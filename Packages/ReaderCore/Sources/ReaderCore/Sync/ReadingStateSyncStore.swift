import Foundation

/// Sync-facing persistence operations, kept separate from the UI-facing
/// `ReadingStateRepository`. Implemented by `SwiftDataStore`.
///
/// The defining property: these write **verbatim** — they preserve a remote
/// row's `updatedAt` and never set `pendingSync` — so applying a pulled change
/// can't masquerade as a new local edit and create a push/pull loop.
public protocol ReadingStateSyncStore: Sendable {
    /// Local states with unsynced changes (`pendingSync == true`).
    func dirtyReadingStates() async throws -> [ReadingState]

    /// Apply a remote state under last-writer-wins: write it verbatim only if it
    /// is strictly newer than the local row (or the row is absent). Never marks
    /// the row dirty. Returns whether it was applied.
    @discardableResult
    func applyRemote(_ state: ReadingState) async throws -> Bool

    /// Clear the dirty flag after a successful push — but only if the local row
    /// hasn't changed since (its `updatedAt` still matches), so an edit made
    /// during the push isn't silently dropped.
    func clearDirty(bookID: String, ifUpdatedAt updatedAt: Date) async throws
}
