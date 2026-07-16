import XCTest
@testable import DECtalkKit

final class SettingsTests: XCTestCase {

    func testCommandPrefixGlobals() {
        var s = DECtalkSettings()
        s.rate = 250; s.volume = 80; s.spf = 90; s.sentencePause = 300; s.commaPause = 120
        let p = s.commandPrefix(for: .paul)
        XCTAssertEqual(p, "[:rate 250][:vo set 80][:spf 90][:pp 300 :cp 120]")
    }

    func testBuiltInPrefixIsGlobalsOnly() {
        // Built-in voices carry no [:dv] — voice design lives in custom voices.
        let s = DECtalkSettings()
        let paul = s.commandPrefix(for: .paul)
        XCTAssertFalse(paul.contains("[:dv"), "built-in should have no [:dv]: \(paul)")
    }

    func testCustomVoicePrefixEmitsAllParams() {
        var s = DECtalkSettings()
        var voice = DECtalkCustomVoice(name: "Deep Paul", base: .paul)
        voice.params["ap"] = 90
        voice.params["hs"] = 130
        s.customVoices[voice.name] = voice

        let (prefix, base) = s.resolve(.custom("Deep Paul"))
        XCTAssertEqual(base, .paul)
        XCTAssertTrue(prefix.contains("[:dv "), prefix)
        XCTAssertTrue(prefix.contains("ap 90"), prefix)
        XCTAssertTrue(prefix.contains("hs 130"), prefix)
        // A custom voice is fully defined: every one of the 28 codes is present.
        for p in DECtalkParameter.voiceParameters {
            XCTAssertTrue(prefix.contains(" \(p.code) ") || prefix.contains("[:dv \(p.code) "), "missing \(p.code): \(prefix)")
        }
    }

    func testCustomVoiceSnapshotsBaseDefaults() {
        // A new custom voice starts from its base voice's built-in values.
        let voice = DECtalkCustomVoice(name: "Betty Clone", base: .betty)
        XCTAssertEqual(voice.params["ap"], 208)
        XCTAssertEqual(voice.params["sx"], 0)
        XCTAssertEqual(voice.params.count, 28)
    }

    func testDtvRoundTrip() throws {
        var voice = DECtalkCustomVoice(name: "Roundtrip", base: .harry)
        voice.params["ap"] = 77
        let data = try voice.dtvData()
        // Same on-disk shape as the NVDA add-on.
        let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(doc["format"] as? String, "dectalk-voice")
        XCTAssertEqual(doc["base"] as? String, "harry")
        let back = try DECtalkCustomVoice.fromDtv(data)
        XCTAssertEqual(back.base, .harry)
        XCTAssertEqual(back.params["ap"], 77)
        XCTAssertEqual(back.name, "Roundtrip")
    }

    func testDtvRejectsNonVoiceFile() {
        let junk = Data("{\"hello\":1}".utf8)
        XCTAssertThrowsError(try DECtalkCustomVoice.fromDtv(junk))
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

    func testCustomVoicePitchChangesF0() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        var low = DECtalkSettings()
        var lowVoice = DECtalkCustomVoice(name: "Low", base: .paul); lowVoice.params["ap"] = 100
        low.customVoices[lowVoice.name] = lowVoice
        var high = DECtalkSettings()
        var highVoice = DECtalkCustomVoice(name: "High", base: .paul); highVoice.params["ap"] = 300
        high.customVoices[highVoice.name] = highVoice

        let lowF0  = f0(synth.render("Testing one two three four.", applying: low,  selection: .custom("Low")),  sampleRate: synth.sampleRate)
        let highF0 = f0(synth.render("Testing one two three four.", applying: high, selection: .custom("High")), sampleRate: synth.sampleRate)

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
