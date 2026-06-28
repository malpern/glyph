import Foundation
import Observation
import ReaderCore

/// Drives the library screen. Talks only to the `LibraryRepository` protocol and
/// the importer — no SwiftData, no Readium types leak in here.
@MainActor
@Observable
final class LibraryViewModel {
    private let library: any LibraryRepository
    private let importer: BookImporter

    private(set) var books: [Book] = []
    var isImporting = false
    var errorMessage: String?

    init(library: any LibraryRepository, importer: BookImporter) {
        self.library = library
        self.importer = importer
    }

    func load() async {
        do {
            books = try await library.allBooks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importBook(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await importer.importBook(from: url)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Auto-import any `.epub` files dropped into the app's Documents folder (via
    /// AirDrop, the Files app, "Open in Glyph", or a direct device copy), then
    /// remove the source so it's a one-shot ingest. Runs on each library appearance.
    func ingestInbox() async {
        let fileManager = FileManager.default
        guard let documents = try? fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        let epubs = ((try? fileManager.contentsOfDirectory(
            at: documents, includingPropertiesForKeys: nil
        )) ?? []).filter { $0.pathExtension.lowercased() == "epub" }
        guard !epubs.isEmpty else { return }

        isImporting = true
        defer { isImporting = false }
        for url in epubs {
            do {
                try await importer.importBook(from: url)
                try? fileManager.removeItem(at: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await load()
    }

    /// Imports the bundled first-run sample so a fresh install has something to read.
    func importSample() async {
        guard let url = Bundle.main.url(forResource: "Sample", withExtension: "epub") else {
            errorMessage = "Sample book is missing from the bundle."
            return
        }
        await importBook(from: url)
    }

    func delete(_ book: Book) async {
        do {
            try await library.delete(id: book.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
