import Foundation
import Security
import XCTest
@testable import WiFiPriorityCore

final class WiFiCredentialVaultTests: XCTestCase {
    func testOwnKeychainItemCanBeReadSilentlyUpdatedAndRemoved() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifipriority-test-\(UUID().uuidString).keychain-db")
        let key = "temporary-test-password"
        var keychain: SecKeychain?
        let status = path.path.withCString { name in
            key.withCString { password in
                SecKeychainCreate(name, UInt32(key.utf8.count), password, false, nil, &keychain)
            }
        }
        XCTAssertEqual(status, errSecSuccess)
        let isolated = try XCTUnwrap(keychain)
        defer { _ = SecKeychainDelete(isolated) }

        let vault = WiFiCredentialVault(keychain: isolated, allowedSSIDs: ["Test Network"],
                                        serviceName: "org.wifipriority.test.\(UUID().uuidString)")
        XCTAssertEqual(vault.read("Other"), .outsideScope)
        XCTAssertEqual(vault.store("sample-secret", for: "Other"), errSecParam)
        XCTAssertEqual(vault.read("Test Network"), .missing)
        XCTAssertEqual(vault.store("sample-secret", for: "Test Network"), errSecSuccess)
        XCTAssertEqual(vault.read("Test Network"), .password("sample-secret"))
        XCTAssertEqual(vault.store("changed-secret", for: "Test Network"), errSecSuccess)
        XCTAssertEqual(vault.read("Test Network"), .password("changed-secret"))
        XCTAssertEqual(vault.delete("Test Network"), errSecSuccess)
        XCTAssertEqual(vault.read("Test Network"), .missing)
    }
}
