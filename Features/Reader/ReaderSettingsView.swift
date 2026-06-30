import SwiftUI

/// The reading-appearance panel (theme / text size / spacing / font). Changes apply
/// to the page live behind the sheet, Apple-Books style.
struct ReaderSettingsView: View {
    @Bindable var store: ReaderSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $store.settings.theme) {
                        ForEach(ReaderTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Text size") {
                    HStack(spacing: 16) {
                        Button { adjustFont(-0.1) } label: { Text("A").font(.footnote) }
                            .buttonStyle(.bordered)
                        Slider(value: $store.settings.fontScale, in: 0.8...2.0, step: 0.1)
                        Button { adjustFont(0.1) } label: { Text("A").font(.title2) }
                            .buttonStyle(.bordered)
                    }
                    Text("\(Int(store.settings.fontScale * 100))%")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Section("Line spacing") {
                    Slider(value: $store.settings.lineHeight, in: 1.0...2.2, step: 0.1)
                }

                Section("Font") {
                    Picker("Font", selection: $store.settings.font) {
                        ForEach(ReaderFont.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Picker("Highlight", selection: $store.settings.highlightGranularity) {
                        ForEach(HighlightGranularity.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Voice", selection: $store.settings.ttsProvider) {
                        ForEach(TTSProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    switch store.settings.ttsProvider {
                    case .openai:
                        Picker("OpenAI voice", selection: $store.settings.openAIVoice) {
                            ForEach(OpenAISpeechEngine.voices, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    case .elevenlabs:
                        Picker("ElevenLabs voice", selection: $store.settings.elevenLabsVoiceID) {
                            ForEach(ElevenLabsSpeechEngine.voices, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    case .apple:
                        EmptyView()
                    }
                } header: {
                    Text("Read-aloud")
                } footer: {
                    Text("Highlight granularity and the voice that reads aloud. OpenAI/ElevenLabs need an API key (Settings → TTS keys), and fall back to Apple if the key's missing or a request fails. Voice changes apply right away.")
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func adjustFont(_ delta: Double) {
        store.settings.fontScale = min(2.0, max(0.8, (store.settings.fontScale + delta)))
    }
}
