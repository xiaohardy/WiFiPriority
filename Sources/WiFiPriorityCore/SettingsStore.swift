import Foundation

public final class SettingsStore {
    public enum StoreError: Error {
        case unreadableSettingsFile
    }

    public let settings: Settings
    public let requiresCredentialReset: Bool
    public private(set) var loadFailed: Bool
    private let file: URL

    public init(file: URL, credentialIdentity: String) {
        self.file = file
        var loaded = try! Settings()
        var failed = false
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                loaded = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: file))
            } catch {
                failed = true
            }
        }
        let needsReset = !failed && loaded.credentialIdentity != credentialIdentity
        if needsReset {
            loaded.paused = true
            loaded.credentialReadyNetworks = []
            loaded.credentialIdentity = nil
        }
        settings = loaded
        loadFailed = failed
        requiresCredentialReset = needsReset
    }

    public func write(_ next: Settings) throws {
        // If decoding failed, keep the original bytes for manual recovery.
        // Saving becomes possible after the unreadable file is moved aside.
        if loadFailed && FileManager.default.fileExists(atPath: file.path) {
            throw StoreError.unreadableSettingsFile
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateAppStorage.write(encoder.encode(next), to: file)
        loadFailed = false
    }
}
