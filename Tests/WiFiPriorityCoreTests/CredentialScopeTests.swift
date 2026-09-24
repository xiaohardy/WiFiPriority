import Security
import XCTest
@testable import WiFiPriorityCore

final class CredentialScopeTests: XCTestCase {
    func testUnlistedNetworkNeverTouchesEitherKeychainDomain() {
        var lookups = 0
        let result = ScopedWiFiCredential.find(
            ssid: "Unlisted", allowedSSIDs: ["Preferred"],
            systemLookup: { _ in lookups += 1; return (errSecSuccess, "wrong") },
            userLookup: { _ in lookups += 1; return (errSecSuccess, "wrong") }
        )
        XCTAssertEqual(result, .outsideScope)
        XCTAssertEqual(lookups, 0)
    }

    func testOnlyExactSSIDIsPassedAndUserDomainIsFallbackForMissingItem() {
        var requested = [String]()
        let result = ScopedWiFiCredential.find(
            ssid: "Preferred", allowedSSIDs: ["Preferred", "Backup"],
            systemLookup: { name in requested.append("system:\(name)"); return (errSecItemNotFound, nil) },
            userLookup: { name in requested.append("user:\(name)"); return (errSecSuccess, "test-secret") }
        )
        XCTAssertEqual(result, .password("test-secret"))
        XCTAssertEqual(requested, ["system:Preferred", "user:Preferred"])
    }

    func testDeclinedSystemAccessDoesNotProbeUserDomain() {
        var userLookups = 0
        let result = ScopedWiFiCredential.find(
            ssid: "Preferred", allowedSSIDs: ["Preferred"],
            systemLookup: { _ in (errSecUserCanceled, nil) },
            userLookup: { _ in userLookups += 1; return (errSecSuccess, "wrong") }
        )
        XCTAssertEqual(result, .denied)
        XCTAssertEqual(userLookups, 0)
    }

}
