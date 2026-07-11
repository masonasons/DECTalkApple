import XCTest
import AVFoundation
@testable import DECtalkKit

/// Exercises the exact audio path the app uses: a DECtalk buffer (11025 Hz)
/// played through an AVAudioEngine player→mixer graph and resampled to a
/// hardware-like rate, rendered offline so we can assert it isn't silent.
final class PlaybackGraphTests: XCTestCase {

    func testEngineResamplesAndOutputsNonSilentAudio() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        let source = try XCTUnwrap(synth.renderBuffer("Playback graph test."))

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: source.format)

        // Render offline to a 48 kHz float buffer — proves the resampling path.
        let outFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: 48000,
                                                    channels: 2,
                                                    interleaved: false))
        try engine.enableManualRenderingMode(.offline,
                                             format: outFormat,
                                             maximumFrameCount: 4096)
        try engine.start()
        player.scheduleBuffer(source, at: nil, options: [])
        player.play()

        let capture = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 4096))
        var peak: Float = 0
        // Render roughly the source duration plus a little headroom.
        let totalFrames = AVAudioFramePosition(source.frameLength) * 48000 / AVAudioFramePosition(source.format.sampleRate)
        var rendered: AVAudioFramePosition = 0
        while rendered < totalFrames + 4096 {
            let status = try engine.renderOffline(4096, to: capture)
            guard status == .success, capture.frameLength > 0 else { break }
            let ch = capture.floatChannelData![0]
            for i in 0..<Int(capture.frameLength) { peak = max(peak, abs(ch[i])) }
            rendered += AVAudioFramePosition(capture.frameLength)
        }
        engine.stop()

        XCTAssertGreaterThan(peak, 0.05, "playback graph produced silence")
    }
}
