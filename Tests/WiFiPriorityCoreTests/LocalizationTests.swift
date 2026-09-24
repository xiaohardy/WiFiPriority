import XCTest
@testable import WiFiPriorityCore

final class LocalizationTests: XCTestCase {
    func testSystemLanguageMatchingAndFallback() {
        XCTAssertEqual(L10n.resolve(.system, preferred: ["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["zh-Hant-TW"]), .traditionalChinese)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["zh-Hans-HK"]), .simplifiedChinese)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["zh-Hans-TW"]), .simplifiedChinese)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["zh-Hant-CN"]), .traditionalChinese)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["es-MX"]), .spanish)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["pt-PT"]), .portuguese)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["xx", "fr-CA"]), .french)
        XCTAssertEqual(L10n.resolve(.system, preferred: ["xx"]), .english)
        XCTAssertEqual(L10n.resolve(.japanese, preferred: ["en"]), .japanese)
    }
    func testEveryCatalogHasAllKeysAndMatchingPlaceholders() {
        let english = L10n.catalog(.english)
        XCTAssertEqual(Set(english.keys), Set(MessageKey.allCases.map(\.rawValue)))
        for language in AppLanguage.allCases where language != .system {
            let catalog = L10n.catalog(language)
            XCTAssertEqual(Set(catalog.keys), Set(english.keys), language.rawValue)
            for key in english.keys {
                XCTAssertFalse((catalog[key] ?? "").isEmpty, "\(language): \(key)")
                XCTAssertEqual(placeholders(catalog[key] ?? ""), placeholders(english[key]!), "\(language): \(key)")
            }
        }
    }
    func testOldSettingsKeepNetworksAndDefaultToSystemLanguage() throws {
        let data = Data(#"{"networks":["Primary","Backup"],"paused":false}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded.networks, ["Primary", "Backup"])
        XCTAssertEqual(decoded.language, .system)
        XCTAssertFalse(decoded.paused)
    }
    func testLanguagePersistsAndUnknownPreferenceHasSafeFallback() throws {
        let settings = try Settings(networks: ["Main"], paused: false, language: .spanish)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)), settings)
        let future = Data(#"{"networks":["Main"],"paused":true,"language":"future"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: future).language, .system)
    }
    func testStatusCanBeTranslatedAgainWithoutAnotherNetworkCheck() {
        let status = StatusMessage(.connected, ["network": "My SSID 中文"])
        XCTAssertEqual(L10n.text(status, language: .english), "Connected: My SSID 中文")
        XCTAssertEqual(L10n.text(status, language: .simplifiedChinese), "已连接：My SSID 中文")
    }
    func testSSIDPlaceholderCharactersArePreservedLiterally() {
        let status = StatusMessage(.cooldown, ["network": "SSID {minutes} %s", "minutes": "5"])
        XCTAssertEqual(L10n.text(status, language: .english), "Connected: SSID {minutes} %s. A failed network can be retried in about 5 min.")
    }
    private func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\{[a-zA-Z]+\}"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }.sorted()
    }
}
