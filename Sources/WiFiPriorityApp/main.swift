import AppKit
import SwiftUI
import WiFiPriorityCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(preview: CommandLine.arguments.contains("--preview"))
    var item: NSStatusItem!
    var window: NSWindow?
    let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let credentialSetupItem = NSMenuItem(title: "", action: #selector(prepareCredentialAccess), keyEquivalent: "")
    let pause = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
    let settingsItem = NSMenuItem(title: "", action: #selector(showSettings), keyEquivalent: ",")
    let quitItem = NSMenuItem(title: "", action: #selector(quitApp), keyEquivalent: "q")
    let hotKey = PauseHotKey()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hotKey.onPress = { [weak self] in self?.model.togglePause() }
        model.applyShortcut = { [weak self] shortcut in self?.hotKey.set(shortcut) ?? false }
        if !model.preview && !hotKey.set(model.settings.pauseShortcut) {
            model.message = .init(.shortcutUnavailable)
            model.setPauseShortcut(.off)
        }
        let menu = NSMenu(); menu.autoenablesItems = false; status.isEnabled = false
        menu.addItem(status)
        credentialSetupItem.target = self; menu.addItem(credentialSetupItem)
        menu.addItem(.separator())
        settingsItem.target = self; menu.addItem(settingsItem)
        pause.target = self; menu.addItem(pause)
        quitItem.target = self; menu.addItem(quitItem); item.menu = menu
        model.changed = { [weak self] in self?.refreshMenu() }
        refreshMenu()
        if model.settings.networks.isEmpty || model.preview { showSettings() }
        model.tick()
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshLoginStatus() }
    func refreshMenu() {
        status.title = model.text(model.status); item?.button?.toolTip = status.title
        credentialSetupItem.title = model.t(model.credentialsPrepared ? .credentialRefreshButton : .credentialSetupButton)
        credentialSetupItem.isHidden = model.status.key != .credentialSetupRequired
        let indicator = StatusIndicatorState(networks: model.settings.networks,
                                             currentSSID: model.currentSSID,
                                             paused: model.settings.paused)
        item?.button?.image = StatusIcon.make(state: indicator, paused: model.settings.paused)
        item?.button?.title = ""
        item?.button?.appearsDisabled = false
        let shortcut = model.settings.pauseShortcut
        pause.title = model.t(model.settings.paused ? .enable : .pause) +
            (shortcut.isOff ? "" : "  \(shortcut.displayName)")
        pause.isEnabled = !model.testing && !model.preparingCredentials &&
            (!model.settings.paused || !model.settings.networks.isEmpty)
        settingsItem.title = model.t(.settingsMenu); quitItem.title = model.t(.quit)
        window?.title = model.preview ? model.t(.previewTitle) : "WiFi Priority"
        // A native main menu also provides the normal text-editing shortcuts.
        let bar = NSMenu()
        let appRoot = NSMenuItem(title: "WiFi Priority", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: model.t(.quit), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit); appRoot.submenu = appMenu; bar.addItem(appRoot)
        let editRoot = NSMenuItem(title: model.t(.editMenu), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: model.t(.editMenu))
        for (key, action, shortcut) in [(MessageKey.undo, "undo:", "z"), (.redo, "redo:", "Z"), (.cut, "cut:", "x"), (.copy, "copy:", "c"), (.paste, "paste:", "v"), (.selectAll, "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: model.t(key), action: Selector(action), keyEquivalent: shortcut))
        }
        editRoot.submenu = edit; bar.addItem(editRoot); NSApp.mainMenu = bar
    }
    @objc func showSettings() {
        model.refreshLoginStatus()
        model.refreshSavedNetworks()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 460), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = model.preview ? model.t(.previewTitle) : "WiFi Priority"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.contentMinSize = NSSize(width: 700, height: 410)
            w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggle() { model.togglePause() }
    @objc func prepareCredentialAccess() {
        showSettings()
        model.beginCredentialSetup(refreshExisting: model.credentialsPrepared)
    }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.prepareToQuit { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

// Offline bundle check for release validation; never constructs a radio or requests permission.
if let index = CommandLine.arguments.firstIndex(of: "--render-status-icons"),
   CommandLine.arguments.indices.contains(index + 1) {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (count, active) in [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2), (12, 11), (14, 12)] {
        for paused in [false, true] {
            let networks = (0..<count).map { "Network \($0)" }
            let indicator = StatusIndicatorState(networks: networks,
                currentSSID: count == 0 ? nil : networks[active], paused: paused)
            let icon = StatusIcon.make(state: indicator, paused: paused)
            let scale = 8
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                          pixelsWide: Int(icon.size.width) * scale,
                                          pixelsHigh: Int(icon.size.height) * scale,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = icon.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            icon.draw(in: NSRect(origin: .zero, size: icon.size))
            NSGraphicsContext.restoreGraphicsState()
            let name = "status-\(count)-active\(active)-\(paused ? "paused" : "running").png"
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
        }
    }
} else if CommandLine.arguments.contains("--check-shortcut-conflict") {
    _ = NSApplication.shared
    let first = PauseHotKey(), second = PauseHotKey()
    let candidates: [(UInt16, String)] = [(11, "B"), (16, "Y"), (28, "8")]
    guard let candidate = candidates.compactMap({ PauseShortcut(keyCode: $0.0,
        modifiers: [.control, .option, .shift, .command], key: $0.1) }).first(where: { first.set($0) }) else {
        fatalError("Could not register a test hot key")
    }
    guard let alternate = candidates.compactMap({ PauseShortcut(keyCode: $0.0,
        modifiers: [.control, .option, .shift, .command], key: $0.1) })
        .first(where: { $0 != candidate && second.set($0) }),
          !second.set(candidate), second.active == alternate, first.active == candidate else {
        fatalError("A conflicting hot key was accepted")
    }
    print("Hot key conflict detection works")
} else if CommandLine.arguments.contains("--check-localizations") {
    for language in AppLanguage.allCases where language != .system {
        let value = L10n.text(.init(.title), language: language)
        guard value != MessageKey.title.rawValue else { fatalError("Missing localization resources") }
        print("\(language.rawValue): \(value)")
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
