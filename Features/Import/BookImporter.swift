import Foundation
import CryptoKit
import UIKit
import ReadiumShared
import ReaderCore

/// Imports an EPUB into the local library: parse → derive a stable identity →
/// copy the file and cover into the app container → persist a `Book`.
///
/// Depends only on the `LibraryRepository` protocol and the Readium boundary, so
/// it has no knowledge of SwiftData. `Sendable` and free of stored mutable state,
/// so it runs off the main actor.
struct BookImporter: Sendable {
    let library: LibraryRepository
    let storage: BookStorage

    @discardableResult
    func importBook(from sourceURL: URL) async throws -> Book {
        // Files handed over by the system picker are security-scoped.
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let publication = try await ReadiumStack.open(at: sourceURL)
        let fileData = try Data(contentsOf: sourceURL)

        // Content-derived identity (see PROJECT.md): prefer the EPUB's own
        // dc:identifier so the same book matches across devices; fall back to a
        // file hash. The on-disk filename is a hash of the id, so it's always
        // filesystem-safe regardless of what the identifier contains.
        let bookID = stableID(identifier: publication.metadata.identifier, fileData: fileData)
        let key = Self.hex(SHA256.hash(data: Data(bookID.utf8)))

        let bookRel = storage.bookRelativePath(key: key)
        let bookURL = storage.absoluteURL(for: bookRel)
        try? FileManager.default.removeItem(at: bookURL)        // re-import overwrites
        try fileData.write(to: bookURL, options: .atomic)

        var coverRel: String?
        let coverImage = (try? await publication.cover().get()) ?? nil
        if let coverImage, let png = coverImage.pngData() {
            let rel = storage.coverRelativePath(key: key)
            try? png.write(to: storage.absoluteURL(for: rel), options: .atomic)
            coverRel = rel
        }

        let title = publication.metadata.title ?? sourceURL.deletingPathExtension().lastPathComponent
        let author = publication.metadata.authors.first?.name

        let book = Book(id: bookID, title: title, author: author, coverPath: coverRel, filePath: bookRel)
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
