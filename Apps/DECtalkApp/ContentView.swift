import SwiftUI
import DECtalkKit

struct ContentView: View {
    @StateObject private var player = DECtalkPlayer()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $player.text)
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))

                Picker("Voice", selection: $player.speaker) {
                    ForEach(player.speakers, id: \.self) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: player.speak) {
                        Label("Speak", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(player.isSpeaking)

                    Button(action: player.stop) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!player.isSpeaking)

                    Spacer()
                    Text(player.status)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("DECtalk")
            .toolbar {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(store: player.store, speaker: player.speaker)
                        .navigationTitle("Settings — \(player.speaker.displayName)")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            Button("Done") { showSettings = false }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 560)
                #endif
            }
        }
    }
}

#Preview {
    ContentView()
}
