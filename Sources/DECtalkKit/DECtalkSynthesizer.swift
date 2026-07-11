import Foundation
import AVFoundation
import DECtalkEngine

/// A thin, safe Swift wrapper around the DECtalk formant synthesizer.
///
/// Synthesis is synchronous and CPU-bound: call ``render(_:)`` off the main
/// thread. Each instance owns one engine handle; the underlying C layer
/// serializes concurrent synthesis internally, which is why this type is
/// declared `@unchecked Sendable` — callers must still not mutate `rate` /
/// `speaker` concurrently with an in-flight `render(_:)`.
public final class DECtalkSynthesizer: @unchecked Sendable {

    /// The nine predefined DECtalk voices.
    public enum Speaker: Int, CaseIterable, Sendable {
        case paul = 0, betty, harry, frank, dennis, kit, ursula, rita, wendy

        public var displayName: String {
            switch self {
            case .paul:   return "Perfect Paul"
            case .betty:  return "Beautiful Betty"
            case .harry:  return "Huge Harry"
            case .frank:  return "Frail Frank"
            case .dennis: return "Doctor Dennis"
            case .kit:    return "Kit the Kid"
            case .ursula: return "Uppity Ursula"
            case .rita:   return "Rough Rita"
            case .wendy:  return "Whispering Wendy"
            }
        }
    }

    /// Native output sample rate (Hz).
    public let sampleRate: Double

    private let engine: OpaquePointer

    /// Words per minute (roughly 75...600). Default 200.
    public var rate: Int = 200 {
        didSet { dtk_set_rate(engine, Int32(rate)) }
    }

    /// Active voice. Default `.paul`.
    public var speaker: Speaker = .paul {
        didSet { dtk_set_speaker(engine, Int32(speaker.rawValue)) }
    }

    /// Creates a synthesizer. `dictionaryDirectory` must contain `dtalk_us.dic`;
    /// when nil, the dictionary bundled with DECtalkKit is used.
    public init?(dictionaryDirectory: URL? = nil) {
        let dir = dictionaryDirectory ?? DECtalkSynthesizer.bundledDictionaryDirectory
        let created: OpaquePointer? = dir
            .path
            .withCString { dtk_create($0) }
        guard let engine = created else { return nil }
        self.engine = engine
        self.sampleRate = Double(dtk_sample_rate(engine))
        dtk_set_rate(engine, Int32(rate))
        dtk_set_speaker(engine, Int32(speaker.rawValue))
    }

    deinit {
        dtk_destroy(engine)
    }

    /// Directory of the dictionary shipped inside the DECtalkKit resource bundle.
    public static var bundledDictionaryDirectory: URL {
        // Bundle.module resolves to the resource bundle that holds dtalk_us.dic.
        if let url = Bundle.module.url(forResource: "dtalk_us", withExtension: "dic") {
            return url.deletingLastPathComponent()
        }
        return Bundle.module.bundleURL
    }

    // MARK: - Synthesis

    private final class Collector {
        var samples: [Int16] = []
    }

    /// Synthesizes `text` and returns the raw signed 16-bit mono samples.
    /// Blocks until synthesis completes.
    public func render(_ text: String) -> [Int16] {
        let collector = Collector()
        let ctx = Unmanaged.passUnretained(collector).toOpaque()

        let callback: dtk_sample_cb = { samples, count, ctx in
            guard let samples, let ctx, count > 0 else { return }
            let collector = Unmanaged<Collector>.fromOpaque(ctx).takeUnretainedValue()
            collector.samples.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        }

        _ = text.withCString { dtk_speak(engine, $0, callback, ctx) }
        return collector.samples
    }

    /// Renders `text` with the given settings applied. Selects the base voice,
    /// then prepends the inline command prefix (rate, volume, SPF, pauses, and
    /// any per-voice `[:dv]` overrides). Blocks until synthesis completes.
    public func render(_ text: String, applying settings: DECtalkSettings, speaker: Speaker) -> [Int16] {
        self.speaker = speaker
        let prefix = settings.commandPrefix(for: speaker)
        return render(prefix + " " + text)
    }

    /// As ``render(_:applying:speaker:)`` but returns a float32 mono buffer.
    public func renderBuffer(_ text: String, applying settings: DECtalkSettings, speaker: Speaker) -> AVAudioPCMBuffer? {
        self.speaker = speaker
        let prefix = settings.commandPrefix(for: speaker)
        return renderBuffer(prefix + " " + text)
    }

    /// Synthesizes `text` into a float32 mono `AVAudioPCMBuffer` at ``sampleRate``.
    public func renderBuffer(_ text: String) -> AVAudioPCMBuffer? {
        let samples = render(text)
        guard !samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let out = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            out[i] = Float(samples[i]) / 32768.0
        }
        return buffer
    }

    /// Convenience: writes `text` to a 16-bit mono WAV file.
    @discardableResult
    public func renderToWAV(_ text: String, url: URL) -> Bool {
        url.path.withCString { path in
            text.withCString { body in
                dtk_speak_to_wav(engine, path, body) == 0
            }
        }
    }
}
