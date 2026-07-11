import Foundation
import AVFoundation
import DECtalkKit

/// Drives the DECtalk synthesizer (with the shared settings) and plays its
/// audio through AVAudioEngine.
@MainActor
final class DECtalkPlayer: ObservableObject {

    /// Shared, persisted settings — also read by the system-voice extension.
    let store = DECtalkSettingsStore()

    @Published var text: String = "Hello. I am DECtalk, running natively on Apple platforms."
    @Published var speaker: DECtalkSynthesizer.Speaker = .paul
    @Published private(set) var isSpeaking = false
    @Published private(set) var status: String = ""

    let speakers = DECtalkSynthesizer.Speaker.allCases

    private let synth: DECtalkSynthesizer?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let workQueue = DispatchQueue(label: "dectalk.render", qos: .userInitiated)

    init() {
        synth = DECtalkSynthesizer()
        if synth == nil { status = "Failed to load DECtalk engine." }
        engine.attach(player)
    }

    func speak() {
        guard let synth else { return }
        let phrase = text
        let settings = store.settings
        let voice = speaker

        isSpeaking = true
        status = "Synthesizing…"

        workQueue.async { [weak self] in
            let buffer = synth.renderBuffer(phrase, applying: settings, speaker: voice)
            Task { @MainActor in self?.play(buffer) }
        }
    }

    func stop() {
        player.stop()
        isSpeaking = false
        status = ""
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else {
            status = "Synthesis produced no audio."
            isSpeaking = false
            return
        }
        do {
            try configureSessionIfNeeded()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            if !engine.isRunning { try engine.start() }
            status = String(format: "Playing %.1fs", Double(buffer.frameLength) / buffer.format.sampleRate)
            player.stop()
            player.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor in self?.isSpeaking = false; self?.status = "" }
            }
            player.play()
        } catch {
            status = "Audio error: \(error.localizedDescription)"
            isSpeaking = false
        }
    }

    private func configureSessionIfNeeded() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        #endif
    }
}
