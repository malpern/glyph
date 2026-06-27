import Foundation
import SwiftData

// SwiftData entities. These never leave the persistence layer — `SwiftDataStore`
// maps them to/from the Sendable domain structs, so the `@Model` reference types
// never cross an actor boundary. Records are kept flat (keyed by `bookID`) rather
// than wired with relationships, which keeps `@ModelActor` access simple.

@Model
final class BookEntity {
    @Attribute(.unique) var id: String
    var title: String
    var author: String?
    var coverPath: String?
    var filePath: String
    var addedAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: String,
        title: String,
        author: String?,
        coverPath: String?,
        filePath: String,
        addedAt: Date,
        updatedAt: Date,
        deletedAt: Date?
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

@Model
final class ReadingStateEntity {
    @Attribute(.unique) var bookID: String
    var locator: Data?
    var updatedAt: Date
    var pendingSync: Bool

    init(bookID: String, locator: Data?, updatedAt: Date, pendingSync: Bool) {
        self.bookID = bookID
        self.locator = locator
        self.updatedAt = updatedAt
        self.pendingSync = pendingSync
    }
}

@Model
final class BookmarkEntity {
    @Attribute(.unique) var id: UUID
    var bookID: String
    var locator: Data
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: UUID, bookID: String, locator: Data, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id
        self.bookID = bookID
        self.locator = locator
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

@Model
final class HighlightEntity {
    @Attribute(.unique) var id: UUID
    var bookID: String
    var locator: Data
    var text: String?
    var color: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(id: UUID, bookID: String, locator: Data, text: String?, color: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
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
