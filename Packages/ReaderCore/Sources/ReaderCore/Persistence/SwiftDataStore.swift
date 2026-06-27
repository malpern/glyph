import Foundation
import SwiftData

/// The single SwiftData-backed implementation of both repository protocols.
///
/// `@ModelActor` makes this an actor whose `modelContext` is confined to its
/// executor, so all database access is serialized and the non-`Sendable` `@Model`
/// entities never escape — every method returns Sendable domain structs. This is
/// the *only* type in the app that knows SwiftData exists.
///
/// The store stamps `updatedAt` at write time (the persistence layer owns the
/// write clock) and sets `pendingSync` on reading-state writes, so the future sync
/// outbox has accurate timestamps and dirty flags without the caller's help.
@ModelActor
public actor SwiftDataStore: LibraryRepository, ReadingStateRepository {

    // MARK: LibraryRepository

    public func allBooks() throws -> [Book] {
        let descriptor = FetchDescriptor<BookEntity>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    public func book(id: String) throws -> Book? {
        guard let entity = try bookEntity(id: id), entity.deletedAt == nil else { return nil }
        return entity.toDomain()
    }

    public func upsert(_ book: Book) throws {
        if let entity = try bookEntity(id: book.id) {
            entity.apply(book)
            entity.updatedAt = Date()
        } else {
            let entity = BookEntity.make(from: book)
            entity.updatedAt = Date()
            modelContext.insert(entity)
        }
        try modelContext.save()
    }

    public func delete(id: String) throws {
        guard let entity = try bookEntity(id: id) else { return }
        entity.deletedAt = Date()      // tombstone, not a row removal
        entity.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: ReadingStateRepository

    public func readingState(bookID: String) throws -> ReadingState? {
        guard let state = try stateEntity(bookID: bookID) else { return nil }
        return ReadingState(
            bookID: state.bookID,
            locator: state.locator,
            updatedAt: state.updatedAt,
            bookmarks: try liveBookmarks(bookID: bookID).map { $0.toDomain() },
            highlights: try liveHighlights(bookID: bookID).map { $0.toDomain() },
            pendingSync: state.pendingSync
        )
    }

    public func save(_ state: ReadingState) throws {
        let entity = try stateEntity(bookID: state.bookID) ?? insertState(bookID: state.bookID)
        entity.locator = state.locator
        entity.updatedAt = Date()
        entity.pendingSync = true
        try upsertChildren(state)
        try modelContext.save()
    }

    public func updateLocator(bookID: String, locator: Data) throws {
        let entity = try stateEntity(bookID: bookID) ?? insertState(bookID: bookID)
        entity.locator = locator
        entity.updatedAt = Date()
        entity.pendingSync = true
        try modelContext.save()
    }

    // MARK: - Fetch helpers

    private func bookEntity(id: String) throws -> BookEntity? {
        var descriptor = FetchDescriptor<BookEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func stateEntity(bookID: String) throws -> ReadingStateEntity? {
        var descriptor = FetchDescriptor<ReadingStateEntity>(predicate: #Predicate { $0.bookID == bookID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func insertState(bookID: String) -> ReadingStateEntity {
        let entity = ReadingStateEntity(bookID: bookID, locator: nil, updatedAt: Date(), pendingSync: false)
        modelContext.insert(entity)
        return entity
    }

    private func liveBookmarks(bookID: String) throws -> [BookmarkEntity] {
        try modelContext.fetch(FetchDescriptor<BookmarkEntity>(
            predicate: #Predicate { $0.bookID == bookID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    private func liveHighlights(bookID: String) throws -> [HighlightEntity] {
        try modelContext.fetch(FetchDescriptor<HighlightEntity>(
            predicate: #Predicate { $0.bookID == bookID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    /// Upsert the bookmarks/highlights carried by a `ReadingState` by their stable
    /// id. Records absent from the state are left untouched — deletion is explicit
    /// via a tombstone, never inferred from absence.
    private func upsertChildren(_ state: ReadingState) throws {
        for bookmark in state.bookmarks {
            let id = bookmark.id
            var d = FetchDescriptor<BookmarkEntity>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if let existing = try modelContext.fetch(d).first {
                existing.locator = bookmark.locator
                existing.updatedAt = bookmark.updatedAt
                existing.deletedAt = bookmark.deletedAt
            } else {
                modelContext.insert(BookmarkEntity.make(from: bookmark))
            }
        }
        for highlight in state.highlights {
            let id = highlight.id
            var d = FetchDescriptor<HighlightEntity>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if let existing = try modelContext.fetch(d).first {
                existing.locator = highlight.locator
                existing.text = highlight.text
                existing.color = highlight.color
                existing.updatedAt = highlight.updatedAt
                existing.deletedAt = highlight.deletedAt
            } else {
                modelContext.insert(HighlightEntity.make(from: highlight))
            }
        }
    }
}
