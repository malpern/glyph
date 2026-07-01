import Testing
import Foundation
@testable import ReaderCore

/// In-memory local store for a syncable collection: records by id, plus a dirty set.
/// `applyRemote` enforces strict-LWW and clears dirty (verbatim apply isn't a new edit).
private actor MemStore<R: SyncableRecord> {
    private var records: [UUID: R] = [:]
    private var dirtyIDs: Set<UUID> = []

    func editLocal(_ r: R) { records[r.id] = r; dirtyIDs.insert(r.id) }   // a local change → dirty
    func get(_ id: UUID) -> R? { records[id] }

    func dirty() -> [R] { dirtyIDs.compactMap { records[$0] } }

    func applyRemote(_ r: R) -> Bool {
        if let existing = records[r.id], existing.updatedAt >= r.updatedAt { return false }
        records[r.id] = r
        dirtyIDs.remove(r.id)
        return true
    }

    func clearDirty(_ id: UUID, ifUpdatedAt stamp: Date) {
        guard let current = records[id], current.updatedAt == stamp else { return }   // edited since push
        dirtyIDs.remove(id)
    }
}

/// In-memory remote shared between two "devices", applying the same LWW guard a real
/// backend should.
private actor MemRemote<R: SyncableRecord> {
    private var buckets: [String: [UUID: R]] = [:]

    func push(_ incoming: [R], _ user: String) {
        var bucket = buckets[user] ?? [:]
        for r in incoming {
            if let existing = bucket[r.id], existing.updatedAt >= r.updatedAt { continue }
            bucket[r.id] = r
        }
        buckets[user] = bucket
    }

    func fetchAll(_ user: String) -> [R] { Array((buckets[user] ?? [:]).values) }
}

private func makeEngine<R: SyncableRecord>(
    store: MemStore<R>, remote: MemRemote<R>
) -> CollectionSyncEngine<R> {
    CollectionSyncEngine(
        store: .init(
            dirty: { await store.dirty() },
            applyRemote: { await store.applyRemote($0) },
            clearDirty: { await store.clearDirty($0, ifUpdatedAt: $1) }
        ),
        transport: .init(
            push: { await remote.push($0, $1) },
            fetchAll: { await remote.fetchAll($0) },
            observe: { _ in AsyncThrowingStream { $0.finish() } }   // live path is integration-tested
        )
    )
}

@Suite(.serialized) struct CollectionSyncEngineTests {

    @Test func bookmarkSyncsAcrossTwoDevices() async throws {
        let remote = MemRemote<Bookmark>()
        let a = MemStore<Bookmark>(), b = MemStore<Bookmark>()
        let engineA = makeEngine(store: a, remote: remote)
        let engineB = makeEngine(store: b, remote: remote)
        await engineA.start(userID: "u")
        await engineB.start(userID: "u")

        let bm = Bookmark(bookID: "book-1", locator: Data("ch3".utf8))
        await a.editLocal(bm)
        await engineA.pushDirty()

        await engineB.reconcile()
        #expect(await b.get(bm.id)?.locator == Data("ch3".utf8))
        #expect(await a.dirty().isEmpty)   // push cleared A's dirty
    }

    @Test func deletePropagatesAsTombstone() async throws {
        let remote = MemRemote<Bookmark>()
        let a = MemStore<Bookmark>(), b = MemStore<Bookmark>()
        let engineA = makeEngine(store: a, remote: remote)
        let engineB = makeEngine(store: b, remote: remote)
        await engineA.start(userID: "u"); await engineB.start(userID: "u")

        let bm = Bookmark(bookID: "book-1", locator: Data("x".utf8))
        await a.editLocal(bm); await engineA.pushDirty(); await engineB.reconcile()

        // A deletes it → tombstone with a newer updatedAt.
        let tomb = Bookmark(id: bm.id, bookID: "book-1", locator: bm.locator,
                            createdAt: bm.createdAt,
                            updatedAt: Date(timeIntervalSinceNow: 10), deletedAt: Date())
        await a.editLocal(tomb); await engineA.pushDirty(); await engineB.reconcile()

        #expect(await b.get(bm.id)?.deletedAt != nil)   // deletion reached B
    }

    @Test func olderRemoteDoesNotClobberNewerLocal() async throws {
        let store = MemStore<Bookmark>()
        let id = UUID()
        let localNew = Bookmark(id: id, bookID: "b", locator: Data("new".utf8),
                                updatedAt: Date(timeIntervalSinceNow: 100))
        await store.editLocal(localNew)

        let older = Bookmark(id: id, bookID: "b", locator: Data("old".utf8),
                             updatedAt: Date(timeIntervalSince1970: 1))
        let applied = await store.applyRemote(older)

        #expect(applied == false)
        #expect(await store.get(id)?.locator == Data("new".utf8))
    }

    /// The same engine syncs highlights (colour + text) unchanged — proving the generic
    /// record path isn't bookmark-specific.
    @Test func highlightsSyncThroughSameEngine() async throws {
        let remote = MemRemote<Highlight>()
        let a = MemStore<Highlight>(), b = MemStore<Highlight>()
        let engineA = makeEngine(store: a, remote: remote)
        let engineB = makeEngine(store: b, remote: remote)
        await engineA.start(userID: "u"); await engineB.start(userID: "u")

        let hl = Highlight(bookID: "book-1", locator: Data("sel".utf8), text: "hello", color: "green")
        await a.editLocal(hl)
        await engineA.pushDirty()
        await engineB.reconcile()

        let onB = await b.get(hl.id)
        #expect(onB?.color == "green")
        #expect(onB?.text == "hello")
    }

    // MARK: - Over the real SwiftDataStore (persistence + engine integration)

    private func bookmarkEngine(store: SwiftDataStore, remote: MemRemote<Bookmark>) -> CollectionSyncEngine<Bookmark> {
        CollectionSyncEngine(
            store: .init(
                dirty: { try await store.dirtyBookmarks() },
                applyRemote: { try await store.applyRemoteBookmark($0) },
                clearDirty: { try await store.clearBookmarkDirty(id: $0, ifUpdatedAt: $1) }
            ),
            transport: .init(
                push: { await remote.push($0, $1) },
                fetchAll: { await remote.fetchAll($0) },
                observe: { _ in AsyncThrowingStream { $0.finish() } }
            )
        )
    }

    @Test func bookmarkAddAndDeleteSyncAcrossRealStores() async throws {
        let remote = MemRemote<Bookmark>()
        let deviceA = try ReaderStore.make(inMemory: true)
        let deviceB = try ReaderStore.make(inMemory: true)
        let engineA = bookmarkEngine(store: deviceA, remote: remote)
        let engineB = bookmarkEngine(store: deviceB, remote: remote)
        await engineA.start(userID: "u"); await engineB.start(userID: "u")

        // Add on A → dirty → push → B reconciles and sees it.
        let bm = Bookmark(bookID: "book-1", locator: Data("p3".utf8))
        try await deviceA.addBookmark(bm)
        await engineA.pushDirty()
        await engineB.reconcile()
        #expect(try await deviceB.bookmarks(bookID: "book-1").contains { $0.id == bm.id })
        #expect(try await deviceA.dirtyBookmarks().isEmpty)   // push cleared dirty

        // Delete on A → tombstone → propagates → gone on B.
        try await deviceA.deleteBookmark(id: bm.id)
        await engineA.pushDirty()
        await engineB.reconcile()
        #expect(try await deviceB.bookmarks(bookID: "book-1").isEmpty)
    }

    @Test func highlightAddAndRecolorSyncAcrossRealStores() async throws {
        let remote = MemRemote<Highlight>()
        let deviceA = try ReaderStore.make(inMemory: true)
        let deviceB = try ReaderStore.make(inMemory: true)
        func engine(_ store: SwiftDataStore) -> CollectionSyncEngine<Highlight> {
            CollectionSyncEngine(
                store: .init(
                    dirty: { try await store.dirtyHighlights() },
                    applyRemote: { try await store.applyRemoteHighlight($0) },
                    clearDirty: { try await store.clearHighlightDirty(id: $0, ifUpdatedAt: $1) }
                ),
                transport: .init(
                    push: { await remote.push($0, $1) },
                    fetchAll: { await remote.fetchAll($0) },
                    observe: { _ in AsyncThrowingStream { $0.finish() } }
                )
            )
        }
        let engineA = engine(deviceA), engineB = engine(deviceB)
        await engineA.start(userID: "u"); await engineB.start(userID: "u")

        let hl = Highlight(bookID: "book-1", locator: Data("sel".utf8), text: "hi", color: "yellow")
        try await deviceA.addHighlight(hl)
        await engineA.pushDirty(); await engineB.reconcile()
        #expect(try await deviceB.highlights(bookID: "book-1").first?.color == "yellow")

        // Recolor on A → newer updatedAt wins on B.
        try await deviceA.updateHighlight(Highlight(id: hl.id, bookID: "book-1", locator: hl.locator, text: "hi", color: "pink"))
        await engineA.pushDirty(); await engineB.reconcile()
        #expect(try await deviceB.highlights(bookID: "book-1").first?.color == "pink")
    }
}
