import AppKit
import CoreLocation
import ServiceManagement
import Combine
import Security
import WiFiPriorityCore

final class AppModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var settings: Settings
    @Published var status = StatusMessage(.paused)
    @Published private(set) var currentSSID: String?
    @Published var nearby: [String] = []
    @Published var savedNetworks: [String] = []
    @Published var scanning = false
    @Published var testing = false
    @Published var preparingCredentials = false
    @Published var testResult: StatusMessage?
    @Published var testFailure: StatusMessage?
    @Published var message: StatusMessage?
    @Published var loginEnabled = false
    var changed: (() -> Void)?
    var applyShortcut: ((PauseShortcut) -> Bool)?
    let preview: Bool
    private let location = CLLocationManager()
    private let queue = DispatchQueue(label: "org.wifipriority.worker")
    private let logQueue = DispatchQueue(label: "org.wifipriority.log")
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WiFiPriorityOpen")
    private let settingsStore: SettingsStore?
    private var engine: SwitchEngine
    private var timer: Timer?
    private var busy = false
    private var currentReadPending = false
    private var scanCadence = ScanCadence()
    private var sleeping = false
    private var generation = 0
    private var observers = [NSObjectProtocol]()
    private var systemTestTarget: String?
    private var systemTestDeadline: TimeInterval = 0
    private var systemTestTimer: Timer?
    private var systemTestPollPending = false
    private static let currentCredentialIdentity: String = {
        // Keychain ACLs track the code's designated requirement. A stable
        // signing identity survives updates; an ad hoc signature contains a
        // build-specific hash and therefore requires fresh authorization.
        let unknown = "unidentified:\(UUID().uuidString)"
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return unknown }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return unknown }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return unknown }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let text else { return unknown }
        // Version the preparation marker because 0.8.x marked original
        // System Keychain access as ready without creating an app-owned copy.
        return "vault-v1:designated:\(text as String)"
    }()
    var credentialsPrepared: Bool { settings.credentialIdentity == Self.currentCredentialIdentity }

    init(preview: Bool) {
        self.preview = preview
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WiFiPriorityOpen/settings.json")
        var loaded: Settings
        var loadError: StatusMessage?
        var resetCredentialAccess = false
        if preview {
            loaded = try! Settings(networks: ["Home Wi-Fi", "Mobile Hotspot", "Backup Wi-Fi"])
            settingsStore = nil
            if let index = CommandLine.arguments.firstIndex(of: "--language"), CommandLine.arguments.indices.contains(index + 1) {
                loaded.language = AppLanguage(rawValue: CommandLine.arguments[index + 1]) ?? .system
            }
        } else {
            let store = SettingsStore(file: file, credentialIdentity: Self.currentCredentialIdentity)
            settingsStore = store
            loaded = store.settings
            loadError = store.loadFailed ? .init(.loadFailed) : nil
            resetCredentialAccess = store.requiresCredentialReset
        }
        settings = loaded
        engine = SwitchEngine(networks: loaded.networks)
        super.init()
        message = loadError
        location.delegate = self
        if preview { currentSSID = loaded.networks.first; status = .init(.preview); return }
        queue.async {
            try? PrivateAppStorage.protectExistingFiles(in: self.directory,
                                                         names: ["settings.json", "events.log"])
        }
        if resetCredentialAccess { try? persist(loaded) }
        refreshLoginStatus()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.testing { self.finishSystemTest(.init(.testSystemCancelled)) }
            self.sleeping = true; self.generation += 1
            self.queue.async { self.engine.resetObservations() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = false
            self.scanCadence.reset()
            self.queue.async { self.engine.resetObservations() }
            self.tick()
        })
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
    }
    func t(_ key: MessageKey, _ arguments: [String: String] = [:]) -> String {
        L10n.text(.init(key, arguments), language: settings.language)
    }
    func text(_ message: StatusMessage) -> String { L10n.text(message, language: settings.language) }
    var authorized: Bool { location.authorizationStatus == .authorizedAlways }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        generation += 1
        tick()
    }
    func requestPermission() {
        guard !preview else { return }
        NSApp.activate(ignoringOtherApps: true)
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        else if !authorized, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
    private func persist(_ next: Settings) throws {
        try settingsStore?.write(next)
    }
    func setLanguage(_ language: AppLanguage) {
        var next = settings; next.language = language
        do {
            try persist(next)
            settings = next
            // Language changes must not reset retry cooldowns or cancel an active join.
            changed?()
        } catch { message = .init(.saveFailed) }
    }
    @discardableResult
    func setPauseShortcut(_ shortcut: PauseShortcut) -> Bool {
        guard shortcut != settings.pauseShortcut else { return true }
        let previous = settings.pauseShortcut
        guard preview || applyShortcut?(shortcut) == true else {
            message = .init(.shortcutUnavailable); return false
        }
        var next = settings; next.pauseShortcut = shortcut
        do { try persist(next); settings = next; changed?(); return true }
        catch {
            if !preview { _ = applyShortcut?(previous) }
            message = .init(.saveFailed); return false
        }
    }
    func beginShortcutRecording() {
        if !preview { _ = applyShortcut?(.off) }
    }
    func endShortcutRecording() {
        if !preview { _ = applyShortcut?(settings.pauseShortcut) }
    }
    func save(networks: [String], hiddenNetworks: Set<String>? = nil, paused: Bool? = nil) {
        guard !preparingCredentials else { message = .init(.busy); return }
        do {
            let removedNames = Set(settings.networks).subtracting(networks)
            let next = try Settings(
                networks: networks,
                hiddenNetworks: hiddenNetworks ?? settings.hiddenNetworks,
                paused: paused ?? settings.paused,
                language: settings.language,
                pauseShortcut: settings.pauseShortcut,
                credentialReadyNetworks: settings.credentialReadyNetworks.intersection(networks),
                credentialIdentity: settings.credentialIdentity
            )
            try persist(next)
            let orderChanged = settings.networks != next.networks || settings.hiddenNetworks != next.hiddenNetworks
            settings = next; generation += 1; scanCadence.reset()
            queue.async {
                if !removedNames.isEmpty {
                    let (_, vault) = WiFiCredentialVault.login(allowedSSIDs: removedNames)
                    for name in removedNames {
                        let result = vault?.delete(name) ?? errSecNotAvailable
                        if result != errSecSuccess {
                            DispatchQueue.main.async {
                                self.message = .init(.credentialRemovalFailed,
                                                     ["network": name, "code": String(result)])
                            }
                        }
                    }
                }
                if orderChanged { self.engine = SwitchEngine(networks: next.networks) }
                else { self.engine.resetObservations() }
            }
            report(.init(preview ? .preview : (next.paused ? .paused : .saved)))
            testResult = nil
            testFailure = nil
            if !next.paused && !authorized { requestPermission() }
            tick()
        } catch let error as Settings.ValidationError { message = error.message }
        catch { message = .init(.saveFailed) }
    }
    func togglePause() {
        guard !testing && !preparingCredentials else { message = .init(.busy); return }
        if !settings.paused {
            // Stop immediately even if the disk cannot persist the pause preference.
            settings.paused = true; generation += 1
            queue.async { self.engine.resetObservations() }
            report(.init(preview ? .preview : .paused))
            do { try persist(settings) } catch { message = .init(.saveFailed) }
        } else if credentialsPrepared { save(networks: settings.networks, paused: false) }
        else { beginCredentialSetup() }
    }
    func beginCredentialSetup(refreshExisting: Bool = false) {
        guard !preview else { message = .init(.preview); return }
        guard !busy && !testing && !preparingCredentials else { message = .init(.busy); return }
        guard !settings.networks.isEmpty else { message = .init(.configure); return }
        if !settings.paused {
            settings.paused = true; generation += 1
            queue.async { self.engine.resetObservations() }
            report(.init(.paused))
            do { try persist(settings) }
            catch { message = .init(.saveFailed); return }
        }
        NSApp.activate(ignoringOtherApps: true)
        message = nil
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = t(.credentialConsentTitle)
        let previewNames = settings.networks.prefix(5).enumerated().map {
            "\($0.offset + 1). \($0.element)"
        }.joined(separator: "\n")
        let more = settings.networks.count > 5 ? "\n…" : ""
        alert.informativeText = t(.credentialConsentBody, ["count": String(settings.networks.count)]) +
            "\n\n" + previewNames + more
        alert.addButton(withTitle: t(.credentialConsentApprove))
        alert.addButton(withTitle: t(.credentialConsentCancel))
        switch alert.runModal() {
        case .alertFirstButtonReturn: prepareCredentials(refreshExisting: refreshExisting)
        default: break
        }
    }
    private func prepareCredentials(refreshExisting: Bool) {
        busy = true; preparingCredentials = true; generation += 1
        let names = settings.networks
        let allowed = Set(names)
        queue.async {
            var ready = Set<String>()
            var missing = [String]()
            var problem: StatusMessage?
            let (vaultStatus, vaultValue) = WiFiCredentialVault.login(allowedSSIDs: allowed)
            guard let vault = vaultValue else {
                DispatchQueue.main.async {
                    self.busy = false; self.preparingCredentials = false
                    self.message = .init(.credentialUnavailable,
                                         ["network": names.first ?? "", "code": String(vaultStatus)])
                    self.report(.init(.paused))
                }
                return
            }
            preflight: for (offset, name) in names.enumerated() {
                DispatchQueue.main.sync {
                    self.report(.init(.credentialPreparing, [
                        "network": name,
                        "index": String(offset + 1),
                        "count": String(names.count)
                    ]))
                }
                let result = autoreleasepool {
                    CredentialPreparation.prepare(
                        ssid: name, allowedSSIDs: allowed,
                        refreshExisting: refreshExisting,
                        cacheLookup: { vault.read($0) },
                        sourceLookup: { SystemRadio.requestSavedCredential(for: $0, allowedSSIDs: allowed) },
                        cacheStore: { vault.store($1, for: $0) }
                    )
                }
                switch result {
                case .password: ready.insert(name)
                case .missing: missing.append(name)
                case .denied:
                    problem = .init(.credentialDenied, ["network": name]); break preflight
                case .outsideScope:
                    problem = .init(.credentialDenied, ["network": name]); break preflight
                case .unavailable(let code):
                    problem = .init(.credentialUnavailable, ["network": name, "code": String(code)])
                    break preflight
                }
            }
            DispatchQueue.main.async {
                self.busy = false; self.preparingCredentials = false
                if let problem { self.message = problem; self.report(.init(.paused)); return }
                var next = self.settings
                next.credentialReadyNetworks = ready
                next.credentialIdentity = Self.currentCredentialIdentity
                // A network without a saved password may be open. It can still
                // be joined automatically after the ordinary scan confirms that.
                next.paused = false
                do {
                    try self.persist(next)
                    self.settings = next
                    self.generation += 1
                    self.scanCadence.reset()
                    self.queue.async { self.engine.resetObservations() }
                    self.report(.init(next.paused ? .paused : .saved))
                    self.message = missing.isEmpty
                        ? .init(.credentialPrepared, ["count": String(ready.count)])
                        : .init(.credentialPartial, ["count": String(ready.count), "networks": missing.joined(separator: ", ")])
                    if !next.paused { self.tick() }
                } catch { self.message = .init(.saveFailed); self.report(.init(.paused)) }
            }
        }
    }
    func prepareToQuit(_ completion: @escaping () -> Void) {
        timer?.invalidate(); sleeping = true; generation += 1
        systemTestTimer?.invalidate(); systemTestTarget = nil
        // CoreWLAN scans and associations are synchronous. Do not keep Quit
        // waiting indefinitely for an in-flight system operation.
        var completed = false
        let finish = { if !completed { completed = true; completion() } }
        queue.async { DispatchQueue.main.async(execute: finish) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: finish)
    }
    func refreshLoginStatus() {
        guard !preview else { return }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func refreshSavedNetworks() {
        if preview { savedNetworks = ["Home Wi-Fi", "Mobile Hotspot", "Backup Wi-Fi"]; return }
        queue.async {
            let names = SystemRadio()?.savedNetworkNames ?? []
            DispatchQueue.main.async { self.savedNetworks = names }
        }
    }
    func setLogin(_ enabled: Bool) {
        guard !preview else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            if SMAppService.mainApp.status == .requiresApproval {
                message = .init(.loginApproval)
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { refreshLoginStatus(); message = .init(.loginFailed) }
    }
    func scanNearby() {
        guard !preview else { nearby = ["Home Wi-Fi", "Mobile Hotspot", "Backup Wi-Fi"]; return }
        guard authorized else { requestPermission(); message = .init(.permissionFirst); return }
        guard !busy else { message = .init(.busy); return }
        busy = true; scanning = true
        let directedSSIDs = settings.networks.filter { settings.hiddenNetworks.contains($0) }
        queue.async {
            let result = Result { () -> [String] in
                guard let radio = SystemRadio(directedSSIDs: directedSSIDs), radio.powered else { return [] }
                return try radio.scan().keys.sorted()
            }
            DispatchQueue.main.async {
                self.busy = false; self.scanning = false
                switch result {
                case .success(let names):
                    self.nearby = names
                    if names.isEmpty { self.message = .init(.scanEmpty) }
                case .failure: self.message = .init(.scanFailed)
                }
            }
        }
    }
    func testConnection(_ ssid: String) {
        guard settings.paused else { message = .init(.pauseBeforeTest); return }
        guard !busy else { message = .init(.busy); return }
        guard authorized || preview else { requestPermission(); message = .init(.permissionFirst); return }
        if preview { testResult = .init(.testPreview); testFailure = nil; return }
        guard openSystemWiFi() else {
            testResult = .init(.testSystemOpenFailed); testFailure = nil; return
        }
        busy = true; testing = true; testResult = nil; testFailure = nil; changed?()
        systemTestTarget = ssid
        systemTestDeadline = ProcessInfo.processInfo.systemUptime + 120
        testResult = .init(.testSystemWaiting, ["network": ssid])
        systemTestTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollSystemTest()
        }
        pollSystemTest()
    }
    @discardableResult
    func openSystemWiFi() -> Bool {
        guard !preview,
              let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") else { return false }
        let opened = NSWorkspace.shared.open(url)
        if !opened { message = .init(.testSystemOpenFailed) }
        return opened
    }
    func cancelSystemTest() { if testing { finishSystemTest(.init(.testSystemCancelled)) } }
    private func finishSystemTest(_ result: StatusMessage) {
        systemTestTimer?.invalidate(); systemTestTimer = nil
        systemTestTarget = nil; systemTestPollPending = false
        busy = false; testing = false; testResult = result; testFailure = nil
        queue.async { self.engine.resetObservations() }
        changed?()
    }
    private func pollSystemTest() {
        guard let target = systemTestTarget else { return }
        guard ProcessInfo.processInfo.systemUptime < systemTestDeadline else {
            finishSystemTest(.init(.testSystemTimedOut, ["network": target])); return
        }
        guard !systemTestPollPending else { return }
        systemTestPollPending = true
        queue.async {
            let radio = SystemRadio()
            let current = radio?.current
            DispatchQueue.main.async {
                guard self.systemTestTarget == target else { return }
                self.systemTestPollPending = false
                self.setCurrentSSID(current)
                if radio == nil { self.finishSystemTest(.init(.noInterface)) }
                else if current == target { self.finishSystemTest(.init(.testSystemConnected, ["network": target])) }
            }
        }
    }
    private func permitted(_ token: Int) -> Bool {
        DispatchQueue.main.sync { !self.settings.paused && !self.sleeping && self.authorized && self.generation == token }
    }
    private func setCurrentSSID(_ value: String?) {
        guard currentSSID != value else { return }
        scanCadence.reset()
        currentSSID = value
        changed?()
    }
    private func observeCurrentNetwork() {
        guard !currentReadPending else { return }
        currentReadPending = true
        queue.async {
            let radio = SystemRadio()
            let current = radio?.powered == true ? radio?.current : nil
            DispatchQueue.main.async {
                self.currentReadPending = false
                if !self.sleeping && self.authorized {
                    let changed = self.currentSSID != current
                    self.setCurrentSSID(current)
                    if changed && !self.settings.paused { self.tick() }
                }
            }
        }
    }
    func tick() {
        guard !preview, !busy, !sleeping else { return }
        guard authorized else {
            setCurrentSSID(nil)
            if !settings.paused { report(.init(.permissionNeeded)) }
            return
        }
        if settings.paused { observeCurrentNetwork(); return }
        if !scanCadence.shouldScan(current: currentSSID, preferred: settings.networks.first,
                                   now: ProcessInfo.processInfo.systemUptime) {
            observeCurrentNetwork()
            return
        }
        busy = true
        let token = generation
        let prioritySSIDs = settings.networks
        let directedSSIDs = prioritySSIDs.filter { settings.hiddenNetworks.contains($0) }
        let readySSIDs = credentialsPrepared ? settings.credentialReadyNetworks : []
        queue.async {
            let result: StatusMessage
            let current: String?
            if let radio = SystemRadio(directedSSIDs: directedSSIDs,
                                       prioritySSIDs: prioritySSIDs,
                                       credentialReadySSIDs: readySSIDs) {
                result = self.engine.tick(radio: radio, now: { ProcessInfo.processInfo.systemUptime }, permitted: { self.permitted(token) })
                current = radio.powered ? radio.current : nil
            } else { result = .init(.noInterface); current = nil }
            DispatchQueue.main.async {
                self.busy = false
                if self.generation == token {
                    self.setCurrentSSID(current)
                    if result.key == .credentialSetupRequired {
                        var next = self.settings
                        if let network = result.arguments["network"] {
                            next.credentialReadyNetworks.remove(network)
                        }
                        next.credentialIdentity = nil
                        next.paused = true
                        self.settings = next
                        self.generation += 1
                        do { try self.persist(next) }
                        catch {
                            // Do not retry a denied lookup from a timer after a
                            // failed save. Keep the safer in-memory state.
                            self.message = .init(.saveFailed)
                        }
                    }
                    self.report(result)
                }
            }
        }
    }
    func report(_ value: StatusMessage) {
        guard value != status else { return }
        status = value; changed?()
        guard !preview else { return }
        // Local-only bounded log; it contains SSIDs and is never automatically shared.
        let file = directory.appendingPathComponent("events.log")
        let entry = "\(ISO8601DateFormatter().string(from: Date())) " +
            PrivateAppStorage.singleLine(L10n.text(value, language: .english)) + "\n"
        logQueue.async {
            var log = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if log.utf8.count > 64_000 { log = String(log.suffix(16_000)) }
            log += entry
            try? PrivateAppStorage.write(Data(log.utf8), to: file)
        }
    }
}
