import Foundation

/// The remote transport the sync engine pushes to and observes. Implemented in
/// the App layer by a Firestore-backed client; `ReaderCore` stays dependency-free
/// and unit-testable against a fake. All operations are scoped to a `userID`.
public protocol RemoteSyncClient: Sendable {
    /// Upsert reading states for the user. Implementations should apply their own
    /// last-writer-wins guard (don't overwrite a strictly-newer remote row), so a
    /// slow push can't clobber fresher data.
    func push(_ states: [ReadingState], userID: String) async throws

    /// One-shot fetch of all of the user's reading states (catch-up pull).
    func fetchAll(userID: String) async throws -> [ReadingState]

    /// Live stream of reading states as they change remotely — emits the current
    /// set on subscription, then deltas. Ends when the consumer cancels.
    func observe(userID: String) -> AsyncThrowingStream<[ReadingState], Error>
}
