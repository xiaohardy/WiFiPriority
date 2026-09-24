import XCTest
@testable import WiFiPriorityCore

final class ScanLoadTests: XCTestCase {
    func testConnectedBackupUsesThirtySecondScanCadence() {
        var cadence = ScanCadence()
        XCTAssertTrue(cadence.shouldScan(current: "Backup", preferred: "Main", now: 0))
        XCTAssertFalse(cadence.shouldScan(current: "Backup", preferred: "Main", now: 15))
        XCTAssertTrue(cadence.shouldScan(current: "Backup", preferred: "Main", now: 30))
        XCTAssertTrue(cadence.shouldScan(current: "Other", preferred: "Main", now: 31))
        XCTAssertTrue(cadence.shouldScan(current: nil, preferred: "Main", now: 32))
        XCTAssertTrue(cadence.shouldScan(current: "Backup", preferred: "Main", now: 33))
        XCTAssertFalse(cadence.shouldScan(current: "Backup", preferred: "Main", now: 34))
        cadence.reset()
        XCTAssertTrue(cadence.shouldScan(current: "Backup", preferred: "Main", now: 34))
    }

    func testHiddenScanTargetsOnlyHigherPriorityNetworks() {
        let order = ["Main", "Hotspot", "Hidden backup"]
        let hidden: Set<String> = ["Main", "Hidden backup"]
        XCTAssertEqual(PriorityScanScope.directedNames(networks: order, hidden: hidden,
                                                       current: "Hotspot"), ["Main"])
        XCTAssertEqual(PriorityScanScope.directedNames(networks: order, hidden: hidden,
                                                       current: "Main"), [])
        XCTAssertEqual(PriorityScanScope.directedNames(networks: order, hidden: hidden,
                                                       current: nil), ["Main", "Hidden backup"])
        XCTAssertEqual(PriorityScanScope.directedNames(networks: order, hidden: hidden,
                                                       current: "Unlisted"), ["Main", "Hidden backup"])
    }
}
