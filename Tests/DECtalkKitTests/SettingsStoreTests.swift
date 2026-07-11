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
        store.settings.setOverride("ap", 175, for: .harry)

        // A fresh load from the same directory must see the saved values —
        // this is exactly how the extension reads what the app wrote.
        let reloaded = DECtalkSettingsStore.load(containerURL: dir)
        XCTAssertEqual(reloaded.spf, 55)
        XCTAssertEqual(reloaded.sentencePause, 400)
        XCTAssertEqual(reloaded.override("ap", for: .harry), 175)
    }

    func testResetPersists() {
        let store = DECtalkSettingsStore(containerURL: dir)
        store.settings.volume = 40
        store.resetToDefaults()
        XCTAssertEqual(DECtalkSettingsStore.load(containerURL: dir).volume, DECtalkSettings().volume)
    }
}
