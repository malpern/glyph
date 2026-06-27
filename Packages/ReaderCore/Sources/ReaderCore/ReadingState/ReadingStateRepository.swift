import Foundation

/// Persistence boundary for reading position, bookmarks, and highlights.
/// Split from `LibraryRepository` because reading state mutates on a different
/// cadence (frequently, while reading) and will sync on its own channel.
public protocol ReadingStateRepository: Sendable {
    /// The stored state for a book, or `nil` if it has never been opened.
    func readingState(bookID: String) async throws -> ReadingState?
    /// Persist the whole state (creating the row if needed). Marks it dirty.
    func save(_ state: ReadingState) async throws
    /// Fast path for the common case: update just the resume locator. Creates the
    /// state row if the book has not been opened before.
    func updateLocator(bookID: String, locator: Data) async throws
}
