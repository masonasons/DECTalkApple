import Foundation

// Custom DECtalk voices — the same model the DECtalk NVDA add-on uses.
//
// A custom voice is a complete voice definition: a base voice (one of the nine
// built-ins, which gives the engine its starting point via the C speaker
// selection) plus a value for every one of the 28 `[:dv]` parameters. Custom
// voices never modify the built-ins; you create one by snapshotting a base
// voice's parameters and tweaking them in the Voice Manager. They are exchanged
// as `.dtv` files whose JSON format is identical to the add-on's, so a voice
// designed in either place loads in the other.

public extension DECtalkSynthesizer.Speaker {
    /// The engine's speaker letter (`[:nX]`), matching the add-on's `VOICES`.
    var letter: String {
        switch self {
        case .paul: return "p"
        case .betty: return "b"
        case .harry: return "h"
        case .frank: return "f"
        case .dennis: return "d"
        case .kit: return "k"
        case .ursula: return "u"
        case .rita: return "r"
        case .wendy: return "w"
        }
    }

    /// Stable lowercase id used in `.dtv` files and voice identifiers.
    var id: String {
        switch self {
        case .paul: return "paul"
        case .betty: return "betty"
        case .harry: return "harry"
        case .frank: return "frank"
        case .dennis: return "dennis"
        case .kit: return "kit"
        case .ursula: return "ursula"
        case .rita: return "rita"
        case .wendy: return "wendy"
        }
    }

    init?(id: String) {
        guard let match = Self.allCases.first(where: { $0.id == id }) else { return nil }
        self = match
    }

    /// This voice's built-in value for every `[:dv]` parameter, read back from
    /// the engine (identical to the add-on's `VOICE_DEFAULTS`). New custom voices
    /// start from these.
    var builtInParams: [String: Int] { DECtalkSynthesizer.Speaker.defaults[self] ?? [:] }

    /// Built-in `[:dv]` values for all nine voices.
    static let defaults: [DECtalkSynthesizer.Speaker: [String: Int]] = [
        .paul: ["sx": 1, "sm": 3, "as": 100, "ap": 122, "pr": 100, "br": 0, "ri": 70,
                "nf": 0, "la": 0, "hs": 100, "f4": 3300, "b4": 260, "f5": 3650, "b5": 330,
                "gf": 70, "gh": 70, "gv": 65, "gn": 74, "g1": 68, "g2": 60, "g3": 48, "g4": 64,
                "ft": 75, "bf": 18, "lx": 0, "qu": 40, "hr": 18, "sr": 32],
        .betty: ["sx": 0, "sm": 4, "as": 35, "ap": 208, "pr": 240, "br": 0, "ri": 40,
                 "nf": 0, "la": 0, "hs": 100, "f4": 4450, "b4": 260, "f5": 6000, "b5": 6000,
                 "gf": 72, "gh": 70, "gv": 65, "gn": 72, "g1": 69, "g2": 65, "g3": 50, "g4": 56,
                 "ft": 75, "bf": 0, "lx": 80, "qu": 55, "hr": 14, "sr": 20],
        .harry: ["sx": 1, "sm": 12, "as": 100, "ap": 89, "pr": 80, "br": 0, "ri": 86,
                 "nf": 10, "la": 0, "hs": 115, "f4": 3300, "b4": 200, "f5": 3850, "b5": 240,
                 "gf": 70, "gh": 70, "gv": 65, "gn": 73, "g1": 71, "g2": 60, "g3": 52, "g4": 62,
                 "ft": 60, "bf": 9, "lx": 0, "qu": 10, "hr": 20, "sr": 30],
        .frank: ["sx": 1, "sm": 46, "as": 65, "ap": 155, "pr": 90, "br": 50, "ri": 40,
                 "nf": 0, "la": 5, "hs": 90, "f4": 3650, "b4": 280, "f5": 4200, "b5": 300,
                 "gf": 68, "gh": 68, "gv": 63, "gn": 75, "g1": 63, "g2": 58, "g3": 56, "g4": 66,
                 "ft": 100, "bf": 9, "lx": 50, "qu": 0, "hr": 20, "sr": 22],
        .dennis: ["sx": 1, "sm": 100, "as": 100, "ap": 110, "pr": 135, "br": 38, "ri": 0,
                  "nf": 10, "la": 0, "hs": 105, "f4": 3200, "b4": 240, "f5": 3600, "b5": 280,
                  "gf": 68, "gh": 68, "gv": 63, "gn": 76, "g1": 75, "g2": 60, "g3": 52, "g4": 61,
                  "ft": 100, "bf": 9, "lx": 70, "qu": 50, "hr": 20, "sr": 22],
        .kit: ["sx": 0, "sm": 5, "as": 65, "ap": 306, "pr": 210, "br": 47, "ri": 40,
               "nf": 0, "la": 0, "hs": 80, "f4": 6000, "b4": 6000, "f5": 6000, "b5": 6000,
               "gf": 72, "gh": 70, "gv": 65, "gn": 71, "g1": 69, "g2": 69, "g3": 52, "g4": 50,
               "ft": 75, "bf": 0, "lx": 75, "qu": 50, "hr": 20, "sr": 22],
        .ursula: ["sx": 0, "sm": 60, "as": 100, "ap": 240, "pr": 135, "br": 0, "ri": 100,
                  "nf": 10, "la": 0, "hs": 95, "f4": 4450, "b4": 260, "f5": 6000, "b5": 6000,
                  "gf": 70, "gh": 70, "gv": 65, "gn": 74, "g1": 67, "g2": 65, "g3": 51, "g4": 58,
                  "ft": 100, "bf": 8, "lx": 50, "qu": 30, "hr": 20, "sr": 32],
        .rita: ["sx": 0, "sm": 24, "as": 65, "ap": 106, "pr": 80, "br": 46, "ri": 20,
                "nf": 0, "la": 4, "hs": 95, "f4": 4000, "b4": 250, "f5": 6000, "b5": 6000,
                "gf": 72, "gh": 70, "gv": 65, "gn": 73, "g1": 69, "g2": 72, "g3": 48, "g4": 54,
                "ft": 0, "bf": 0, "lx": 0, "qu": 30, "hr": 20, "sr": 32],
        .wendy: ["sx": 0, "sm": 100, "as": 50, "ap": 200, "pr": 175, "br": 55, "ri": 0,
                 "nf": 10, "la": 0, "hs": 100, "f4": 4500, "b4": 400, "f5": 6000, "b5": 6000,
                 "gf": 70, "gh": 68, "gv": 51, "gn": 75, "g1": 69, "g2": 62, "g3": 53, "g4": 55,
                 "ft": 100, "bf": 0, "lx": 80, "qu": 10, "hr": 20, "sr": 22],
    ]
}

/// A user-designed DECtalk voice: a name, a base built-in, and a value for every
/// `[:dv]` parameter. Persisted in the shared settings and exchanged as `.dtv`.
public struct DECtalkCustomVoice: Codable, Equatable, Sendable {
    public var name: String
    public var base: DECtalkSynthesizer.Speaker
    /// Every one of the 28 `[:dv]` codes → value (clamped to the engine's range).
    public var params: [String: Int]

    public init(name: String, base: DECtalkSynthesizer.Speaker, params: [String: Int]) {
        self.name = name
        self.base = base
        self.params = DECtalkCustomVoice.cleaned(params, base: base)
    }

    /// A fresh voice snapshotting `base`'s built-in parameters.
    public init(name: String, base: DECtalkSynthesizer.Speaker = .paul) {
        self.init(name: name, base: base, params: base.builtInParams)
    }

    /// Validate + clamp a raw parameter map to the full 28-code set, filling any
    /// missing code from the base voice's default (matches the add-on's
    /// `_cleanParams`, but forgiving of missing keys rather than throwing).
    public static func cleaned(_ params: [String: Int], base: DECtalkSynthesizer.Speaker) -> [String: Int] {
        var out: [String: Int] = [:]
        let defaults = base.builtInParams
        for p in DECtalkParameter.voiceParameters {
            let raw = params[p.code] ?? defaults[p.code] ?? p.neutral
            out[p.code] = p.clamp(raw)
        }
        return out
    }

    // MARK: - .dtv exchange format (identical to the NVDA add-on's)

    public static let dtvFormat = "dectalk-voice"
    public static let dtvVersion = 1

    enum VoiceStoreError: LocalizedError {
        case notDtv, tooNew
        var errorDescription: String? {
            switch self {
            case .notDtv: return "Not a DECtalk voice (.dtv) file."
            case .tooNew: return "This voice file needs a newer version of the app."
            }
        }
    }

    /// Encode as pretty-printed, sorted `.dtv` JSON.
    public func dtvData() throws -> Data {
        // Build the document by hand (rather than Codable) so the on-disk shape
        // exactly matches the add-on: format/version/name/base(id)/params.
        let doc: [String: Any] = [
            "format": Self.dtvFormat,
            "version": Self.dtvVersion,
            "name": name,
            "base": base.id,
            "params": params,
        ]
        return try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
    }

    /// Decode a `.dtv` document. The returned voice's `name` is the file's own
    /// name; callers dedupe it against existing voices.
    public static func fromDtv(_ data: Data) throws -> DECtalkCustomVoice {
        guard let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              doc["format"] as? String == dtvFormat else {
            throw VoiceStoreError.notDtv
        }
        if let v = doc["version"] as? Int, v > dtvVersion { throw VoiceStoreError.tooNew }
        let name = (doc["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = DECtalkSynthesizer.Speaker(id: doc["base"] as? String ?? "paul") ?? .paul
        let raw = (doc["params"] as? [String: Int]) ?? [:]
        return DECtalkCustomVoice(name: (name?.isEmpty == false ? name! : "Imported voice"),
                                  base: base, params: raw)
    }
}

/// Which voice the app / extension should speak with: a stock built-in, or a
/// user-designed custom voice referenced by name.
public enum DECtalkVoiceSelection: Hashable, Sendable {
    case builtIn(DECtalkSynthesizer.Speaker)
    case custom(String)
}
