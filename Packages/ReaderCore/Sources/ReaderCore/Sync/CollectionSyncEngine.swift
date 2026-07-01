import Foundation

/// A per-record syncable envelope: a stable id and the LWW/tombstone timestamps.
/// `Bookmark` and `Highlight` already carry exactly this shape.
public protocol SyncableRecord: Sendable, Codable {
    var id: UUID { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

extension Bookmark: SyncableRecord {}
extension Highlight: SyncableRecord {}

/// Syncs a *collection* of independent records (bookmarks, highlights) between the
/// local store and a remote transport — the same convergence model as
/// `ReadingStateSyncEngine`, but for many-per-book records keyed by their own `id`:
///
/// - **Pull** applies each remote record via `applyRemote` (LWW: kept only if strictly
///   newer than local, or absent). Tombstones (`deletedAt`) propagate like any update.
/// - **Push** ships locally-dirty records; the remote applies its own LWW guard.
/// - **Reconcile** pulls *before* pushing, so a stale local record can't clobber a newer
///   remote one, and a genuinely-newer local record survives the pull and gets pushed.
///
/// Backed by closures rather than protocols so one generic engine serves both record
/// types without adapter types or double-conformance gymnastics; the App layer supplies
/// closures over `SwiftDataStore` + the Firestore client, tests supply in-memory fakes.
public actor CollectionSyncEngine<Record: SyncableRecord> {

    /// Local persistence, written *verbatim* on apply (preserves the remote `updatedAt`,
    /// never marks the record dirty) so a pulled change can't masquerade as a new edit.
    public struct LocalStore: Sendable {
        public var dirty: @Sendable () async throws -> [Record]
        public var applyRemote: @Sendable (Record) async throws -> Bool
        public var clearDirty: @Sendable (_ id: UUID, _ ifUpdatedAt: Date) async throws -> Void
        public init(
            dirty: @escaping @Sendable () async throws -> [Record],
            applyRemote: @escaping @Sendable (Record) async throws -> Bool,
            clearDirty: @escaping @Sendable (_ id: UUID, _ ifUpdatedAt: Date) async throws -> Void
        ) {
            self.dirty = dirty
            self.applyRemote = applyRemote
            self.clearDirty = clearDirty
        }
    }

    /// The remote transport, scoped to a `userID`.
    public struct Transport: Sendable {
        public var push: @Sendable (_ records: [Record], _ userID: String) async throws -> Void
        public var fetchAll: @Sendable (_ userID: String) async throws -> [Record]
        public var observe: @Sendable (_ userID: String) -> AsyncThrowingStream<[Record], Error>
        public init(
            push: @escaping @Sendable (_ records: [Record], _ userID: String) async throws -> Void,
            fetchAll: @escaping @Sendable (_ userID: String) async throws -> [Record],
            observe: @escaping @Sendable (_ userID: String) -> AsyncThrowingStream<[Record], Error>
        ) {
            self.push = push
            self.fetchAll = fetchAll
            self.observe = observe
        }
    }

    private let store: LocalStore
    private let transport: Transport
    private var userID: String?
    private var observeTask: Task<Void, Never>?

    public init(store: LocalStore, transport: Transport) {
        self.store = store
        self.transport = transport
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

    /// Pull everything once (LWW), then push anything still dirty. Safe on every foreground.
    public func reconcile() async {
        guard let userID else { return }
        if let remote = try? await transport.fetchAll(userID) {
            for record in remote {
                _ = try? await store.applyRemote(record)
            }
        }
        await pushDirty()
    }

    /// Push locally-dirty records now — called after a local annotation change for snappy
    /// propagation. Best-effort: failures are retried on the next trigger.
    public func pushDirty() async {
        guard let userID else { return }
        guard let dirty = try? await store.dirty(), !dirty.isEmpty else { return }
        guard (try? await transport.push(dirty, userID)) != nil else { return }
        for record in dirty {
            try? await store.clearDirty(record.id, record.updatedAt)
        }
    }

    private func startObserving(userID: String) {
        observeTask?.cancel()
        let store = store
        let transport = transport
        observeTask = Task {
            do {
                for try await batch in transport.observe(userID) {
                    for record in batch {
                        _ = try? await store.applyRemote(record)
                    }
                }
            } catch {
                // Listener dropped; a future foreground reconcile catches up.
            }
        }
    }
}
