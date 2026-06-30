import SwiftUI

/// App root. For Phase 1 this is simply the library; navigation into the reader
/// is handled inside `LibraryView` via a full-screen cover.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        LibraryView(viewModel: LibraryViewModel(
            library: container.library,
            importer: container.makeImporter()
        ))
        // "Open with Glyph" from Files/Mail/Safari: drop the EPUB into Documents so the
        // library's inbox ingest (on appear / foreground) imports it.
        .onOpenURL { url in Task { await Self.copyIntoInbox(url) } }
    }

    private static func copyIntoInbox(_ url: URL) async {
        let fm = FileManager.default
        guard url.pathExtension.lowercased() == "epub",
              let documents = try? fm.url(
                  for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
              ) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = documents.appendingPathComponent(url.lastPathComponent)
        guard !fm.fileExists(atPath: dest.path) else { return }   // already queued
        try? fm.copyItem(at: url, to: dest)
    }
}
