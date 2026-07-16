import XCTest
@testable import DECtalkKit

/// Exercises the file-based persistence round-trip the app and extension rely
/// on, using a temporary directory (the real code uses the App Group container).
final class SettingsStoreTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dectalk-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testStorePersistsAndReloads() {
        let store = DECtalkSettingsStore(containerURL: dir)
        store.settings.spf = 55
        store.settings.sentencePause = 400
        var voice = DECtalkCustomVoice(name: "My Harry", base: .harry)
        voice.params["ap"] = 175
        store.saveVoice(voice)

        // A fresh load from the same directory must see the saved values —
        // this is exactly how the extension reads what the app wrote.
        let reloaded = DECtalkSettingsStore.load(containerURL: dir)
        XCTAssertEqual(reloaded.spf, 55)
        XCTAssertEqual(reloaded.sentencePause, 400)
        XCTAssertEqual(reloaded.customVoices["My Harry"]?.base, .harry)
        XCTAssertEqual(reloaded.customVoices["My Harry"]?.params["ap"], 175)
    }

    func testDtvExportImportRoundTripThroughStore() throws {
        let store = DECtalkSettingsStore(containerURL: dir)
        var voice = DECtalkCustomVoice(name: "Exported", base: .betty)
        voice.params["ap"] = 190
        store.saveVoice(voice)

        let url = dir.appendingPathComponent("Exported.dtv")
        try store.exportVoice("Exported", to: url)

        // Importing into a store that already has it dedupes the name.
        let name = try store.importVoice(from: url)
        XCTAssertEqual(name, "Exported (2)")
        XCTAssertEqual(store.settings.customVoices[name]?.params["ap"], 190)
        XCTAssertEqual(store.settings.customVoices[name]?.base, .betty)
    }

    func testResetPersists() {
        let store = DECtalkSettingsStore(containerURL: dir)
        store.settings.volume = 40
        store.resetToDefaults()
        XCTAssertEqual(DECtalkSettingsStore.load(containerURL: dir).volume, DECtalkSettings().volume)
    }
}
