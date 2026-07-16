import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import DECtalkKit

/// Design custom DECtalk voices and exchange them as `.dtv` files — the app's
/// equivalent of the DECtalk NVDA add-on's Voice Manager. A custom voice is a
/// base built-in plus a value for every one of the 28 `[:dv]` parameters; saved
/// voices appear in the main voice picker (and as system voices) next to the
/// built-ins. SPF / sentence pause / comma pause stay global (in Settings).
struct VoiceManagerView: View {
    @ObservedObject var store: DECtalkSettingsStore
    let player: DECtalkPlayer

    @State private var editing: EditorContext?
    @State private var exportingName: String?
    @State private var showImporter = false
    @State private var errorMessage: String?

    private struct EditorContext: Identifiable {
        let id = UUID()
        let originalName: String?      // nil when creating a new voice
        var voice: DECtalkCustomVoice
    }

    private var voices: [DECtalkCustomVoice] { store.settings.sortedCustomVoices }

    var body: some View {
        List {
            Section {
                Button {
                    editing = EditorContext(originalName: nil,
                                            voice: DECtalkCustomVoice(name: newVoiceName(), base: .paul))
                } label: {
                    Label("New Voice", systemImage: "plus.circle.fill")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import from .dtv…", systemImage: "square.and.arrow.down")
                }
            }

            Section("My voices") {
                if voices.isEmpty {
                    Text("No custom voices yet. Tap “New Voice” to design one, or import a .dtv file.")
                        .foregroundStyle(.secondary)
                }
                ForEach(voices, id: \.name) { voice in
                    row(for: voice)
                }
            }
        }
        .navigationTitle("Voice Manager")
        .sheet(item: $editing) { ctx in
            NavigationStack {
                VoiceEditorView(
                    voice: ctx.voice,
                    isNew: ctx.originalName == nil,
                    onTest: { player.preview($0) },
                    onSave: { saved in
                        if let original = ctx.originalName {
                            store.renameVoice(from: original, to: saved)
                        } else {
                            store.saveVoice(saved)
                        }
                        refreshSystemVoices()
                        editing = nil
                    },
                    onCancel: { editing = nil })
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 600)
            #endif
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [Self.dtvType, .json],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .fileExporter(isPresented: Binding(get: { exportingName != nil },
                                           set: { if !$0 { exportingName = nil } }),
                      document: exportDocument,
                      contentType: Self.dtvType,
                      defaultFilename: exportingName) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            exportingName = nil
        }
        .alert("Voice Manager", isPresented: Binding(get: { errorMessage != nil },
                                                     set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private func row(for voice: DECtalkCustomVoice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                Text("Based on \(voice.base.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                player.preview(voice)
            } label: { Image(systemName: "play.circle") }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editing = EditorContext(originalName: voice.name, voice: voice)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteVoice(voice.name)
                player.validateSelection()
                refreshSystemVoices()
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                exportingName = voice.name
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .tint(.blue)
        }
        .contextMenu {
            Button("Edit") { editing = EditorContext(originalName: voice.name, voice: voice) }
            Button("Export…") { exportingName = voice.name }
            Button("Delete", role: .destructive) {
                store.deleteVoice(voice.name)
                player.validateSelection()
                refreshSystemVoices()
            }
        }
    }

    // MARK: - Import / export

    private var exportDocument: DTVDocument {
        guard let name = exportingName, let data = try? store.settings.customVoices[name]?.dtvData() else {
            return DTVDocument(data: Data())
        }
        return DTVDocument(data: data)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var imported = 0
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { _ = try store.importVoice(from: url); imported += 1 }
                catch { errorMessage = "Couldn’t import \(url.lastPathComponent): \(error.localizedDescription)" }
            }
            if imported > 0 { refreshSystemVoices() }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func newVoiceName() -> String {
        store.uniqueName(basedOn: "Custom Voice")
    }

    /// Ask the system to re-query the extension's voice list so newly saved /
    /// deleted custom voices show up under Spoken Content without a relaunch.
    private func refreshSystemVoices() {
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
    }

    static let dtvType = UTType(filenameExtension: "dtv") ?? .json
}

/// FileDocument wrapper so `.fileExporter` can write a `.dtv` file.
struct DTVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [VoiceManagerView.dtvType, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Design one voice: name, base voice, and a slider per `[:dv]` parameter,
/// grouped by category, with a Test button. Sliders behave exactly as the old
/// per-voice sliders did — they just live here now.
struct VoiceEditorView: View {
    @State var voice: DECtalkCustomVoice
    let isNew: Bool
    let onTest: (DECtalkCustomVoice) -> Void
    let onSave: (DECtalkCustomVoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section("Voice") {
                TextField("Name", text: $voice.name)
                Picker("Based on", selection: baseBinding) {
                    ForEach(DECtalkSynthesizer.Speaker.allCases, id: \.self) { speaker in
                        Text(speaker.displayName).tag(speaker)
                    }
                }
            }

            ForEach(DECtalkParameter.Category.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(DECtalkParameter.voiceParameters(in: category)) { param in
                        VoiceParameterSlider(param: param, value: paramBinding(param))
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(isNew ? "New Voice" : "Edit Voice")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { onSave(voice) }
                    .disabled(voice.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    onTest(voice)
                } label: { Label("Test", systemImage: "play.fill") }
            }
        }
    }

    private var baseBinding: Binding<DECtalkSynthesizer.Speaker> {
        Binding(get: { voice.base }, set: { newBase in
            // Picking a base is a clean starting point: reset every parameter to
            // that voice's built-in defaults (matches the add-on's editor).
            voice.base = newBase
            voice.params = newBase.builtInParams
        })
    }

    private func paramBinding(_ param: DECtalkParameter) -> Binding<Int> {
        Binding(
            get: { voice.params[param.code] ?? param.neutral },
            set: { voice.params[param.code] = param.clamp($0) })
    }
}
