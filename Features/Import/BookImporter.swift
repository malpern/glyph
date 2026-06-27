import Foundation
import CryptoKit
import ReaderCore

/// Imports an EPUB into the local library: inspect → derive a stable identity →
/// copy the file and cover into the app container → persist a `Book`.
///
/// Depends only on the `LibraryRepository` protocol and the Readium boundary's
/// `Sendable` snapshot — it never holds a Readium `Publication`, so it's `Sendable`
/// and runs off the main actor (good for the file I/O).
struct BookImporter: Sendable {
    let library: any LibraryRepository
    let storage: BookStorage

    @discardableResult
    func importBook(from sourceURL: URL) async throws -> Book {
        // Files handed over by the system picker are security-scoped.
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let meta = try await ReadiumStack.inspect(at: sourceURL)
        let fileData = try Data(contentsOf: sourceURL)

        // Content-derived identity (see PROJECT.md): prefer the EPUB's own
        // dc:identifier so the same book matches across devices; fall back to a
        // file hash. The on-disk filename is a hash of the id, so it's always
        // filesystem-safe regardless of what the identifier contains.
        let bookID = stableID(identifier: meta.identifier, fileData: fileData)
        let key = Self.hex(SHA256.hash(data: Data(bookID.utf8)))

        let bookRel = storage.bookRelativePath(key: key)
        try? FileManager.default.removeItem(at: storage.absoluteURL(for: bookRel))   // re-import overwrites
        try fileData.write(to: storage.absoluteURL(for: bookRel), options: .atomic)

        var coverRel: String?
        if let png = meta.coverPNG {
            let rel = storage.coverRelativePath(key: key)
            try? png.write(to: storage.absoluteURL(for: rel), options: .atomic)
            coverRel = rel
        }

        let title = meta.title ?? sourceURL.deletingPathExtension().lastPathComponent
        let book = Book(id: bookID, title: title, author: meta.author, coverPath: coverRel, filePath: bookRel)
        try await library.upsert(book)
        return book
    }

    // MARK: -

    private func stableID(identifier: String?, fileData: Data) -> String {
        if let identifier, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return identifier
        }
        return "sha256:" + Self.hex(SHA256.hash(data: fileData))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
