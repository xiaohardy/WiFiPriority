import AppKit
import SwiftUI
import WiFiPriorityCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: [String]
    @State private var draftHidden: Set<String>
    @State private var selected: String?
    @State private var name = ""
    @State private var showTestHelp = false
    @State private var showAutoHelp = false
    @StateObject private var shortcutCapture = ShortcutCapture()
    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.settings.networks)
        _draftHidden = State(initialValue: model.settings.hiddenNetworks)
    }
    private var selectedIndex: Int? { draft.firstIndex(of: selected ?? "") }
    private var listHeight: CGFloat { min(200, max(80, CGFloat(max(draft.count, 1)) * 36 + 18)) }
    private var selectedHidden: Binding<Bool> {
        Binding(
            get: { selected.map { draftHidden.contains($0) } ?? false },
            set: { isHidden in
                guard let selected else { return }
                if isHidden { draftHidden.insert(selected) } else { draftHidden.remove(selected) }
            }
        )
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Image(nsImage: NSApp.applicationIconImage).resizable()
                        .frame(width: 46, height: 46).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.t(.title)).font(.title2.bold())
                        Text(model.t(.subtitle)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.t(.language)).font(.caption).foregroundStyle(.secondary)
                        Picker(model.t(.language), selection: Binding(get: { model.settings.language }, set: { model.setLanguage($0) })) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language == .system ? model.t(.systemLanguage) : language.nativeName).tag(language)
                            }
                        }.labelsHidden().frame(width: 155)
                    }
                }
                List(selection: $selected) {
                    if draft.isEmpty { Text(model.t(.emptyList)).foregroundStyle(.secondary) }
                    ForEach(Array(draft.enumerated()), id: \.element) { index, ssid in
                        HStack {
                            Text(index == 0 ? model.t(.preferred) : model.t(.backup, ["number": String(index)]))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 85, alignment: .leading)
                            Text(ssid).lineLimit(1).help(ssid)
                            Spacer()
                            if draftHidden.contains(ssid) {
                                Image(systemName: "eye.slash").foregroundStyle(.secondary)
                                    .help(model.t(.hiddenNetwork))
                            }
                            if index == 0 { Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityHidden(true) }
                            if model.currentSSID == ssid {
                                Label(model.t(.currentlyConnected), systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                                    .help(model.t(.currentlyConnected))
                            }
                        }.padding(.vertical, 6).tag(ssid)
                    }
                }.frame(height: listHeight).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.25)))
                HStack {
                    Button(model.t(.moveUp)) { move(-1) }.disabled(selectedIndex == nil || selectedIndex == 0)
                    Button(model.t(.moveDown)) { move(1) }.disabled(selectedIndex == nil || selectedIndex == draft.count - 1)
                    Button(model.t(.remove)) {
                        if let selected {
                            draft.removeAll { $0 == selected }
                            draftHidden.remove(selected)
                            self.selected = nil
                        }
                    }.disabled(selected == nil)
                    Spacer()
                    Button(model.t(.saveOrder)) { model.save(networks: draft, hiddenNetworks: draftHidden) }
                        .disabled(model.testing || model.preparingCredentials ||
                            (draft == model.settings.networks && draftHidden == model.settings.hiddenNetworks))
                }
                HStack {
                    Toggle(model.t(.hiddenNetwork), isOn: selectedHidden)
                        .toggleStyle(.checkbox).disabled(selected == nil)
                    Spacer()
                    if model.testing { ProgressView().controlSize(.small) }
                    Button(model.t(model.testing ? .cancelTest : .testButton)) {
                        if model.testing { model.cancelSystemTest() }
                        else if let selected { model.testConnection(selected) }
                    }.disabled(model.preparingCredentials || (selected == nil && !model.testing))
                    Button { showTestHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain).help(model.t(.testHelpTitle))
                        .accessibilityLabel(model.t(.testHelpTitle))
                        .popover(isPresented: $showTestHelp, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(model.t(.testHelpTitle)).font(.headline)
                                Text(model.t(.testHelp))
                                Text(model.t(.hotspotHelp))
                            }.frame(width: 360, alignment: .leading).padding(16)
                        }
                }
                if let result = model.testResult {
                    Text(model.text(result)).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                if let failure = model.testFailure {
                    Text(model.text(failure)).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    TextField(model.t(.ssidPlaceholder), text: $name).onSubmit { add() }.frame(minWidth: 150)
                    Button(model.t(.add)) { add() }.disabled(name.isEmpty)
                    Menu(model.t(.savedNetworks)) {
                        if model.savedNetworks.isEmpty { Text(model.t(.savedEmpty)) }
                        ForEach(model.savedNetworks, id: \.self) { ssid in Button(ssid) { name = ssid } }
                        Divider()
                        Button(model.t(.refreshSaved)) { model.refreshSavedNetworks() }
                    }
                    Menu(model.t(.nearby)) {
                        if model.nearby.isEmpty { Text(model.t(.scanFirst)) }
                        ForEach(model.nearby, id: \.self) { ssid in Button(ssid) { name = ssid } }
                    }
                    Button(model.t(model.scanning ? .scanning : .scan)) { model.scanNearby() }.disabled(model.scanning)
                }
                if model.preparingCredentials {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.text(model.status)).font(.callout)
                    }.padding(10)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                } else if model.status.key == .credentialSetupRequired {
                    HStack(spacing: 10) {
                        Text(model.text(model.status)).font(.callout)
                        Spacer(minLength: 8)
                        Button(model.t(.credentialSetupButton)) { model.beginCredentialSetup() }
                    }.padding(10)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
                Divider()
                HStack {
                    Text(model.t(.shortcut))
                    Text(model.settings.pauseShortcut.isOff ? model.t(.shortcutOff) : model.settings.pauseShortcut.displayName)
                        .font(.system(.body, design: .monospaced)).frame(minWidth: 90, alignment: .leading)
                    Button(model.t(shortcutCapture.recording ? .shortcutRecording : .shortcutSet)) {
                        if shortcutCapture.recording { stopRecording() }
                        else {
                            model.beginShortcutRecording()
                            shortcutCapture.start { event in handleShortcutKey(event) }
                        }
                    }
                    Button(model.t(.shortcutClear)) { _ = model.setPauseShortcut(.off) }
                        .disabled(shortcutCapture.recording || model.settings.pauseShortcut.isOff)
                }
                if shortcutCapture.recording {
                    Text(model.t(.shortcutHelp)).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.t(.permissionButton)) { model.requestPermission() }
                    Toggle(model.t(.login), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                        .toggleStyle(.checkbox).disabled(model.preview)
                    Spacer()
                    if model.preparingCredentials { ProgressView().controlSize(.small) }
                    Button(model.t(model.credentialsPrepared ? .credentialRefreshButton : .credentialSetupButton)) {
                        model.beginCredentialSetup(refreshExisting: model.credentialsPrepared)
                    }
                        .disabled(model.preview || model.testing || model.preparingCredentials ||
                            model.settings.networks.isEmpty || draft != model.settings.networks ||
                            draftHidden != model.settings.hiddenNetworks)
                    Button { showAutoHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain).help(model.t(.autoHelpTitle))
                        .accessibilityLabel(model.t(.autoHelpTitle))
                        .popover(isPresented: $showAutoHelp, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(model.t(.autoHelpTitle)).font(.headline)
                                Text(model.t(.credentialsHelp))
                                Text(model.t(.timingHelp))
                                Text(model.t(.limitsHelp))
                            }.frame(width: 360, alignment: .leading).padding(16)
                        }
                    Button(model.t(model.settings.paused ? .enable : .pause)) { model.togglePause() }
                        .disabled(model.testing || model.preparingCredentials || (model.settings.paused &&
                            (model.settings.networks.isEmpty || draft != model.settings.networks ||
                             draftHidden != model.settings.hiddenNetworks)))
                }
            }.padding(24)
        }
        .frame(minWidth: 700)
        .alert("WiFi Priority", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(model.t(.ok)) { model.message = nil }
        } message: { Text(model.message.map(model.text) ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stopRecording() }
        .onDisappear { stopRecording() }
    }
    private func stopRecording() {
        guard shortcutCapture.recording else { return }
        shortcutCapture.stop(); model.endShortcutRecording()
    }
    private func handleShortcutKey(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return } // Escape cancels.
        if event.keyCode == 51 || event.keyCode == 117 {
            _ = model.setPauseShortcut(.off); stopRecording(); return
        }
        guard let shortcut = ShortcutCapture.shortcut(from: event) else {
            model.message = .init(.shortcutInvalid); stopRecording(); return
        }
        _ = model.setPauseShortcut(shortcut)
        stopRecording()
    }
    private func add() {
        guard !name.isEmpty else { return }
        guard !draft.contains(name) else { model.message = .init(.duplicate); return }
        guard name.utf8.count <= 32, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.message = .init(.invalidName); return
        }
        draft.append(name); selected = name; name = ""
    }
    private func move(_ delta: Int) {
        guard let i = selectedIndex, draft.indices.contains(i + delta) else { return }
        draft.swapAt(i, i + delta)
    }
}
