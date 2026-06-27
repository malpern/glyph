import Foundation

/// The library's persistence boundary. Features depend on this protocol, never on
/// SwiftData. Swapping the storage engine — or adding a sync-aware implementation
/// later — means providing a new conformer, with no change to the features.
///
/// `Sendable` so it can be held by `@MainActor` view models and called across the
/// actor boundary into the store.
public protocol LibraryRepository: Sendable {
    /// All live (non-tombstoned) books, newest first.
    func allBooks() async throws -> [Book]
    func book(id: String) async throws -> Book?
    /// Insert or update by `id`. Bumps `updatedAt` and marks the record dirty.
    func upsert(_ book: Book) async throws
    /// Soft delete: sets a `deletedAt` tombstone rather than removing the row, so
    /// the deletion can later propagate through sync.
    func delete(id: String) async throws
}
