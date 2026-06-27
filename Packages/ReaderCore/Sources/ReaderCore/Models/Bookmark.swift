import Foundation

/// A user bookmark anchored to a Readium `Locator` (stored serialized as `Data`).
/// Its own syncable record with `id` + tombstone, so sync resolves bookmarks
/// independently of the book and of each other.
public struct Bookmark: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let bookID: String
    /// Serialized Readium `Locator` JSON. ReaderCore stays Readium-free, so the
    /// position is opaque bytes here; the reader layer encodes/decodes it.
    public var locator: Data
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        bookID: String,
        locator: Data,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.locator = locator
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
