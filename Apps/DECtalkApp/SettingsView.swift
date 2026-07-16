import SwiftUI
import DECtalkKit

/// Global DECtalk controls: rate, volume, SPF and pauses that apply to every
/// voice. Per-voice `[:dv]` design now lives in the Voice Manager, so this
/// screen no longer lists the 28 voice parameters.
struct SettingsView: View {
    @ObservedObject var store: DECtalkSettingsStore

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

            Section {
                Button("Reset all global settings", role: .destructive) {
                    let voices = store.settings.customVoices   // keep the user's voices
                    store.resetToDefaults()
                    store.settings.customVoices = voices
                }
            } footer: {
                Text("Design and manage individual voices in the Voice Manager. This resets only the global sliders above.")
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
            Slider(
                value: Binding(get: { Double(value) },
                               set: { value = Int($0.rounded()) }),
                in: Double(param.range.lowerBound)...Double(param.range.upperBound))
        }
    }
}

/// A labelled slider for one `[:dv]` voice parameter, editing a raw Int value in
/// the parameter's engine range. Used by the Voice Manager's editor.
struct VoiceParameterSlider: View {
    let param: DECtalkParameter
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(param.name)
                Spacer()
                Text("\(value)\(param.unit.isEmpty ? "" : " " + param.unit)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { Double(value) },
                               set: { value = param.clamp(Int($0.rounded())) }),
                in: Double(param.range.lowerBound)...Double(param.range.upperBound))
        }
    }
}
