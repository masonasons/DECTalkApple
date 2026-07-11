import Foundation

/// Metadata for one adjustable DECtalk parameter, used to drive UI (sliders)
/// and to build the inline command string the engine understands.
///
/// Ranges are generous; DECtalk clamps out-of-range values to the nearest legal
/// value, so these bounds only need to be reasonable, not exact.
public struct DECtalkParameter: Identifiable, Sendable, Hashable {
    public enum Category: String, CaseIterable, Sendable {
        case pitch    = "Pitch & Intonation"
        case quality  = "Voice Quality"
        case formants = "Formants"
        case gains    = "Source Gains"
    }

    public let code: String              // DECtalk [:dv] code, e.g. "ap"
    public let name: String
    public let unit: String
    public let range: ClosedRange<Int>
    public let neutral: Int              // slider start when an override is enabled
    public let category: Category

    public var id: String { code }
}

public extension DECtalkParameter {
    /// Every per-voice `[:dv]` parameter, all verified to be accepted by the
    /// engine (unlike `lo`, which the engine speaks rather than consumes).
    static let voiceParameters: [DECtalkParameter] = [
        // Pitch & intonation
        .init(code: "ap", name: "Average Pitch",   unit: "Hz", range: 50...400,  neutral: 122, category: .pitch),
        .init(code: "pr", name: "Pitch Range",     unit: "%",  range: 0...250,   neutral: 100, category: .pitch),
        .init(code: "as", name: "Assertiveness",   unit: "%",  range: 0...100,   neutral: 65,  category: .pitch),
        .init(code: "bf", name: "Baseline Fall",   unit: "Hz", range: 0...40,    neutral: 18,  category: .pitch),
        .init(code: "hr", name: "Hat Rise",        unit: "Hz", range: 0...100,   neutral: 18,  category: .pitch),
        .init(code: "sr", name: "Stress Rise",     unit: "Hz", range: 0...100,   neutral: 32,  category: .pitch),
        // Voice quality
        .init(code: "hs", name: "Head Size",       unit: "%",  range: 50...200,  neutral: 100, category: .quality),
        .init(code: "sm", name: "Smoothness",      unit: "%",  range: 0...100,   neutral: 3,   category: .quality),
        .init(code: "ri", name: "Richness",        unit: "%",  range: 0...100,   neutral: 70,  category: .quality),
        .init(code: "br", name: "Breathiness",     unit: "dB", range: 0...72,    neutral: 0,   category: .quality),
        .init(code: "la", name: "Laryngealization",unit: "%",  range: 0...100,   neutral: 0,   category: .quality),
        .init(code: "lx", name: "Lax Breathiness", unit: "%",  range: 0...100,   neutral: 0,   category: .quality),
        .init(code: "qu", name: "Quickness",       unit: "%",  range: 0...100,   neutral: 40,  category: .quality),
        .init(code: "nf", name: "Fixed OG Samples",unit: "",   range: 0...100,   neutral: 0,   category: .quality),
        .init(code: "ft", name: "Spectral Tilt",   unit: "%",  range: 0...100,   neutral: 0,   category: .quality),
        .init(code: "sx", name: "Sex (0=F, 1=M)",  unit: "",   range: 0...1,     neutral: 1,   category: .quality),
        // Formants
        .init(code: "f4", name: "Formant 4 Freq",  unit: "Hz", range: 2000...5000, neutral: 3300, category: .formants),
        .init(code: "b4", name: "Formant 4 BW",    unit: "Hz", range: 100...2000,  neutral: 260,  category: .formants),
        .init(code: "f5", name: "Formant 5 Freq",  unit: "Hz", range: 2500...5000, neutral: 3850, category: .formants),
        .init(code: "b5", name: "Formant 5 BW",    unit: "Hz", range: 100...2000,  neutral: 320,  category: .formants),
        // Source gains
        .init(code: "gv", name: "Gain: Voicing",     unit: "dB", range: 0...86, neutral: 65, category: .gains),
        .init(code: "gh", name: "Gain: Aspiration",  unit: "dB", range: 0...86, neutral: 70, category: .gains),
        .init(code: "gf", name: "Gain: Frication",   unit: "dB", range: 0...86, neutral: 70, category: .gains),
        .init(code: "gn", name: "Gain: Nasalization", unit: "dB", range: 0...86, neutral: 74, category: .gains),
        .init(code: "g1", name: "Gain: Cascade F1",  unit: "dB", range: 0...86, neutral: 68, category: .gains),
        .init(code: "g2", name: "Gain: Cascade F2",  unit: "dB", range: 0...86, neutral: 60, category: .gains),
        .init(code: "g3", name: "Gain: Cascade F3",  unit: "dB", range: 0...86, neutral: 48, category: .gains),
        .init(code: "g4", name: "Gain: Cascade F4",  unit: "dB", range: 0...86, neutral: 64, category: .gains),
    ]

    static func voiceParameters(in category: Category) -> [DECtalkParameter] {
        voiceParameters.filter { $0.category == category }
    }

    static func voiceParameter(code: String) -> DECtalkParameter? {
        voiceParameters.first { $0.code == code }
    }
}

/// Metadata for the global (voice-independent) parameters.
public struct DECtalkGlobalParameter: Identifiable, Sendable {
    public let key: String
    public let name: String
    public let unit: String
    public let range: ClosedRange<Int>
    public var id: String { key }

    public static let rate          = DECtalkGlobalParameter(key: "rate",          name: "Rate",          unit: "wpm", range: 75...600)
    public static let volume        = DECtalkGlobalParameter(key: "volume",        name: "Volume",        unit: "",    range: 0...99)
    public static let spf           = DECtalkGlobalParameter(key: "spf",           name: "SPF",           unit: "",    range: 0...100)
    public static let sentencePause = DECtalkGlobalParameter(key: "sentencePause", name: "Sentence Pause", unit: "ms", range: -380...2000)
    public static let commaPause    = DECtalkGlobalParameter(key: "commaPause",    name: "Comma Pause",   unit: "ms",  range: -40...2000)

    public static let all: [DECtalkGlobalParameter] = [rate, volume, spf, sentencePause, commaPause]
}
