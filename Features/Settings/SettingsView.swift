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
            .onAppear { key = container.keyAuth.currentKey() }
        }
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
