import SwiftUI
import DECtalkKit

/// Full DECtalk control panel: global parameters plus per-voice `[:dv]`
/// overrides for the currently selected speaker.
struct SettingsView: View {
    @ObservedObject var store: DECtalkSettingsStore
    let speaker: DECtalkSynthesizer.Speaker

    var body: some View {
        Form {
            Section {
                ForEach(DECtalkGlobalParameter.all) { param in
                    GlobalSliderRow(param: param, value: globalBinding(param))
                }
                Toggle("Honor VoiceOver pauses", isOn: Binding(
                    get: { store.settings.honorVoiceOverPauses },
                    set: { store.settings.honorVoiceOverPauses = $0 }))
            } header: {
                Text("Global — applies to every voice")
            } footer: {
                Text("Converts VoiceOver's SSML breaks into DECtalk [:slnc] silence between spoken items.")
            }

            ForEach(DECtalkParameter.Category.allCases, id: \.self) { category in
                Section("\(speaker.displayName) · \(category.rawValue)") {
                    ForEach(DECtalkParameter.voiceParameters(in: category)) { param in
                        VoiceParameterRow(param: param, speaker: speaker, store: store)
                    }
                }
            }

            Section {
                Button("Reset \(speaker.displayName)'s voice") {
                    store.settings.clearAllOverrides(for: speaker)
                }
                Button("Reset all settings", role: .destructive) {
                    store.resetToDefaults()
                }
            } footer: {
                Text("Per-voice parameters left on “auto” keep the voice's built-in value.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private func globalBinding(_ p: DECtalkGlobalParameter) -> Binding<Int> {
        switch p.key {
        case "rate":          return Binding(get: { store.settings.rate },          set: { store.settings.rate = $0 })
        case "volume":        return Binding(get: { store.settings.volume },        set: { store.settings.volume = $0 })
        case "spf":           return Binding(get: { store.settings.spf },           set: { store.settings.spf = $0 })
        case "sentencePause": return Binding(get: { store.settings.sentencePause }, set: { store.settings.sentencePause = $0 })
        case "commaPause":    return Binding(get: { store.settings.commaPause },    set: { store.settings.commaPause = $0 })
        default:              return .constant(0)
        }
    }
}

/// A labelled slider for an always-on global parameter.
struct GlobalSliderRow: View {
    let param: DECtalkGlobalParameter
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(param.name)
                Spacer()
                Text("\(value)\(param.unit.isEmpty ? "" : " " + param.unit)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            // The slider below carries the name and value for VoiceOver, so this
            // visual row would just be read twice.
            .accessibilityHidden(true)

            Slider(
                value: Binding(get: { Double(value) },
                               set: { value = Int($0.rounded()) }),
                in: Double(param.range.lowerBound)...Double(param.range.upperBound),
                step: Double(param.step))
                .accessibilityLabel(param.name)
                .accessibilityValue(param.spokenValue(value))
        }
    }
}

extension DECtalkGlobalParameter {
    /// What VoiceOver should say for a value — the real number and its unit,
    /// not the percentage-of-range a bare SwiftUI slider announces.
    func spokenValue(_ value: Int) -> String {
        Self.spoken(value, unit: unit)
    }

    static func spoken(_ value: Int, unit: String) -> String {
        switch unit {
        case "":    return "\(value)"
        case "ms":  return "\(value) milliseconds"
        case "Hz":  return "\(value) hertz"
        case "dB":  return "\(value) decibels"
        case "wpm": return "\(value) words per minute"
        case "%":   return "\(value) percent"
        default:    return "\(value) \(unit)"
        }
    }
}

extension DECtalkParameter {
    func spokenValue(_ value: Int) -> String {
        DECtalkGlobalParameter.spoken(value, unit: unit)
    }
}

/// A per-voice `[:dv]` parameter: a toggle to override the voice's built-in
/// value, plus a slider that's active only while the override is on.
struct VoiceParameterRow: View {
    let param: DECtalkParameter
    let speaker: DECtalkSynthesizer.Speaker
    @ObservedObject var store: DECtalkSettingsStore

    var body: some View {
        let stored = store.settings.override(param.code, for: speaker)
        let overridden = stored != nil
        let current = stored ?? param.neutral

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(isOn: Binding(
                    get: { overridden },
                    set: { on in
                        if on { store.settings.setOverride(param.code, current, for: speaker) }
                        else { store.settings.clearOverride(param.code, for: speaker) }
                    })) {
                    Text(param.name)
                }
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                Spacer()
                Text(overridden ? "\(current)\(param.unit.isEmpty ? "" : " " + param.unit)" : "auto")
                    .monospacedDigit()
                    .foregroundStyle(overridden ? .secondary : .tertiary)
                    // The toggle announces the name, the slider announces the
                    // value — this label would be a third redundant stop.
                    .accessibilityHidden(true)
            }
            Slider(
                value: Binding(get: { Double(current) },
                               set: { store.settings.setOverride(param.code, Int($0.rounded()), for: speaker) }),
                in: Double(param.range.lowerBound)...Double(param.range.upperBound),
                step: Double(param.step))
            .disabled(!overridden)
            .accessibilityLabel(param.name)
            .accessibilityValue(overridden ? param.spokenValue(current) : "auto")
        }
    }
}
