import Foundation
import XCTest
@testable import WiFiPriorityCore

final class PrivateAppStorageTests: XCTestCase {
    func testWriteRepairsExistingDirectoryAndFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifipriority-private-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        let file = directory.appendingPathComponent("settings.json")
        try Data("first".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        try PrivateAppStorage.write(Data("updated".utf8), to: file)

        XCTAssertEqual(try Data(contentsOf: file), Data("updated".utf8))
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        XCTAssertEqual(fileMode?.intValue, 0o600)
    }

    func testLogTextCannotInsertExtraLines() {
        XCTAssertEqual(PrivateAppStorage.singleLine("Wi-Fi\r\nchanged\tname\u{2028}again"),
                       "Wi-Fi  changed name again")
    }

    func testStartupCanTightenOldFilesWithoutChangingContents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifipriority-old-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        let file = directory.appendingPathComponent("events.log")
        try Data("existing log".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        try PrivateAppStorage.protectExistingFiles(in: directory,
                                                   names: ["settings.json", "events.log"])

        XCTAssertEqual(try Data(contentsOf: file), Data("existing log".utf8))
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        XCTAssertEqual(fileMode?.intValue, 0o600)
    }
}
