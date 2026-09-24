import XCTest
@testable import WiFiPriorityCore

final class PolicyTests: XCTestCase {
    let all = ["Main": -45, "Backup 1": -55, "Backup 2": -60]
    func ready(_ p: inout PriorityPolicy, current: String? = nil, now: Double = 15) {
        p.observe(current: current, visible: all)
        p.observe(current: current, visible: all)
    }
    func testFailedVisiblePrimaryDoesNotStarveBackup() {
        var p = PriorityPolicy(networks: ["Main", "Backup 1", "Backup 2"])
        ready(&p)
        XCTAssertEqual(p.candidate(current: nil, now: 0), "Main")
        p.failed("Main", now: 0)
        XCTAssertEqual(p.candidate(current: nil, now: 0), "Backup 1")
        p.failed("Backup 1", now: 0)
        XCTAssertEqual(p.candidate(current: nil, now: 0), "Backup 2")
    }
    func testRecoveryHasFiniteCooldownAndRetriesWhileOnBackup() {
        var p = PriorityPolicy(networks: ["Main", "Backup 1", "Backup 2"])
        ready(&p, current: "Backup 1")
        p.failed("Main", now: 0)
        XCTAssertNil(p.candidate(current: "Backup 1", now: 299))
        p.observe(current: "Backup 1", visible: all)
        p.observe(current: "Backup 1", visible: all)
        XCTAssertEqual(p.candidate(current: "Backup 1", now: 300), "Main")
        p.failed("Main", now: 300)
        XCTAssertEqual(p.retryAt["Main"], 900)
        p.failed("Main", now: 900)
        XCTAssertEqual(p.retryAt["Main"], 1800)
        p.failed("Main", now: 1800)
        XCTAssertEqual(p.retryAt["Main"], 2700)
    }
    func testSuccessClearsFailureAndDoesNotDowngrade() {
        var p = PriorityPolicy(networks: ["Main", "Backup 1", "Backup 2"])
        ready(&p)
        p.failed("Main", now: 0)
        p.succeeded("Main", now: 300)
        XCTAssertNil(p.retryAt["Main"])
        XCTAssertNil(p.candidate(current: "Main", now: 999))
        p.failed("Main", now: 1000)
        XCTAssertEqual(p.retryAt["Main"], 1300)
    }
    func testStableSightingsAndManualChoice() {
        var p = PriorityPolicy(networks: ["Main", "Backup 1", "Backup 2"])
        p.observe(current: "Backup 2", visible: all)
        XCTAssertNil(p.candidate(current: "Backup 2", now: 0))
        p.observe(current: "Backup 2", visible: ["Backup 1": -50])
        XCTAssertEqual(p.candidate(current: "Backup 2", now: 15), "Backup 1")
        p.observe(current: "Backup 2", visible: all)
        XCTAssertEqual(p.candidate(current: "Backup 2", now: 30), "Backup 1")
        p.observe(current: "Unlisted", visible: all)
        XCTAssertNil(p.candidate(current: "Unlisted", now: 45))
    }
    func testWeakNetworkOnlyAsDisconnectedFallback() {
        var p = PriorityPolicy(networks: ["Main", "Backup 1"])
        p.observe(current: "Backup 1", visible: ["Main": -90])
        p.observe(current: "Backup 1", visible: ["Main": -90])
        XCTAssertNil(p.candidate(current: "Backup 1", now: 0))
        p.observe(current: nil, visible: ["Main": -90])
        p.observe(current: nil, visible: ["Main": -90])
        XCTAssertEqual(p.candidate(current: nil, now: 30), "Main")
    }
    func testResetObservationsRetainsCooldown() {
        var p = PriorityPolicy(networks: ["Main", "Backup 1"])
        ready(&p)
        p.failed("Main", now: 0)
        p.resetObservations()
        ready(&p)
        XCTAssertEqual(p.candidate(current: nil, now: 30), "Backup 1")
    }
    func testConfigurationValidationAndOrdering() throws {
        let c = try Settings(networks: ["Third", "Main", "Second"], paused: true)
        XCTAssertEqual(c.networks, ["Third", "Main", "Second"])
        XCTAssertThrowsError(try Settings(networks: ["A", "A"]))
        XCTAssertThrowsError(try Settings(networks: [""]))
        XCTAssertThrowsError(try Settings(networks: [String(repeating: "中", count: 11)]))
        let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(roundTrip, c)
    }
    func testHiddenNetworkSettingsMigrateAndStayWithinTheList() throws {
        let old = Data(#"{"networks":["Hidden","Hotspot"],"paused":false,"language":"system"}"#.utf8)
        let migrated = try JSONDecoder().decode(Settings.self, from: old)
        XCTAssertTrue(migrated.hiddenNetworks.isEmpty)
        let configured = try Settings(networks: ["Hidden", "Hotspot"], hiddenNetworks: ["Hidden"], paused: false)
        XCTAssertEqual(configured.hiddenNetworks, ["Hidden"])
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(configured)), configured)
        XCTAssertThrowsError(try Settings(networks: ["Hotspot"], hiddenNetworks: ["Hidden"]))
    }
    func testPauseShortcutMigratesAndPersists() throws {
        let old = Data(#"{"networks":["Main"],"paused":false,"language":"en"}"#.utf8)
        let migrated = try JSONDecoder().decode(Settings.self, from: old)
        XCTAssertEqual(migrated.pauseShortcut, .off)
        let previouslySelected = Data(#"{"networks":["Main"],"paused":false,"language":"en","pauseShortcut":"controlOptionCommandW"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: previouslySelected).pauseShortcut.displayName, "⌃⌥⌘W")
        let shortcut = PauseShortcut(keyCode: 11, modifiers: [.control, .option, .command], key: "b")!
        let changed = try Settings(networks: migrated.networks, paused: migrated.paused,
                                   language: migrated.language, pauseShortcut: shortcut)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(changed)).pauseShortcut,
                       shortcut)
        XCTAssertEqual(shortcut.displayName, "⌃⌥⌘B")
        XCTAssertNil(PauseShortcut(keyCode: 11, modifiers: [.command], key: "B"))
        XCTAssertNil(PauseShortcut(keyCode: 11, modifiers: [.option, .shift], key: "B"))
        XCTAssertNil(PauseShortcut(keyCode: 11, modifiers: [.control, .command], key: "↩"))
    }
    func testCredentialPreparationStateMigratesAndStaysWithinConfiguredList() throws {
        let old = Data(#"{"networks":["Main"],"paused":false,"language":"en"}"#.utf8)
        let migrated = try JSONDecoder().decode(Settings.self, from: old)
        XCTAssertNil(migrated.credentialIdentity)
        XCTAssertTrue(migrated.credentialReadyNetworks.isEmpty)
        let prepared = try Settings(networks: ["Main", "Backup"], credentialReadyNetworks: ["Main"],
                                    credentialIdentity: "designated:sample")
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(prepared)), prepared)
        XCTAssertThrowsError(try Settings(networks: ["Main"], credentialReadyNetworks: ["Other"]))
    }
}

final class FakeRadio: Radio {
    var current: String?
    var powered = true
    var visible = ["Main": -45, "Backup 1": -55, "Backup 2": -60]
    var attempts = [String]()
    var results = [String: Bool]()
    var reportedConnectedCurrent = [String: String]()
    var credentialsNeeded = Set<String>()
    var dropOnFailure = true
    var afterScan: (() -> Void)?
    var afterConnect: (() -> Void)?
    func scan() throws -> [String: Int] { afterScan?(); return visible }
    func connect(to ssid: String, permitted: () -> Bool) -> JoinResult {
        guard permitted() else { return .cancelled }
        attempts.append(ssid)
        afterConnect?()
        guard permitted() else { return .cancelled }
        if credentialsNeeded.contains(ssid) { return .requiresCredentialSetup }
        if results[ssid] == true { current = reportedConnectedCurrent[ssid] ?? ssid; return .connected }
        if dropOnFailure { current = nil }
        return .failed
    }
}

final class EngineTests: XCTestCase {
    func engine() -> SwitchEngine { SwitchEngine(networks: ["Main", "Backup 1", "Backup 2"]) }
    func tick(_ e: SwitchEngine, _ r: FakeRadio, _ now: Double) {
        _ = e.tick(radio: r, now: { now }, permitted: { true })
    }
    func testUnpreparedUpgradeRequestsAuthorizationWithoutCooldownOrDisconnect() {
        let e = engine(), r = FakeRadio()
        r.current = "Backup 1"; r.credentialsNeeded.insert("Main")
        tick(e, r, 0)
        let notice = e.tick(radio: r, now: { 15 }, permitted: { true })
        XCTAssertEqual(notice, .init(.credentialSetupRequired, ["network": "Main"]))
        XCTAssertEqual(r.current, "Backup 1")
        XCTAssertNil(e.policy.retryAt["Main"])
        XCTAssertEqual(r.attempts, ["Main"])
        let repeated = e.tick(radio: r, now: { 30 }, permitted: { true })
        XCTAssertEqual(repeated, notice)
        XCTAssertEqual(r.current, "Backup 1")
    }
    func testProtectedPrimaryDoesNotBlockPasswordFreeFallbackWhenDisconnected() {
        let e = engine(), r = FakeRadio()
        r.credentialsNeeded.insert("Main")
        r.results["Backup 1"] = true
        tick(e, r, 0)
        let result = e.tick(radio: r, now: { 15 }, permitted: { true })
        XCTAssertEqual(result, .init(.connected, ["network": "Backup 1"]))
        XCTAssertEqual(r.attempts, ["Main", "Backup 1"])
        XCTAssertEqual(r.current, "Backup 1")
        XCTAssertNil(e.policy.retryAt["Main"])
    }
    func testProtectedPrimaryStillPromptsWhenNoPasswordFreeFallbackWorks() {
        let e = SwitchEngine(networks: ["Main"]), r = FakeRadio()
        r.credentialsNeeded.insert("Main")
        tick(e, r, 0)
        let result = e.tick(radio: r, now: { 15 }, permitted: { true })
        XCTAssertEqual(result, .init(.credentialSetupRequired, ["network": "Main"]))
        XCTAssertEqual(r.attempts, ["Main"])
        XCTAssertNil(e.policy.retryAt["Main"])
    }
    func testSeveralProtectedNetworksDoNotStarveLaterPasswordFreeNetwork() {
        let e = SwitchEngine(networks: ["Main", "Backup 1", "Backup 2", "Open"])
        let r = FakeRadio()
        r.visible["Open"] = -55
        r.credentialsNeeded = ["Main", "Backup 1", "Backup 2"]
        r.results["Open"] = true
        tick(e, r, 0)
        let result = e.tick(radio: r, now: { 15 }, permitted: { true })
        XCTAssertEqual(result, .init(.connected, ["network": "Open"]))
        XCTAssertEqual(r.attempts, ["Main", "Backup 1", "Backup 2", "Open"])
    }
    func testFailedMainFallsThroughInSameCycle() {
        let e = engine(), r = FakeRadio()
        r.results["Backup 1"] = true
        tick(e, r, 0); tick(e, r, 15)
        XCTAssertEqual(r.attempts, ["Main", "Backup 1"])
        XCTAssertEqual(r.current, "Backup 1")
        tick(e, r, 30)
        XCTAssertEqual(r.attempts.count, 2)
        tick(e, r, 315)
        XCTAssertEqual(r.attempts, ["Main", "Backup 1", "Main", "Backup 1"])
        r.results["Main"] = true
        tick(e, r, 915); tick(e, r, 930)
        XCTAssertEqual(r.current, "Main")
    }
    func testFailedUpgradeRestoresOriginalBeforeOtherNetworks() {
        let e = engine(), r = FakeRadio()
        r.current = "Backup 2"; r.results["Backup 2"] = true
        tick(e, r, 0); tick(e, r, 15)
        XCTAssertEqual(r.attempts, ["Main", "Backup 2"])
        XCTAssertEqual(r.current, "Backup 2")
    }
    func testFailedUpgradeDoesNotReconnectIntactBackup() {
        let e = engine(), r = FakeRadio()
        r.current = "Backup 1"; r.dropOnFailure = false
        tick(e, r, 0); tick(e, r, 15)
        XCTAssertEqual(r.attempts, ["Main"])
        XCTAssertEqual(r.current, "Backup 1")
    }
    func testAllFailedIsBoundedAndCooldownSurvivesNextScan() {
        let e = engine(), r = FakeRadio()
        tick(e, r, 0); tick(e, r, 15)
        XCTAssertEqual(r.attempts, ["Main", "Backup 1", "Backup 2"])
        tick(e, r, 30); tick(e, r, 45)
        XCTAssertEqual(r.attempts.count, 3)
    }
    func testManualChangeDuringScanWins() {
        let e = engine(), r = FakeRadio()
        tick(e, r, 0)
        r.afterScan = { r.current = "Unlisted" }
        tick(e, r, 15)
        XCTAssertTrue(r.attempts.isEmpty)
    }
    func testPauseStopsFallbackAndWifiOffDoesNotConnect() {
        let e = engine(), r = FakeRadio()
        tick(e, r, 0)
        var allowed = true
        r.afterConnect = { allowed = false }
        _ = e.tick(radio: r, now: { 15 }, permitted: { allowed })
        XCTAssertEqual(r.attempts, ["Main"])
        r.powered = false
        tick(e, r, 30)
        XCTAssertEqual(r.attempts.count, 1)
    }
    func testFourthNetworkAfterBoundedFirstCycle() {
        let e = SwitchEngine(networks: ["Main", "Backup 1", "Backup 2", "Fourth"])
        let r = FakeRadio()
        r.visible["Fourth"] = -60; r.results["Fourth"] = true
        tick(e, r, 0); tick(e, r, 15)
        XCTAssertEqual(r.attempts.count, 3)
        tick(e, r, 30)
        XCTAssertEqual(r.attempts, ["Main", "Backup 1", "Backup 2", "Fourth"])
        XCTAssertEqual(r.current, "Fourth")
    }
    func testFailedRestorationFallsThroughToAnotherBackup() {
        let e = engine(), r = FakeRadio()
        r.current = "Backup 1"; r.results["Backup 2"] = true
        tick(e, r, 0); tick(e, r, 15)
        XCTAssertEqual(r.attempts, ["Main", "Backup 1", "Backup 2"])
        XCTAssertEqual(r.current, "Backup 2")
    }
    func testRestorationMustConfirmActualNetwork() {
        let e = engine(), r = FakeRadio()
        r.current = "Backup 1"; r.results["Backup 1"] = true
        r.reportedConnectedCurrent["Backup 1"] = "Manual"
        tick(e, r, 0)
        let message = e.tick(radio: r, now: { 15 }, permitted: { true })
        XCTAssertNotEqual(message.key, .restored)
        XCTAssertEqual(r.current, "Manual")
    }
    func testPauseAndWakeResetKeepsFailureCooldown() {
        let e = engine(), r = FakeRadio()
        r.results["Backup 1"] = true
        tick(e, r, 0); tick(e, r, 15)
        e.resetObservations()
        tick(e, r, 30); tick(e, r, 45)
        XCTAssertEqual(r.attempts, ["Main", "Backup 1"])
        XCTAssertEqual(e.policy.retryAt["Main"], 315)
    }
    func testFailedUpgradeDoesNotInventSecondSightingForFallback() {
        let e = engine(), r = FakeRadio()
        r.current = "Backup 1"
        r.visible = ["Main": -45, "Backup 1": -55]
        tick(e, r, 0)
        r.visible["Backup 2"] = -50
        tick(e, r, 15)
        XCTAssertEqual(r.attempts, ["Main", "Backup 1"])
        r.results["Backup 2"] = true
        tick(e, r, 30); tick(e, r, 45)
        XCTAssertEqual(r.current, "Backup 2")
    }
}
