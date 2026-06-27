import Foundation

/// The reading position for one book, plus its bookmarks and highlights.
///
/// This is **the unit a future sync engine will replicate.** Everything needed to
/// resume on another device is here: the serialized Readium `Locator`, an
/// `updatedAt` for last-writer-wins conflict resolution, and a `pendingSync` flag
/// the outbox will use. Phase 1 keeps it purely local.
public struct ReadingState: Codable, Sendable, Equatable {
    public let bookID: String
    /// Serialized Readium `Locator` JSON — the exact resume point. `nil` until the
    /// book has been opened at least once. Never a page number.
    public var locator: Data?
    public var updatedAt: Date
    public var bookmarks: [Bookmark]
    public var highlights: [Highlight]
    /// Dirty flag for the future sync outbox; always set when the state mutates.
    public var pendingSync: Bool

    public init(
        bookID: String,
        locator: Data? = nil,
        updatedAt: Date = Date(),
        bookmarks: [Bookmark] = [],
        highlights: [Highlight] = [],
        pendingSync: Bool = false
    ) {
        self.bookID = bookID
        self.locator = locator
        self.updatedAt = updatedAt
        self.bookmarks = bookmarks
        self.highlights = highlights
        self.pendingSync = pendingSync
    }
}
