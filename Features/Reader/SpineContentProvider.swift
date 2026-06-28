import Foundation
import ReaderCore

/// Supplies the paragraph model for TTS. It opens its **own** publication off the
/// main actor (via the nonisolated Readium boundary) and returns `Sendable`
/// `[Paragraph]`, so it never touches the reader's main-isolated `Publication` and
/// stays `Sendable` itself. Opens happen at spine boundaries (infrequent).
struct SpineContentProvider: Sendable {
    let fileURL: URL

    func spineCount() async throws -> Int {
        try await ReadiumStack.spineCount(at: fileURL)
    }

    func paragraphs(spineIndex: Int) async throws -> [Paragraph] {
        try await ReadiumStack.paragraphs(at: fileURL, spineIndex: spineIndex)
    }
}
