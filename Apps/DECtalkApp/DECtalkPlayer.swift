import Foundation
import Combine
import AVFoundation
import DECtalkKit

/// Drives the DECtalk synthesizer (with the shared settings) and plays its
/// audio through AVAudioEngine.
@MainActor
final class DECtalkPlayer: ObservableObject {

    /// Shared, persisted settings — also read by the system-voice extension.
    let store = DECtalkSettingsStore()

    @Published var text: String = "Hello. I am DECtalk, running natively on Apple platforms."
    /// The voice to speak with: a built-in, or one of the user's custom voices.
    @Published var selection: DECtalkVoiceSelection = .builtIn(.paul)
    @Published private(set) var isSpeaking = false
    @Published private(set) var status: String = ""

    let builtInSpeakers = DECtalkSynthesizer.Speaker.allCases

    private let synth: DECtalkSynthesizer?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let workQueue = DispatchQueue(label: "dectalk.render", qos: .userInitiated)
    private var storeObserver: AnyCancellable?

    init() {
        synth = DECtalkSynthesizer()
        if synth == nil { status = "Failed to load DECtalk engine." }
        engine.attach(player)
        // Re-render views observing the player (e.g. the voice picker) whenever
        // the shared settings/custom-voice list changes.
        storeObserver = store.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// If the selected custom voice was deleted, fall back to Perfect Paul.
    func validateSelection() {
        if case .custom(let name) = selection, store.settings.customVoices[name] == nil {
            selection = .builtIn(.paul)
        }
    }

    func speak() {
        guard let synth else { return }
        let phrase = text
        let settings = store.settings
        let voice = selection

        isSpeaking = true
        status = "Synthesizing…"

        workQueue.async { [weak self] in
            let buffer = synth.renderBuffer(phrase, applying: settings, selection: voice)
            Task { @MainActor in self?.play(buffer) }
        }
    }

    /// Speak a short sample in a specific custom voice (the Voice Manager's Test).
    func preview(_ voice: DECtalkCustomVoice) {
        guard let synth else { return }
        let settings = store.settings
        let sample = "DECtalk voice preview. The quick brown fox jumps over the lazy dog."
        isSpeaking = true
        status = "Testing \(voice.name)…"
        workQueue.async { [weak self] in
            let buffer = synth.renderBuffer(preview: voice, text: sample, applying: settings)
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
