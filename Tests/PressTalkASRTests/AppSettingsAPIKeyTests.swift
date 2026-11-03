import XCTest
@testable import PressTalkASR

@MainActor
final class AppSettingsAPIKeyTests: XCTestCase {
    func testMigratesLegacyPlaintextKeyToSecureStore() {
        let defaults = makeDefaults()
        defaults.set("sk-legacy-abcdefghijklmnopqrstuvwxyz", forKey: "apiKeyLocalCache")
        let store = CountingAPIKeyStore()

        let settings = AppSettings(defaults: defaults, apiKeyStore: store, environment: [:])

        XCTAssertEqual(settings.resolvedAPIKey(), "sk-legacy-abcdefghijklmnopqrstuvwxyz")
        XCTAssertEqual(settings.apiKeySource(), .keychain)
        XCTAssertEqual(store.savedValues, ["sk-legacy-abcdefghijklmnopqrstuvwxyz"])
        XCTAssertNil(defaults.string(forKey: "apiKeyLocalCache"))
    }

    func testReadsSecureStoreOnlyDuringInitialization() {
        let store = CountingAPIKeyStore(value: "sk-secure-abcdefghijklmnopqrstuvwxyz")
        let settings = AppSettings(defaults: makeDefaults(), apiKeyStore: store, environment: [:])

        _ = settings.resolvedAPIKey()
        _ = settings.resolvedAPIKey()

        XCTAssertEqual(store.readCount, 1)
    }

    func testSaveAndClearUseSecureStore() throws {
        let store = CountingAPIKeyStore()
        let settings = AppSettings(defaults: makeDefaults(), apiKeyStore: store, environment: [:])

        try settings.saveAPIKey("  sk-new-abcdefghijklmnopqrstuvwxyz  ")
        XCTAssertEqual(store.value, "sk-new-abcdefghijklmnopqrstuvwxyz")
        XCTAssertEqual(settings.apiKeySource(), .keychain)

        try settings.clearAPIKey()
        XCTAssertNil(store.value)
        XCTAssertEqual(store.deleteCount, 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsAPIKeyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class CountingAPIKeyStore: APIKeyStoring {
    var value: String?
    private(set) var readCount = 0
    private(set) var deleteCount = 0
    private(set) var savedValues: [String] = []

    init(value: String? = nil) {
        self.value = value
    }

    func read() throws -> String? {
        readCount += 1
        return value
    }

    func save(_ value: String) throws {
        self.value = value
        savedValues.append(value)
    }

    func delete() throws {
        value = nil
        deleteCount += 1
    }
}
