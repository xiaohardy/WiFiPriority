import Security
import XCTest
@testable import WiFiPriorityCore

final class CredentialPreparationTests: XCTestCase {
    func testAuthorizedCredentialIsCachedOnceAndReusedWithoutAnotherSystemRead() {
        var cached: String?
        var sourceReads = 0
        var stores = 0
        let prepare = {
            CredentialPreparation.prepare(
                ssid: "Preferred", allowedSSIDs: ["Preferred"],
                cacheLookup: { _ in cached.map(CredentialLookupResult.password) ?? .missing },
                sourceLookup: { _ in sourceReads += 1; return .password("sample-password") },
                cacheStore: { _, password in
                    stores += 1
                    cached = password
                    return errSecSuccess
                }
            )
        }

        XCTAssertEqual(prepare(), .password("sample-password"))
        XCTAssertEqual(prepare(), .password("sample-password"))
        XCTAssertEqual(sourceReads, 1)
        XCTAssertEqual(stores, 1)
    }

    func testOutOfScopeNetworkCannotReadOrStoreEitherCredential() {
        var calls = 0
        let result = CredentialPreparation.prepare(
            ssid: "Other", allowedSSIDs: ["Preferred"],
            cacheLookup: { _ in calls += 1; return .missing },
            sourceLookup: { _ in calls += 1; return .password("sample-password") },
            cacheStore: { _, _ in calls += 1; return errSecSuccess }
        )
        XCTAssertEqual(result, .outsideScope)
        XCTAssertEqual(calls, 0)
    }

    func testFailedCacheWriteDoesNotCountAsPrepared() {
        let result = CredentialPreparation.prepare(
            ssid: "Preferred", allowedSSIDs: ["Preferred"],
            cacheLookup: { _ in .missing },
            sourceLookup: { _ in .password("sample-password") },
            cacheStore: { _, _ in errSecNotAvailable }
        )
        XCTAssertEqual(result, .unavailable(errSecNotAvailable))
    }

    func testDeclinedSystemReadDoesNotCreateCache() {
        var writes = 0
        let result = CredentialPreparation.prepare(
            ssid: "Preferred", allowedSSIDs: ["Preferred"],
            cacheLookup: { _ in .missing },
            sourceLookup: { _ in .denied },
            cacheStore: { _, _ in writes += 1; return errSecSuccess }
        )
        XCTAssertEqual(result, .denied)
        XCTAssertEqual(writes, 0)
    }

    func testExplicitRefreshReplacesAnOutdatedSavedPassword() {
        var cached = "old-password"
        var sourceReads = 0
        let result = CredentialPreparation.prepare(
            ssid: "Preferred", allowedSSIDs: ["Preferred"], refreshExisting: true,
            cacheLookup: { _ in .password(cached) },
            sourceLookup: { _ in sourceReads += 1; return .password("new-password") },
            cacheStore: { _, password in cached = password; return errSecSuccess }
        )
        XCTAssertEqual(result, .password("new-password"))
        XCTAssertEqual(sourceReads, 1)
    }
}
