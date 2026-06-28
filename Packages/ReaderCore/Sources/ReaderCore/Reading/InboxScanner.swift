import Foundation

/// Selects which files dropped into the app's Documents "inbox" (AirDrop, the Files
/// app, "Open in Glyph", a direct USB copy) should be auto-imported as books.
///
/// Pulled out of the view model so the selection rule — which is easy to get subtly
/// wrong — is unit-tested without a simulator or a real filesystem.
public enum InboxScanner {
    /// Given a directory listing, the EPUB files to ingest, in a deterministic order.
    ///
    /// - Matches the `epub` extension **case-insensitively**, so `.EPUB` / `.Epub`
    ///   from various senders are caught.
    /// - Skips macOS **AppleDouble** stubs (`._Book.epub`) that AirDrop and USB copies
    ///   leave beside the real file — they carry the `.epub` extension but are just
    ///   resource-fork metadata, so importing one only produces a spurious error.
    /// - Returns the survivors sorted by file name (natural order: `Book2` before
    ///   `Book10`), so ingest order doesn't depend on unspecified directory ordering.
    public static func epubsToIngest(in contents: [URL]) -> [URL] {
        contents
            .filter { $0.pathExtension.lowercased() == "epub" }
            .filter { !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
