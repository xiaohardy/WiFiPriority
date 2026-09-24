import Foundation

/// Keeps locally saved Wi-Fi names and diagnostics private to the current user.
public enum PrivateAppStorage {
    public static func protectExistingFiles(in directory: URL, names: [String]) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        for name in names {
            let file = directory.appendingPathComponent(name)
            if manager.fileExists(atPath: file.path) {
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
        }
    }

    public static func write(_ data: Data, to file: URL) throws {
        let directory = file.deletingLastPathComponent()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        // A prior version may have created the directory with the default umask.
        try protectExistingFiles(in: directory, names: [])
        try data.write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public static func singleLine(_ value: String) -> String {
        String(value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
                ? " " : String($0)
        }.joined())
    }
}
