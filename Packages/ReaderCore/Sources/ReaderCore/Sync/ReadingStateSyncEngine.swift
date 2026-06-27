import Foundation

/// Orchestrates reading-position sync between the local store and the remote
/// transport. Pure logic over two protocols — no Firebase, no SwiftData — so it
/// runs identically on every client and is fully unit-testable with fakes.
///
/// Convergence model (last-writer-wins on `updatedAt`):
/// - **Pull** applies each remote state via `applyRemote`, which keeps it only if
///   it's newer than local.
/// - **Push** sends locally-dirty rows; the remote applies its own LWW guard.
/// - **Reconcile** pulls *before* pushing, so a stale local row can't clobber a
///   newer remote one, and a genuinely-newer local row survives the pull and gets
///   pushed.
public actor ReadingStateSyncEngine {
    private let store: any ReadingStateSyncStore
    private let remote: any RemoteSyncClient
    private var userID: String?
    private var observeTask: Task<Void, Never>?

    public init(store: any ReadingStateSyncStore, remote: any RemoteSyncClient) {
        self.store = store
        self.remote = remote
    }

    /// Begin syncing for a user: reconcile once, then observe live changes.
    public func start(userID: String) async {
        self.userID = userID
        await reconcile()
        startObserving(userID: userID)
    }

    public func stop() {
        observeTask?.cancel()
        observeTask = nil
        userID = nil
    }

    /// Pull everything once (LWW), then push anything still dirty. Safe to call on
    /// every app foreground.
    public func reconcile() async {
        guard let userID else { return }
        if let remoteStates = try? await remote.fetchAll(userID: userID) {
            for state in remoteStates {
                _ = try? await store.applyRemote(state)
            }
        }
        await pushDirty()
    }

    /// Push locally-dirty states now — called after a local position save for
    /// snappy propagation. Best-effort: failures are retried on the next trigger.
    public func pushDirty() async {
        guard let userID else { return }
        guard let dirty = try? await store.dirtyReadingStates(), !dirty.isEmpty else { return }
        guard (try? await remote.push(dirty, userID: userID)) != nil else { return }
        for state in dirty {
            try? await store.clearDirty(bookID: state.bookID, ifUpdatedAt: state.updatedAt)
        }
    }

    // MARK: -

    private func startObserving(userID: String) {
        observeTask?.cancel()
        let store = store
        let remote = remote
        observeTask = Task {
            do {
                for try await batch in remote.observe(userID: userID) {
                    for state in batch {
                        _ = try? await store.applyRemote(state)
                    }
                }
            } catch {
                // Listener dropped; a future foreground reconcile will catch up.
            }
        }
    }
}
