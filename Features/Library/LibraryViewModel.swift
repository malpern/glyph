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
