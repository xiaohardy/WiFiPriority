import XCTest
@testable import WiFiPriorityCore

final class StatusIndicatorStateTests: XCTestCase {
    func testPriorityOrderMapsToFixedStarPositions() {
        let networks = ["Preferred", "Backup 1", "Backup 2"]
        let preferred = StatusIndicatorState(networks: networks, currentSSID: "Preferred", paused: false)
        XCTAssertEqual(preferred.starCount, 3)
        XCTAssertEqual(preferred.activeIndex, 0)
        XCTAssertEqual(StatusIndicatorState(networks: networks, currentSSID: "Backup 1", paused: false).activeIndex, 1)
        XCTAssertEqual(StatusIndicatorState(networks: networks, currentSSID: "Backup 2", paused: false).activeIndex, 2)
        XCTAssertNil(StatusIndicatorState(networks: networks, currentSSID: "Other", paused: false).activeIndex)
        XCTAssertNil(StatusIndicatorState(networks: networks, currentSSID: nil, paused: false).activeIndex)
        XCTAssertNil(StatusIndicatorState(networks: networks, currentSSID: "Preferred", paused: true).activeIndex)
    }

    func testStarCountStopsAtTwelve() {
        let networks = (0..<14).map { "Network \($0)" }
        XCTAssertEqual(StatusIndicatorState(networks: [], currentSSID: nil, paused: false).starCount, 0)
        XCTAssertEqual(StatusIndicatorState(networks: networks, currentSSID: "Network 11", paused: false).activeIndex, 11)
        let beyondRing = StatusIndicatorState(networks: networks, currentSSID: "Network 12", paused: false)
        XCTAssertEqual(beyondRing.starCount, 12)
        XCTAssertNil(beyondRing.activeIndex)
    }
}
