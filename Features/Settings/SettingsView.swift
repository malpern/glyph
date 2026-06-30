import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// App settings: read-aloud granularity, plus sync — show this device's key (copy /
/// QR) to bring other devices onto the same account, or paste another device's key to
/// join it. No passwords, no email — the key is the whole credential.
struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var pasteText = ""
    @State private var copied = false
    @State private var openAIKey = ""
    @State private var openAIKeySaved = false
    @State private var elevenLabsKey = ""
    @State private var elevenLabsKeySaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Highlight", selection: Binding(
                        get: { container.readerSettings.settings.highlightGranularity },
                        set: { container.readerSettings.settings.highlightGranularity = $0 }
                    )) {
                        ForEach(HighlightGranularity.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Read-aloud")
                } footer: {
                    Text("How the spoken position is highlighted and followed — and how often the X4 e-ink screen refreshes. Sentence is best for active read-along; Paragraph is calmer; Off is audio-only (no highlight, nothing sent to the X4).")
                }

                Section {
                    Picker("Voice", selection: Binding(
                        get: { container.readerSettings.settings.ttsProvider },
                        set: { container.readerSettings.settings.ttsProvider = $0 }
                    )) {
                        ForEach(TTSProvider.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if container.readerSettings.settings.ttsProvider == .openai {
                        Picker("OpenAI voice", selection: Binding(
                            get: { container.readerSettings.settings.openAIVoice },
                            set: { container.readerSettings.settings.openAIVoice = $0 }
                        )) {
                            ForEach(OpenAISpeechEngine.voices, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        SecureField(openAIKeySaved ? "API key saved — enter to replace" : "OpenAI API key (sk-…)", text: $openAIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(openAIKeySaved ? "Update Key" : "Save Key") { saveOpenAIKey() }
                            .disabled(openAIKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if container.readerSettings.settings.ttsProvider == .elevenlabs {
                        Picker("ElevenLabs voice", selection: Binding(
                            get: { container.readerSettings.settings.elevenLabsVoiceID },
                            set: { container.readerSettings.settings.elevenLabsVoiceID = $0 }
                        )) {
                            ForEach(ElevenLabsSpeechEngine.voices, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        SecureField(elevenLabsKeySaved ? "API key saved — enter to replace" : "ElevenLabs API key", text: $elevenLabsKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(elevenLabsKeySaved ? "Update Key" : "Save Key") { saveElevenLabsKey() }
                            .disabled(elevenLabsKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("OpenAI reads with a cloud voice using your own API key (billed to you). Apple is on-device and free. A voice change applies the next time you open a book.")
                }

                Section {
                    Text(SyncKey.grouped(key))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button { copyKey() } label: {
                        Label(copied ? "Copied" : "Copy Key",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    if let qr = qrImage(key) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .accessibilityLabel("Sync key QR code")
                    }
                } header: {
                    Text("Your sync key")
                } footer: {
                    Text("Any device that uses this key shares your reading positions. Treat it like a password.")
                }

                Section {
                    TextField("Paste a key", text: $pasteText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use This Key") { adoptPastedKey() }
                        .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Use another device's key")
                } footer: {
                    Text("Replaces this device's key so it joins that account.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                key = container.keyAuth.currentKey()
                openAIKeySaved = KeychainHelper.hasKey(account: KeychainHelper.Account.openAI)
                elevenLabsKeySaved = KeychainHelper.hasKey(account: KeychainHelper.Account.elevenLabs)
            }
        }
    }

    private func saveOpenAIKey() {
        KeychainHelper.save(openAIKey, account: KeychainHelper.Account.openAI)
        openAIKeySaved = KeychainHelper.hasKey(account: KeychainHelper.Account.openAI)
        openAIKey = ""
    }

    private func saveElevenLabsKey() {
        KeychainHelper.save(elevenLabsKey, account: KeychainHelper.Account.elevenLabs)
        elevenLabsKeySaved = KeychainHelper.hasKey(account: KeychainHelper.Account.elevenLabs)
        elevenLabsKey = ""
    }

    private func copyKey() {
        UIPasteboard.general.string = key
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private func adoptPastedKey() {
        let cleaned = pasteText.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        Task {
            await container.keyAuth.useKey(cleaned)
            key = container.keyAuth.currentKey()
            pasteText = ""
        }
    }

    private func qrImage(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
