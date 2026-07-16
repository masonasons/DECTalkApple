import Foundation

/// All DECtalk tunables. Global parameters (rate, volume, SPF, pauses) apply to
/// every voice. The `[:dv]` voice parameters are no longer tweaked per built-in
/// here — voice design happens in the Voice Manager, which stores complete named
/// ``DECtalkCustomVoice`` definitions in ``customVoices``.
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

    /// User-designed voices, keyed by name (see the Voice Manager). Shared with
    /// the extension via the settings file so custom voices are speakable there.
    public var customVoices: [String: DECtalkCustomVoice] = [:]

    public init() {}

    // Forgiving decoder: missing keys fall back to defaults, so adding new
    // settings never invalidates a previously-saved file.
    enum CodingKeys: String, CodingKey {
        case rate, volume, spf, sentencePause, commaPause, honorVoiceOverPauses, customVoices
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rate = try c.decodeIfPresent(Int.self, forKey: .rate) ?? rate
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume
        spf = try c.decodeIfPresent(Int.self, forKey: .spf) ?? spf
        sentencePause = try c.decodeIfPresent(Int.self, forKey: .sentencePause) ?? sentencePause
        commaPause = try c.decodeIfPresent(Int.self, forKey: .commaPause) ?? commaPause
        honorVoiceOverPauses = try c.decodeIfPresent(Bool.self, forKey: .honorVoiceOverPauses) ?? honorVoiceOverPauses
        customVoices = try c.decodeIfPresent([String: DECtalkCustomVoice].self, forKey: .customVoices) ?? [:]
    }

    /// Custom voices sorted by name (the order the UI and voice list present).
    public var sortedCustomVoices: [DECtalkCustomVoice] {
        customVoices.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Command string

    /// Global inline command prefix shared by every voice:
    /// `[:rate 200][:vo set 72][:spf 100][:pp 0 :cp 0]`.
    private var globalPrefix: String {
        "[:rate \(rate)][:vo set \(volume)][:spf \(spf)][:pp \(sentencePause) :cp \(commaPause)]"
    }

    /// Command prefix for a stock built-in voice: globals only. The base voice is
    /// selected through the engine's speaker API, so no `[:dv]` is needed.
    public func commandPrefix(for speaker: DECtalkSynthesizer.Speaker) -> String {
        globalPrefix
    }

    /// Command prefix for a custom voice: globals plus every `[:dv]` parameter
    /// (a custom voice is fully defined by its parameters — `[:nX]`/the base
    /// speaker only gives the engine its starting point).
    public func commandPrefix(for voice: DECtalkCustomVoice) -> String {
        let dv = DECtalkParameter.voiceParameters
            .compactMap { p in voice.params[p.code].map { "\(p.code) \($0)" } }
            .joined(separator: " ")
        return dv.isEmpty ? globalPrefix : globalPrefix + "[:dv \(dv)]"
    }

    // MARK: - Voice selection

    /// Resolve a selection to the inline prefix and the base built-in speaker the
    /// engine should be switched to before rendering.
    public func resolve(_ selection: DECtalkVoiceSelection) -> (prefix: String, base: DECtalkSynthesizer.Speaker) {
        switch selection {
        case .builtIn(let speaker):
            return (commandPrefix(for: speaker), speaker)
        case .custom(let name):
            if let voice = customVoices[name] {
                return (commandPrefix(for: voice), voice.base)
            }
            return (commandPrefix(for: .paul), .paul)   // deleted underfoot → fall back
        }
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

    // MARK: - Custom voice management (mirrors the add-on's _voicestore)

    /// Save (or overwrite) a custom voice. Returns the stored name (trimmed).
    @discardableResult
    public func saveVoice(_ voice: DECtalkCustomVoice) -> String {
        var v = voice
        v.name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.name.isEmpty else { return "" }
        settings.customVoices[v.name] = v
        return v.name
    }

    /// Rename `oldName` to the (already-set) name of `voice`, dropping the old
    /// record. If the name is unchanged this is a plain save.
    public func renameVoice(from oldName: String, to voice: DECtalkCustomVoice) {
        let newName = saveVoice(voice)
        if !newName.isEmpty, oldName != newName {
            settings.customVoices[oldName] = nil
        }
    }

    public func deleteVoice(_ name: String) {
        settings.customVoices[name] = nil
    }

    /// A name not already taken (appends " (2)", " (3)", … as the add-on does).
    public func uniqueName(basedOn name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported voice" : name
        if settings.customVoices[base] == nil { return base }
        var n = 2
        while settings.customVoices["\(base) (\(n))"] != nil { n += 1 }
        return "\(base) (\(n))"
    }

    /// Write custom voice `name` to `url` as a `.dtv` file.
    public func exportVoice(_ name: String, to url: URL) throws {
        guard let voice = settings.customVoices[name] else {
            throw DECtalkCustomVoice.VoiceStoreError.notDtv
        }
        try voice.dtvData().write(to: url, options: .atomic)
    }

    /// Import a `.dtv` file, deduplicating its name. Returns the stored name.
    @discardableResult
    public func importVoice(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var voice = try DECtalkCustomVoice.fromDtv(data)
        voice.name = uniqueName(basedOn: voice.name)
        return saveVoice(voice)
    }
}
