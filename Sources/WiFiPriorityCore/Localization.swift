import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system, english = "en", spanish = "es", french = "fr"
    case simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    case german = "de", japanese = "ja", portuguese = "pt-BR"
    public var id: String { rawValue }
    public var nativeName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .german: return "Deutsch"
        case .japanese: return "日本語"
        case .portuguese: return "Português (Brasil)"
        }
    }
}

public enum MessageKey: String, CaseIterable {
    case title
    case subtitle
    case preferred
    case backup
    case currentlyConnected
    case moveUp
    case moveDown
    case remove
    case saveOrder
    case ssidPlaceholder
    case add
    case nearby
    case scanFirst
    case scan
    case scanning
    case credentialsHelp
    case timingHelp
    case limitsHelp
    case permissionButton
    case login
    case enable
    case pause
    case language
    case systemLanguage
    case ok
    case quit
    case settingsMenu
    case previewTitle
    case paused
    case wifiOff
    case configure
    case manual
    case preferredConnected
    case scanFailed
    case changed
    case stopped
    case keeping
    case connected
    case cancelled
    case keepingRetry
    case credentialSetupRequired
    case credentialSetupButton
    case credentialRefreshButton
    case credentialConsentTitle
    case credentialConsentBody
    case credentialConsentApprove
    case credentialConsentCancel
    case credentialPreparing
    case credentialPrepared
    case credentialPartial
    case credentialDenied
    case credentialUnavailable
    case credentialRemovalFailed
    case credentialSetupFirst
    case openSystemWiFi
    case restored
    case recoveryCancelled
    case connectionRestored
    case cooldown
    case checking
    case waiting
    case preview
    case saved
    case loadFailed
    case loginApproval
    case permissionFirst
    case busy
    case permissionNeeded
    case noInterface
    case duplicate
    case invalidName
    case saveFailed
    case loginFailed
    case locationUsage
    case editMenu
    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
    case emptyList
    case scanEmpty
    case inProgress
    case hiddenNetwork
    case testButton
    case testing
    case testHelp
    case savedNetworks
    case savedEmpty
    case refreshSaved
    case pauseBeforeTest
    case testPreview
    case testAlready
    case testConnected
    case testConnectedRestored
    case testConnectedRestoreFailed
    case testFailedPreviousAvailable
    case testFailedDisconnected
    case testFailedRestoreFailed
    case testCancelled
    case testChanged
    case testScanFailed
    case testNetworkNotFound
    case testAssociationRejected
    case testTimedOut
    case shortcut
    case shortcutOff
    case shortcutUnavailable
    case cancelTest
    case hotspotHelp
    case testSystemWaiting
    case testSystemConnected
    case testSystemTimedOut
    case testSystemCancelled
    case testSystemOpenFailed
    case testHelpTitle
    case autoHelpTitle
    case shortcutSet
    case shortcutRecording
    case shortcutClear
    case shortcutHelp
    case shortcutInvalid
}

public struct StatusMessage: Equatable {
    public let key: MessageKey
    public let arguments: [String: String]
    public init(_ key: MessageKey, _ arguments: [String: String] = [:]) {
        self.key = key; self.arguments = arguments
    }
}

public enum L10n {
    private static var resourceBundle: Bundle {
        // A packaged app must be self-contained, never use SwiftPM's absolute
        // development-directory fallback to hide missing release resources.
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("WiFiPriority_WiFiPriorityCore.bundle"),
                  let bundle = Bundle(url: url) else { fatalError("Missing application language resources") }
            return bundle
        }
        return Bundle.module
    }
    private static let catalogs: [AppLanguage: [String: String]] = {
        var result = [AppLanguage: [String: String]]()
        for language in AppLanguage.allCases where language != .system {
            if let url = resourceBundle.url(forResource: language.rawValue, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let values = try? JSONDecoder().decode([String: String].self, from: data) {
                result[language] = values
            }
        }
        return result
    }()
    static func catalog(_ language: AppLanguage) -> [String: String] { catalogs[language] ?? [:] }
    public static func resolve(_ language: AppLanguage, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard language == .system else { return language }
        for tag in preferred {
            let parts = tag.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
            switch parts.first {
            case "zh":
                if parts.contains("hant") { return .traditionalChinese }
                if parts.contains("hans") { return .simplifiedChinese }
                return parts.contains("tw") || parts.contains("hk") || parts.contains("mo") ? .traditionalChinese : .simplifiedChinese
            case "en": return .english
            case "es": return .spanish
            case "fr": return .french
            case "de": return .german
            case "ja": return .japanese
            case "pt": return .portuguese
            default: continue
            }
        }
        return .english
    }
    public static func text(_ message: StatusMessage, language: AppLanguage) -> String {
        let chosen = resolve(language)
        var template = catalog(chosen)[message.key.rawValue] ?? catalog(.english)[message.key.rawValue] ?? message.key.rawValue
        // Replace only placeholders in the template, never content inside an SSID.
        let regex = try! NSRegularExpression(pattern: #"\{([a-zA-Z]+)\}"#)
        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))
        for match in matches.reversed() {
            guard let keyRange = Range(match.range(at: 1), in: template),
                  let range = Range(match.range, in: template),
                  let value = message.arguments[String(template[keyRange])] else { continue }
            template.replaceSubrange(range, with: value)
        }
        return template
    }
}
