import Foundation

/// A user highlight over a text range, anchored to a Readium `Locator` whose
/// `text` and `locations` capture the selection. Phase 1 stores but does not yet
/// create these; the model exists so the schema and sync envelope are stable.
public struct Highlight: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let bookID: String
    /// Serialized Readium `Locator` JSON (opaque to ReaderCore).
    public var locator: Data
    /// The highlighted text, denormalized for display without re-resolving the locator.
    public var text: String?
    /// A color token (e.g. "yellow"); kept as a string for forward-compatible sync.
    public var color: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        bookID: String,
        locator: Data,
        text: String? = nil,
        color: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.locator = locator
        self.text = text
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
