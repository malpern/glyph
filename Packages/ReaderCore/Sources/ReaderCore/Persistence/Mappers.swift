import Foundation

// Entity <-> domain mapping. One-directional dependency: persistence knows about
// the domain models, not the other way round.

extension BookEntity {
    func toDomain() -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            coverPath: coverPath,
            filePath: filePath,
            addedAt: addedAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    /// Copy the mutable fields of a domain `Book` onto this entity (used on update).
    func apply(_ book: Book) {
        title = book.title
        author = book.author
        coverPath = book.coverPath
        filePath = book.filePath
        addedAt = book.addedAt
        updatedAt = book.updatedAt
        deletedAt = book.deletedAt
    }

    static func make(from book: Book) -> BookEntity {
        BookEntity(
            id: book.id,
            title: book.title,
            author: book.author,
            coverPath: book.coverPath,
            filePath: book.filePath,
            addedAt: book.addedAt,
            updatedAt: book.updatedAt,
            deletedAt: book.deletedAt
        )
    }
}

extension BookmarkEntity {
    func toDomain() -> Bookmark {
        Bookmark(id: id, bookID: bookID, locator: locator, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    static func make(from b: Bookmark) -> BookmarkEntity {
        BookmarkEntity(id: b.id, bookID: b.bookID, locator: b.locator, createdAt: b.createdAt, updatedAt: b.updatedAt, deletedAt: b.deletedAt)
    }
}

extension HighlightEntity {
    func toDomain() -> Highlight {
        Highlight(id: id, bookID: bookID, locator: locator, text: text, color: color, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    static func make(from h: Highlight) -> HighlightEntity {
        HighlightEntity(id: h.id, bookID: h.bookID, locator: h.locator, text: h.text, color: h.color, createdAt: h.createdAt, updatedAt: h.updatedAt, deletedAt: h.deletedAt)
    }
}
