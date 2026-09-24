import XCTest
@testable import WiFiPriorityCore

private final class AuditRadio: Radio {
    var current: String?
    var powered = true
    var attempts: [String] = []
    var scanFails = false
    var cancel = false
    var manualAfterAttempt: String?
    func scan() throws -> [String:Int] {
        if scanFails { throw NSError(domain: "audit", code: 1) }
        return ["Main": -40, "Backup": -50]
    }
    func connect(to ssid:String, permitted:()->Bool)->JoinResult {
        attempts.append(ssid)
        if cancel { return .cancelled }
        if let manualAfterAttempt { current = manualAfterAttempt; return .failed }
        if ssid == "Backup" { current = ssid; return .connected }
        current = nil; return .failed
    }
}
final class AuditTests: XCTestCase {
    private func run(_ e:SwitchEngine,_ r:AuditRadio,_ time:Double) { _ = e.tick(radio:r, now:{time}, permitted:{true}) }
    func testScanFailureRequiresNewStableEvidence() {
        let e=SwitchEngine(networks:["Main","Backup"]), r=AuditRadio()
        run(e,r,0); r.scanFails=true;run(e,r,15);r.scanFails=false;run(e,r,30)
        XCTAssertEqual(r.attempts,[])
        run(e,r,45);XCTAssertEqual(r.attempts,["Main","Backup"])
    }
    func testCancelledJoinNeverStartsFallback() {
        let e=SwitchEngine(networks:["Main","Backup"]),r=AuditRadio();r.cancel=true
        run(e,r,0);run(e,r,15)
        XCTAssertEqual(r.attempts,["Main"])
    }
    func testManualAssociationAfterFailedCommandWins() {
        let e=SwitchEngine(networks:["Main","Backup"]),r=AuditRadio();r.manualAfterAttempt="User choice"
        run(e,r,0);run(e,r,15);run(e,r,330)
        XCTAssertEqual(r.current,"User choice");XCTAssertEqual(r.attempts,["Main"])
    }
    func testRetriesKeepBackupForFourHoursWithoutStarvation() {
        let e=SwitchEngine(networks:["Main","Backup"]),r=AuditRadio()
        for time in stride(from:0.0,through:14400.0,by:15.0) {run(e,r,time)}
        XCTAssertEqual(r.current,"Backup")
        let mains=r.attempts.filter{$0=="Main"}.count
        XCTAssertGreaterThan(mains,10)
        XCTAssertLessThan(mains,20)
        XCTAssertEqual(mains,r.attempts.filter{$0=="Backup"}.count)
        XCTAssertGreaterThan(e.policy.retryAt["Main"] ?? 0,14400)
    }
}
