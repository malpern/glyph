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
                    LabeledContent("OpenAI") { Text(openAIKeySaved ? "Saved" : "Not set").foregroundStyle(.secondary) }
                    SecureField(openAIKeySaved ? "Enter to replace OpenAI key" : "OpenAI API key (sk-…)", text: $openAIKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(openAIKeySaved ? "Update OpenAI Key" : "Save OpenAI Key") { saveOpenAIKey() }
                        .disabled(openAIKey.trimmingCharacters(in: .whitespaces).isEmpty)

                    LabeledContent("ElevenLabs") { Text(elevenLabsKeySaved ? "Saved" : "Not set").foregroundStyle(.secondary) }
                    SecureField(elevenLabsKeySaved ? "Enter to replace ElevenLabs key" : "ElevenLabs API key", text: $elevenLabsKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(elevenLabsKeySaved ? "Update ElevenLabs Key" : "Save ElevenLabs Key") { saveElevenLabsKey() }
                        .disabled(elevenLabsKey.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("TTS API keys")
                } footer: {
                    Text("For OpenAI / ElevenLabs read-aloud voices, billed to your own account. Pick the provider and voice in the reader's Aa menu. Apple's voice is on-device and free — no key needed.")
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
