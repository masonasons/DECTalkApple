import XCTest
import AVFoundation
@testable import DECtalkKit

final class DECtalkKitTests: XCTestCase {

    func testEngineInitializes() throws {
        let synth = DECtalkSynthesizer()
        XCTAssertNotNil(synth, "DECtalk engine failed to start (dictionary not found?)")
        XCTAssertEqual(synth?.sampleRate, 11025)
    }

    func testRendersNonSilentSpeech() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        let samples = synth.render("Hello world. This is DECtalk.")

        XCTAssertGreaterThan(samples.count, 4000, "far too few samples for a sentence")
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 2000, "output is silent — synthesis produced no audio")
    }

    func testRenderBufferHasFloatAudio() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        let buffer = try XCTUnwrap(synth.renderBuffer("Testing one two three."))
        XCTAssertGreaterThan(buffer.frameLength, 0)
        let peak = (0..<Int(buffer.frameLength))
            .map { abs(buffer.floatChannelData![0][$0]) }
            .max() ?? 0
        XCTAssertGreaterThan(peak, 0.05, "float buffer is effectively silent")
    }

    func testSpeakerAndRateAreAccepted() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        synth.speaker = .betty
        synth.rate = 300
        let samples = synth.render("Beautiful Betty speaking quickly.")
        XCTAssertGreaterThan(samples.count, 1000)
    }
}
