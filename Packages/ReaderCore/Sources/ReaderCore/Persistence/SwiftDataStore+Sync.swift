import Foundation
import SwiftData

/// `SwiftDataStore`'s sync-facing operations. These deliberately bypass the
/// "stamp updatedAt / mark dirty" behavior of the UI-facing writes: applying a
/// remote change writes the remote `updatedAt` verbatim and leaves the row clean,
/// so reconciliation converges instead of looping.
///
/// Phase 2a syncs reading position only, so the `ReadingState`s produced here
/// carry empty `bookmarks`/`highlights`; those join the sync later.
extension SwiftDataStore: ReadingStateSyncStore {

    public func dirtyReadingStates() throws -> [ReadingState] {
        let descriptor = FetchDescriptor<ReadingStateEntity>(
            predicate: #Predicate { $0.pendingSync == true }
        )
        return try modelContext.fetch(descriptor).map {
            ReadingState(
                bookID: $0.bookID,
                locator: $0.locator,
                updatedAt: $0.updatedAt,
                bookmarks: [],
                highlights: [],
                pendingSync: true
            )
        }
    }

    @discardableResult
    public func applyRemote(_ state: ReadingState) throws -> Bool {
        let bookID = state.bookID
        var descriptor = FetchDescriptor<ReadingStateEntity>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            guard state.updatedAt > existing.updatedAt else { return false }   // LWW
            existing.locator = state.locator
            existing.updatedAt = state.updatedAt                              // verbatim
            existing.pendingSync = false
        } else {
            modelContext.insert(ReadingStateEntity(
                bookID: state.bookID,
                locator: state.locator,
                updatedAt: state.updatedAt,
                pendingSync: false
            ))
        }
        try modelContext.save()
        return true
    }

    public func clearDirty(bookID: String, ifUpdatedAt updatedAt: Date) throws {
        var descriptor = FetchDescriptor<ReadingStateEntity>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first,
              entity.pendingSync,
              entity.updatedAt == updatedAt   // unchanged since the push
        else { return }
        entity.pendingSync = false
        try modelContext.save()
    }

    // MARK: Bookmarks (CollectionSyncEngine store — dirty incl. tombstones)

    public func dirtyBookmarks() throws -> [Bookmark] {
        try modelContext.fetch(FetchDescriptor<BookmarkEntity>(
            predicate: #Predicate { $0.pendingSync == true }
        )).map { $0.toDomain() }
    }

    @discardableResult
    public func applyRemoteBookmark(_ bookmark: Bookmark) throws -> Bool {
        let id = bookmark.id
        var descriptor = FetchDescriptor<BookmarkEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            guard bookmark.updatedAt > existing.updatedAt else { return false }   // LWW
            existing.locator = bookmark.locator
            existing.createdAt = bookmark.createdAt
            existing.updatedAt = bookmark.updatedAt      // verbatim
            existing.deletedAt = bookmark.deletedAt      // tombstones sync too
            existing.pendingSync = false
        } else {
            modelContext.insert(BookmarkEntity.make(from: bookmark, pendingSync: false))
        }
        try modelContext.save()
        return true
    }

    public func clearBookmarkDirty(id: UUID, ifUpdatedAt updatedAt: Date) throws {
        var descriptor = FetchDescriptor<BookmarkEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first,
              entity.pendingSync, entity.updatedAt == updatedAt else { return }
        entity.pendingSync = false
        try modelContext.save()
    }

    // MARK: Highlights

    public func dirtyHighlights() throws -> [Highlight] {
        try modelContext.fetch(FetchDescriptor<HighlightEntity>(
            predicate: #Predicate { $0.pendingSync == true }
        )).map { $0.toDomain() }
    }

    @discardableResult
    public func applyRemoteHighlight(_ highlight: Highlight) throws -> Bool {
        let id = highlight.id
        var descriptor = FetchDescriptor<HighlightEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            guard highlight.updatedAt > existing.updatedAt else { return false }   // LWW
            existing.locator = highlight.locator
            existing.text = highlight.text
            existing.color = highlight.color
            existing.createdAt = highlight.createdAt
            existing.updatedAt = highlight.updatedAt
            existing.deletedAt = highlight.deletedAt
            existing.pendingSync = false
        } else {
            modelContext.insert(HighlightEntity.make(from: highlight, pendingSync: false))
        }
        try modelContext.save()
        return true
    }

    public func clearHighlightDirty(id: UUID, ifUpdatedAt updatedAt: Date) throws {
        var descriptor = FetchDescriptor<HighlightEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first,
              entity.pendingSync, entity.updatedAt == updatedAt else { return }
        entity.pendingSync = false
        try modelContext.save()
    }
}
