import Foundation

/// A library entry. Pure value type — the canonical, storage-agnostic
/// representation features depend on. The SwiftData entity in Persistence/ maps
/// to and from this; nothing outside Persistence/ ever sees the `@Model` class.
///
/// `id` is **content-derived** (EPUB `dc:identifier`, or a file hash fallback) so
/// the same book imported on two devices resolves to the same identity — the
/// precondition for cross-device resume. It is never a per-import random UUID.
public struct Book: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var author: String?
    /// Path relative to the app's books container (see `BookStorage`), not absolute,
    /// so it survives container-path changes between launches and devices.
    public var coverPath: String?
    public var filePath: String
    public var addedAt: Date
    // --- sync envelope (unused in Phase 1, present so no migration is needed later) ---
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: String,
        title: String,
        author: String? = nil,
        coverPath: String? = nil,
        filePath: String,
        addedAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverPath = coverPath
        self.filePath = filePath
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
