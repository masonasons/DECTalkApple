import Foundation

/// All DECtalk tunables. Global parameters (rate, volume, SPF, pauses) apply to
/// every voice; the `[:dv]` voice parameters are stored per speaker so each
/// voice can be customized independently.
public struct DECtalkSettings: Codable, Equatable, Sendable {
    // Global (voice-independent)
    public var rate: Int          = 200   // [:rate N]
    public var volume: Int        = 72    // [:vo set N]
    public var spf: Int           = 100   // [:spf N]
    public var sentencePause: Int = 0     // [:pp N] — added to the default period pause
    public var commaPause: Int    = 0     // [:cp N] — added to the default comma pause

    /// When true, the voice extension turns VoiceOver's SSML `<break>` elements
    /// into DECtalk `[:slnc N]` silence so pauses between spoken items are kept.
    public var honorVoiceOverPauses: Bool = true

    /// Per-voice `[:dv]` overrides: speaker raw value → (parameter code → value).
    /// Only present codes are emitted; absent codes keep the speaker's own value.
    public var voiceOverrides: [Int: [String: Int]] = [:]

    public init() {}

    // Forgiving decoder: missing keys fall back to defaults, so adding new
    // settings never invalidates a previously-saved file.
    enum CodingKeys: String, CodingKey {
        case rate, volume, spf, sentencePause, commaPause, honorVoiceOverPauses, voiceOverrides
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rate = try c.decodeIfPresent(Int.self, forKey: .rate) ?? rate
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume
        spf = try c.decodeIfPresent(Int.self, forKey: .spf) ?? spf
        sentencePause = try c.decodeIfPresent(Int.self, forKey: .sentencePause) ?? sentencePause
        commaPause = try c.decodeIfPresent(Int.self, forKey: .commaPause) ?? commaPause
        honorVoiceOverPauses = try c.decodeIfPresent(Bool.self, forKey: .honorVoiceOverPauses) ?? honorVoiceOverPauses
        voiceOverrides = try c.decodeIfPresent([Int: [String: Int]].self, forKey: .voiceOverrides) ?? [:]
    }

    // MARK: - Per-voice override access

    public func override(_ code: String, for speaker: DECtalkSynthesizer.Speaker) -> Int? {
        voiceOverrides[speaker.rawValue]?[code]
    }

    public mutating func setOverride(_ code: String, _ value: Int, for speaker: DECtalkSynthesizer.Speaker) {
        voiceOverrides[speaker.rawValue, default: [:]][code] = value
    }

    public mutating func clearOverride(_ code: String, for speaker: DECtalkSynthesizer.Speaker) {
        voiceOverrides[speaker.rawValue]?[code] = nil
        if voiceOverrides[speaker.rawValue]?.isEmpty == true {
            voiceOverrides[speaker.rawValue] = nil
        }
    }

    public mutating func clearAllOverrides(for speaker: DECtalkSynthesizer.Speaker) {
        voiceOverrides[speaker.rawValue] = nil
    }

    // MARK: - Command string

    /// The inline DECtalk command prefix for `speaker`, e.g.
    /// `[:rate 200][:vo set 72][:spf 100][:pp 0 :cp 0][:dv ap 180 hs 120]`.
    public func commandPrefix(for speaker: DECtalkSynthesizer.Speaker) -> String {
        var out = "[:rate \(rate)][:vo set \(volume)][:spf \(spf)]"
        out += "[:pp \(sentencePause) :cp \(commaPause)]"

        if let overrides = voiceOverrides[speaker.rawValue], !overrides.isEmpty {
            // Emit in catalog order for stable, readable output.
            let dv = DECtalkParameter.voiceParameters
                .compactMap { p in overrides[p.code].map { "\(p.code) \($0)" } }
                .joined(separator: " ")
            if !dv.isEmpty { out += "[:dv \(dv)]" }
        }
        return out
    }
}

/// Loads and persists ``DECtalkSettings`` as a JSON file inside a shared App
/// Group container, so the host app and the system-voice extension read/write
/// the same file. A plain file is used rather than `UserDefaults(suiteName:)`
/// because cfprefsd does not reliably flush App Group defaults to disk across
/// process launches.
public final class DECtalkSettingsStore: ObservableObject {
    // App Group container shared by the app and the voice extension.
    // On macOS a Team-ID-prefixed group is granted to any app signed by the team
    // without portal registration; iOS requires the "group." form (registered
    // automatically by Xcode when the capability is added).
    #if os(macOS)
    public static let appGroupID = "9QBYDAX396.com.dectalkapple.shared"
    #else
    public static let appGroupID = "group.com.dectalkapple.shared"
    #endif
    private static let fileName = "dectalk-settings.json"

    private let fileURL: URL?

    @Published public var settings: DECtalkSettings {
        didSet { if settings != oldValue { save() } }
    }

    /// - Parameter containerURL: directory to store settings in. Defaults to the
    ///   App Group container; tests pass a temporary directory.
    public init(containerURL: URL? = DECtalkSettingsStore.defaultContainerURL()) {
        self.fileURL = containerURL?.appendingPathComponent(DECtalkSettingsStore.fileName)
        self.settings = DECtalkSettingsStore.decode(fileURL) ?? DECtalkSettings()
    }

    /// Read-only load, for the extension.
    public static func load(containerURL: URL? = DECtalkSettingsStore.defaultContainerURL()) -> DECtalkSettings {
        decode(containerURL?.appendingPathComponent(fileName)) ?? DECtalkSettings()
    }

    public static func defaultContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func decode(_ url: URL?) -> DECtalkSettings? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DECtalkSettings.self, from: data)
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func resetToDefaults() {
        settings = DECtalkSettings()
    }
}
