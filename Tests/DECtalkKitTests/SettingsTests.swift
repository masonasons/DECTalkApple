import XCTest
@testable import DECtalkKit

final class SettingsTests: XCTestCase {

    func testCommandPrefixGlobals() {
        var s = DECtalkSettings()
        s.rate = 250; s.volume = 80; s.spf = 90; s.sentencePause = 300; s.commaPause = 120
        let p = s.commandPrefix(for: .paul)
        XCTAssertEqual(p, "[:rate 250][:vo set 80][:spf 90][:pp 300 :cp 120]")
    }

    func testCommandPrefixPerVoiceOverrides() {
        var s = DECtalkSettings()
        s.setOverride("ap", 180, for: .harry)
        s.setOverride("hs", 130, for: .harry)
        s.setOverride("ap", 250, for: .betty)   // different voice, ignored for harry

        let harry = s.commandPrefix(for: .harry)
        XCTAssertTrue(harry.contains("[:dv ap 180 hs 130]"), harry)
        let paul = s.commandPrefix(for: .paul)
        XCTAssertFalse(paul.contains("[:dv"), "paul has no overrides: \(paul)")
    }

    func testClearOverride() {
        var s = DECtalkSettings()
        s.setOverride("ap", 200, for: .paul)
        XCTAssertEqual(s.override("ap", for: .paul), 200)
        s.clearOverride("ap", for: .paul)
        XCTAssertNil(s.override("ap", for: .paul))
        XCTAssertNil(s.voiceOverrides[DECtalkSynthesizer.Speaker.paul.rawValue])
    }

    func testCatalogHasNoInvalidCodes() {
        // `lo` is the one standard code the engine rejects — make sure it's absent.
        XCTAssertNil(DECtalkParameter.voiceParameter(code: "lo"))
        XCTAssertNotNil(DECtalkParameter.voiceParameter(code: "ap"))
        XCTAssertEqual(DECtalkParameter.voiceParameters.count, 28)
    }

    // MARK: - Audible effect

    private func f0(_ samples: [Int16], sampleRate: Double) -> Double {
        let mid = Array(samples[(samples.count/3)..<min(samples.count/3 + 4000, samples.count)])
        var best = (score: 0.0, lag: 0)
        let lo = Int(sampleRate/400), hi = Int(sampleRate/80)
        for lag in lo...hi {
            var s = 0.0
            var i = 0
            while i + lag < mid.count { s += Double(mid[i]) * Double(mid[i+lag]); i += 4 }
            if s > best.score { best = (s, lag) }
        }
        return best.lag > 0 ? sampleRate / Double(best.lag) : 0
    }

    func testPitchOverrideChangesF0() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        var low = DECtalkSettings();  low.setOverride("ap", 100, for: .paul)
        var high = DECtalkSettings(); high.setOverride("ap", 300, for: .paul)

        let lowF0  = f0(synth.render("Testing one two three four.", applying: low,  speaker: .paul), sampleRate: synth.sampleRate)
        let highF0 = f0(synth.render("Testing one two three four.", applying: high, speaker: .paul), sampleRate: synth.sampleRate)

        XCTAssertLessThan(lowF0, 170, "low-pitch f0 unexpectedly high: \(lowF0)")
        XCTAssertGreaterThan(highF0, 250, "high-pitch f0 unexpectedly low: \(highF0)")
    }

    func testCommaPauseLengthensSpeech() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        var none = DECtalkSettings()
        var big = DECtalkSettings(); big.commaPause = 1500

        let short = synth.render("one, two, three, four, five.", applying: none, speaker: .paul).count
        let long  = synth.render("one, two, three, four, five.", applying: big,  speaker: .paul).count
        XCTAssertGreaterThan(long, short * 2, "comma pause did not lengthen output (short=\(short) long=\(long))")
    }
}
