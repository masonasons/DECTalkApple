import XCTest
@testable import DECtalkKit

final class PitchTests: XCTestCase {

    func testPitchScaleFromSSML() {
        func scale(_ pitch: String) -> Double {
            DECtalkSettings.pitchScale(fromSSML: #"<speak><prosody rate="100%" pitch="\#(pitch)">Hi</prosody></speak>"#)
        }
        XCTAssertEqual(scale("x-low"), 0.6)
        XCTAssertEqual(scale("medium"), 1.0)
        XCTAssertEqual(scale("x-high"), 1.5)
        XCTAssertEqual(scale("120%"), 1.2, accuracy: 0.0001)
        XCTAssertEqual(scale("+20%"), 1.2, accuracy: 0.0001)
        XCTAssertEqual(scale("-15%"), 0.85, accuracy: 0.0001)
        XCTAssertEqual(scale("+12st"), 2.0, accuracy: 0.0001)
        XCTAssertEqual(scale("0.5"), 0.5, accuracy: 0.0001)
        XCTAssertEqual(scale("+10Hz"), 1.0)
        XCTAssertEqual(DECtalkSettings.pitchScale(fromSSML: "<speak>No pitch here</speak>"), 1.0)
    }

    func testPitchScaleIsClamped() {
        XCTAssertEqual(DECtalkSettings.pitchScale(fromSSML: #"pitch="1000%""#), 4.0)
        XCTAssertEqual(DECtalkSettings.pitchScale(fromSSML: #"pitch="1%""#), 0.25)
        XCTAssertEqual(DECtalkSettings.pitchScale(fromSSML: #"pitch="-100%""#), 1.0)
    }

    func testBuiltInPitchOverride() {
        var s = DECtalkSettings()
        s.pitchScale = 1.5
        // Paul's average pitch is 122 Hz; 1.5x is 183.
        XCTAssertEqual(s.commandPrefix(for: .paul), "[:rate 200][:vo set 72][:spf 100][:pp 0 :cp 0][:dv ap 183]")
        // The result is clamped to the engine's 50...350 Hz range (Kit is 306 Hz).
        XCTAssertTrue(s.commandPrefix(for: .kit).hasSuffix("[:dv ap 350]"))
    }

    func testCustomVoicePitchIsScaled() {
        var s = DECtalkSettings()
        var voice = DECtalkCustomVoice(name: "Deep Paul", base: .paul)
        voice.params["ap"] = 90
        s.customVoices[voice.name] = voice
        s.pitchScale = 2.0

        let (prefix, _) = s.resolve(.custom("Deep Paul"))
        XCTAssertTrue(prefix.contains("[:dv ap 180 "), prefix)
        XCTAssertFalse(prefix.contains("ap 90"), prefix)
        // The saved voice itself is untouched.
        XCTAssertEqual(s.customVoices["Deep Paul"]?.params["ap"], 90)
    }

    func testPitchScaleIsNotPersisted() throws {
        var s = DECtalkSettings()
        s.pitchScale = 2.0
        let decoded = try JSONDecoder().decode(DECtalkSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.pitchScale, 1.0)
    }
}
