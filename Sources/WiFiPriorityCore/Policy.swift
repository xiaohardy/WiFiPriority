import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let shift = Self(rawValue: 4)
    public static let command = Self(rawValue: 8)
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(UInt8.self)
        guard value & ~UInt8(15) == 0 else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid shortcut modifiers")) }
        rawValue = value
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct PauseShortcut: Codable, Equatable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
    public let key: String

    public static let off = PauseShortcut(keyCode: 0, modifiers: [], key: "", unchecked: true)
    public var isOff: Bool { key.isEmpty }

    private init(keyCode: UInt16, modifiers: ShortcutModifiers, key: String, unchecked: Bool) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }
    public init?(keyCode: UInt16, modifiers: ShortcutModifiers, key: String) {
        let label = key.uppercased()
        let ascii = label.utf8
        guard ascii.count == 1, let character = ascii.first,
              (65...90).contains(character) || (48...57).contains(character),
              keyCode < 128,
              modifiers.rawValue & ~UInt8(15) == 0,
              modifiers.contains(.control),
              (modifiers.contains(.option) || modifiers.contains(.command)) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, key: label, unchecked: true)
    }
    public var displayName: String {
        guard !isOff else { return "—" }
        return (modifiers.contains(.control) ? "⌃" : "") +
            (modifiers.contains(.option) ? "⌥" : "") +
            (modifiers.contains(.shift) ? "⇧" : "") +
            (modifiers.contains(.command) ? "⌘" : "") + key
    }
    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, key }
    public init(from decoder: Decoder) throws {
        if let old = try? decoder.singleValueContainer().decode(String.self) {
            switch old {
            case "controlOptionCommandP": self = Self(keyCode: 35, modifiers: [.control, .option, .command], key: "P")!
            case "controlOptionCommandW": self = Self(keyCode: 13, modifiers: [.control, .option, .command], key: "W")!
            case "controlOptionCommandS": self = Self(keyCode: 1, modifiers: [.control, .option, .command], key: "S")!
            default: self = .off
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .key)
        if key.isEmpty { self = .off; return }
        let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let modifiers = try container.decode(ShortcutModifiers.self, forKey: .modifiers)
        guard let shortcut = Self(keyCode: keyCode, modifiers: modifiers, key: key) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid shortcut"))
        }
        self = shortcut
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(key, forKey: .key)
    }
}

public struct Settings: Codable, Equatable {
    public var networks: [String]
    public var hiddenNetworks: Set<String>
    public var paused: Bool
    public var language: AppLanguage
    public var pauseShortcut: PauseShortcut
    public var credentialReadyNetworks: Set<String>
    public var credentialIdentity: String?
    public init(networks: [String] = [], hiddenNetworks: Set<String> = [], paused: Bool = true,
                language: AppLanguage = .system, pauseShortcut: PauseShortcut = .off,
                credentialReadyNetworks: Set<String> = [], credentialIdentity: String? = nil) throws {
        guard Set(networks).count == networks.count else { throw ValidationError.duplicate }
        guard networks.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 32 }) else {
            throw ValidationError.invalidName
        }
        guard hiddenNetworks.isSubset(of: Set(networks)) else { throw ValidationError.invalidName }
        guard credentialReadyNetworks.isSubset(of: Set(networks)) else { throw ValidationError.invalidName }
        self.networks = networks
        self.hiddenNetworks = hiddenNetworks
        self.paused = paused
        self.language = language
        self.pauseShortcut = pauseShortcut
        self.credentialReadyNetworks = credentialReadyNetworks
        self.credentialIdentity = credentialIdentity
    }
    public enum ValidationError: LocalizedError {
        case duplicate, invalidName
        public var message: StatusMessage { .init(self == .duplicate ? .duplicate : .invalidName) }
        public var errorDescription: String? {
            L10n.text(message, language: .system)
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .language)
        try self.init(
            networks: c.decode([String].self, forKey: .networks),
            hiddenNetworks: c.decodeIfPresent(Set<String>.self, forKey: .hiddenNetworks) ?? [],
            paused: c.decode(Bool.self, forKey: .paused),
            language: raw.flatMap(AppLanguage.init(rawValue:)) ?? .system,
            pauseShortcut: (try? c.decode(PauseShortcut.self, forKey: .pauseShortcut)) ?? .off,
            credentialReadyNetworks: c.decodeIfPresent(Set<String>.self, forKey: .credentialReadyNetworks) ?? [],
            credentialIdentity: c.decodeIfPresent(String.self, forKey: .credentialIdentity)
        )
    }
}

public struct PriorityPolicy {
    public let networks: [String]
    public private(set) var retryAt: [String: TimeInterval] = [:]
    private var failures: [String: Int] = [:]
    private var seen: [String: Int] = [:]
    private var signal: [String: Int] = [:]
    private var disconnected = 0
    private var lastSuccess: TimeInterval = -.infinity
    public init(networks: [String]) { self.networks = networks }

    public mutating func resetObservations() {
        seen = [:]; signal = [:]; disconnected = 0
    }
    public mutating func observe(current: String?, visible: [String: Int]) {
        guard current == nil || networks.contains(current!) else { resetObservations(); return }
        signal = visible
        disconnected = current == nil ? min(disconnected + 1, 2) : 0
        for ssid in networks { seen[ssid] = visible[ssid] == nil ? 0 : min((seen[ssid] ?? 0) + 1, 2) }
        // A successful native/manual association is also evidence that this network recovered.
        if let current { retryAt[current] = nil; failures[current] = nil }
    }
    public func candidate(current: String?, now: TimeInterval, recovering: Bool = false,
                          excluding: Set<String> = []) -> String? {
        let upper: Int
        if let current {
            guard let rank = networks.firstIndex(of: current), now - lastSuccess >= 120 else { return nil }
            upper = rank
        } else {
            guard recovering || disconnected >= 2 else { return nil }
            upper = networks.count
        }
        return networks.prefix(upper).first {
            !excluding.contains($0) && (seen[$0] ?? 0) >= 2 && now >= (retryAt[$0] ?? -.infinity)
                && (current == nil || (signal[$0] ?? -1000) >= -78)
        }
    }
    public mutating func failed(_ ssid: String, now: TimeInterval) {
        let count = min((failures[ssid] ?? 0) + 1, 3)
        failures[ssid] = count
        retryAt[ssid] = now + [300.0, 600.0, 900.0][count - 1]
        // Other candidates keep their evidence, so a failed primary never starves them.
        seen[ssid] = 0
    }
    public mutating func succeeded(_ ssid: String, now: TimeInterval) {
        retryAt[ssid] = nil; failures[ssid] = nil; lastSuccess = now
        resetObservations()
    }
    public var earliestRetry: TimeInterval? { retryAt.values.min() }
}
