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
    public enum Speaker: Int, CaseIterable, Sendable, Codable, Hashable {
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

        _ = Self.engineASCII(text).withCString { dtk_speak(engine, $0, callback, ctx) }
        return collector.samples
    }

    /// The DECtalk engine is ASCII/Latin-1 era: raw multi-byte UTF-8 (curly
    /// quotes, em-dashes, accented letters, …) is spoken byte-by-byte as symbol
    /// names ("circumflex"). Map common “smart” punctuation to ASCII, strip
    /// diacritics, and drop anything else non-ASCII before handing text over.
    static func engineASCII(_ text: String) -> String {
        let replacements: [Character: String] = [
            "\u{2018}": "'",  "\u{2019}": "'",  "\u{201A}": "'", "\u{201B}": "'",   // ‘ ’ ‚ ‛
            "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", // “ ” „ ‟
            "\u{00AB}": "\"", "\u{00BB}": "\"",                                      // « »
            "\u{2013}": "-",  "\u{2014}": " - ", "\u{2015}": "-", "\u{2212}": "-",  // – — ― −
            "\u{2022}": "-",  "\u{00B7}": ".",   "\u{2026}": "...",                 // • · …
            "\u{00A0}": " ",  "\u{2007}": " ",   "\u{2009}": " ", "\u{202F}": " ",  // no-break/thin spaces
            "\u{FEFF}": "",                                                          // BOM / zero-width no-break
        ]
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text { out += replacements[ch].map { $0 } ?? String(ch) }
        // Fold accents (café -> cafe), then drop any remaining non-ASCII.
        out = out.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        return String(String.UnicodeScalarView(out.unicodeScalars.map { $0.isASCII ? $0 : " " }))
    }

    /// Renders `text` for a built-in `speaker` with the global settings applied.
    /// Blocks until synthesis completes.
    public func render(_ text: String, applying settings: DECtalkSettings, speaker: Speaker) -> [Int16] {
        render(text, applying: settings, selection: .builtIn(speaker))
    }

    /// As ``render(_:applying:speaker:)`` but returns a float32 mono buffer.
    public func renderBuffer(_ text: String, applying settings: DECtalkSettings, speaker: Speaker) -> AVAudioPCMBuffer? {
        renderBuffer(text, applying: settings, selection: .builtIn(speaker))
    }

    /// Renders `text` for a voice `selection` (built-in or custom): switches the
    /// engine to the base speaker, then prepends the resolved inline command
    /// prefix (globals, and every `[:dv]` parameter for a custom voice).
    public func render(_ text: String, applying settings: DECtalkSettings, selection: DECtalkVoiceSelection) -> [Int16] {
        let (prefix, base) = settings.resolve(selection)
        self.speaker = base
        return render(prefix + " " + text)
    }

    /// As ``render(_:applying:selection:)`` but returns a float32 mono buffer.
    public func renderBuffer(_ text: String, applying settings: DECtalkSettings, selection: DECtalkVoiceSelection) -> AVAudioPCMBuffer? {
        let (prefix, base) = settings.resolve(selection)
        self.speaker = base
        return renderBuffer(prefix + " " + text)
    }

    /// Preview a custom voice's raw parameters directly (used by the Voice
    /// Manager's Test button, so a preview sounds exactly like the saved voice).
    public func renderBuffer(preview voice: DECtalkCustomVoice, text: String, applying settings: DECtalkSettings) -> AVAudioPCMBuffer? {
        self.speaker = voice.base
        return renderBuffer(settings.commandPrefix(for: voice) + " " + text)
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
