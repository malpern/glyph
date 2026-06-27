import Foundation

/// Supplies the identity that scopes a user's synced data. The real
/// implementation lives in the App layer (Firebase Auth); `ReaderCore` only needs
/// a stream of "who is signed in" so the sync engine knows when to start/stop and
/// which account to sync.
public protocol AuthProviding: Sendable {
    /// Emits the signed-in user id (or `nil` when signed out), starting with the
    /// current value on subscription and then on every auth-state change.
    func userIDs() -> AsyncStream<String?>
}

/// A fixed-identity stand-in used to build and prove the sync engine before real
/// auth exists. Every device configured with the same id syncs to one account —
/// exactly what the two-simulator test needs.
public struct StubAuth: AuthProviding {
    public let userID: String

    public init(userID: String = "dev-shared-user") {
        self.userID = userID
    }

    public func userIDs() -> AsyncStream<String?> {
        let id = userID
        return AsyncStream { continuation in
            continuation.yield(id)
            // Stays open (never finishes) so the engine treats this as a stable
            // signed-in session rather than a sign-out.
            continuation.onTermination = { _ in }
        }
    }
}
