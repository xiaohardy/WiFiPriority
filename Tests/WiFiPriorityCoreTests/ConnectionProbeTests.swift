import XCTest
@testable import WiFiPriorityCore

final class ConnectionProbeTests: XCTestCase {
    func testHiddenNameIsTriedDirectlyAndPreviousConnectionRestored() {
        let radio = FakeRadio()
        radio.current = "Main"
        radio.visible = [:]
        radio.results = ["Hidden": true, "Main": true]
        let outcome = ConnectionProbe.run(radio: radio, target: "Hidden", permitted: { true })
        XCTAssertEqual(outcome, .connectedRestored)
        XCTAssertEqual(radio.attempts, ["Hidden", "Main"])
        XCTAssertEqual(radio.current, "Main")
    }
    func testWrongNameKeepsOriginalWithoutUnnecessaryReconnect() {
        let radio = FakeRadio()
        radio.current = "Main"
        radio.dropOnFailure = false
        let outcome = ConnectionProbe.run(radio: radio, target: "Typo", permitted: { true })
        XCTAssertEqual(outcome, .failedPreviousAvailable)
        XCTAssertEqual(radio.attempts, ["Typo"])
        XCTAssertEqual(radio.current, "Main")
    }
    func testFailedAttemptRestoresPreviousWhenDisconnected() {
        let radio = FakeRadio()
        radio.current = "Main"
        radio.results["Main"] = true
        let outcome = ConnectionProbe.run(radio: radio, target: "Unavailable", permitted: { true })
        XCTAssertEqual(outcome, .failedPreviousAvailable)
        XCTAssertEqual(radio.attempts, ["Unavailable", "Main"])
        XCTAssertEqual(radio.current, "Main")
    }
    func testSuccessfulAttemptReportsFailedRestoration() {
        let radio = FakeRadio()
        radio.current = "Main"
        radio.results["Hotspot"] = true
        let outcome = ConnectionProbe.run(radio: radio, target: "Hotspot", permitted: { true })
        XCTAssertEqual(outcome, .connectedRestoreFailed)
        XCTAssertEqual(radio.attempts, ["Hotspot", "Main"])
        XCTAssertNil(radio.current)
    }
    func testNoPreviousConnectionLeavesSuccessfulTargetConnected() {
        let radio = FakeRadio()
        radio.results["Hotspot"] = true
        let outcome = ConnectionProbe.run(radio: radio, target: "Hotspot", permitted: { true })
        XCTAssertEqual(outcome, .connected)
        XCTAssertEqual(radio.current, "Hotspot")
    }
    func testManualChangeIsNeverOverridden() {
        let radio = FakeRadio()
        radio.current = "Main"
        radio.results["Hotspot"] = true
        radio.reportedConnectedCurrent["Hotspot"] = "Manual"
        let outcome = ConnectionProbe.run(radio: radio, target: "Hotspot", permitted: { true })
        XCTAssertEqual(outcome, .changed)
        XCTAssertEqual(radio.attempts, ["Hotspot"])
        XCTAssertEqual(radio.current, "Manual")
    }
    func testAlreadyConnectedAndCancelledDoNotJoin() {
        let radio = FakeRadio()
        radio.current = "Main"
        XCTAssertEqual(ConnectionProbe.run(radio: radio, target: "Main", permitted: { true }), .alreadyConnected)
        XCTAssertEqual(ConnectionProbe.run(radio: radio, target: "Hotspot", permitted: { false }), .cancelled)
        XCTAssertTrue(radio.attempts.isEmpty)
    }
}
