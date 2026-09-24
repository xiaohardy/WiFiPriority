import XCTest
@testable import WiFiPriorityCore

final class SettingsStoreTests: XCTestCase {
    func testUnreadableSettingsRemainUntouchedEvenWhenSavingIsAttempted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        let original = Data(#"{"networks":["Home Wi-Fi"],"paused":"invalid"}"#.utf8)
        try original.write(to: file)

        let store = SettingsStore(file: file, credentialIdentity: "test-identity")
        XCTAssertTrue(store.loadFailed)
        XCTAssertFalse(store.requiresCredentialReset)
        XCTAssertTrue(store.settings.paused)
        XCTAssertTrue(store.settings.networks.isEmpty)
        XCTAssertThrowsError(try store.write(try Settings(networks: ["New Wi-Fi"])))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testValidSettingsResetOnlyCredentialStateWhenIdentityChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        let previous = try Settings(networks: ["Home Wi-Fi"], paused: false,
                                    credentialReadyNetworks: ["Home Wi-Fi"], credentialIdentity: "old-identity")
        try JSONEncoder().encode(previous).write(to: file)

        let store = SettingsStore(file: file, credentialIdentity: "new-identity")
        XCTAssertFalse(store.loadFailed)
        XCTAssertTrue(store.requiresCredentialReset)
        XCTAssertEqual(store.settings.networks, ["Home Wi-Fi"])
        XCTAssertTrue(store.settings.paused)
        XCTAssertTrue(store.settings.credentialReadyNetworks.isEmpty)
        XCTAssertNil(store.settings.credentialIdentity)
        try store.write(store.settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data(contentsOf: file)), store.settings)
    }
}
