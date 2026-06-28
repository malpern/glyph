import Testing
import Foundation
@testable import ReaderCore

/// An in-memory stand-in for the remote transport, shared between two "devices"
/// (two stores). Applies the same last-writer-wins guard a real backend should.
private actor FakeRemote: RemoteSyncClient {
    private var states: [String: [String: ReadingState]] = [:]   // userID -> bookID -> state

    func push(_ incoming: [ReadingState], userID: String) async throws {
        var bucket = states[userID] ?? [:]
        for state in incoming {
            if let existing = bucket[state.bookID], existing.updatedAt >= state.updatedAt { continue }
            bucket[state.bookID] = state
        }
        states[userID] = bucket
    }

    func fetchAll(userID: String) async throws -> [ReadingState] {
        Array((states[userID] ?? [:]).values)
    }

    nonisolated func observe(userID: String) -> AsyncThrowingStream<[ReadingState], Error> {
        AsyncThrowingStream { $0.finish() }   // live path is covered by integration, not here
    }
}

@Suite(.serialized) struct SyncEngineTests {

    @Test func positionSyncsAcrossTwoDevices() async throws {
        let remote = FakeRemote()
        let user = "u1"
        let deviceA = try ReaderStore.make(inMemory: true)
        let deviceB = try ReaderStore.make(inMemory: true)
        let engineA = ReadingStateSyncEngine(store: deviceA, remote: remote)
        let engineB = ReadingStateSyncEngine(store: deviceB, remote: remote)
        await engineA.start(userID: user)
        await engineB.start(userID: user)

        // A reads → dirty locally → pushes.
        let locator = Data("chapter-6".utf8)
        try await deviceA.updateLocator(bookID: "book-1", locator: locator)
        await engineA.pushDirty()

        // B reconciles → resumes at A's position.
        await engineB.reconcile()
        let onB = try await deviceB.readingState(bookID: "book-1")
        #expect(onB?.locator == locator)
    }

    @Test func newerLocalSurvivesPullAndWins() async throws {
        let remote = FakeRemote()
        let user = "u1"
        // Remote already holds an OLD position.
        let old = ReadingState(bookID: "b", locator: Data("old".utf8),
                               updatedAt: Date(timeIntervalSince1970: 1_000), pendingSync: false)
        try await remote.push([old], userID: user)

        // This device has a NEWER local position.
        let device = try ReaderStore.make(inMemory: true)
        try await device.updateLocator(bookID: "b", locator: Data("new".utf8))   // updatedAt = now

        let engine = ReadingStateSyncEngine(store: device, remote: remote)
        await engine.start(userID: user)   // reconcile: ignores old remote, pushes new

        #expect(decode(try await device.readingState(bookID: "b")?.locator) == "new")
        #expect(decode(try await remote.fetchAll(userID: user).first?.locator) == "new")
    }

    @Test func olderRemoteDoesNotClobberLocal() async throws {
        let device = try ReaderStore.make(inMemory: true)
        try await device.updateLocator(bookID: "b", locator: Data("local-new".utf8))

        let older = ReadingState(bookID: "b", locator: Data("remote-old".utf8),
                                 updatedAt: Date(timeIntervalSince1970: 1), pendingSync: false)
        let applied = try await device.applyRemote(older)

        #expect(applied == false)
        #expect(decode(try await device.readingState(bookID: "b")?.locator) == "local-new")
    }

    @Test func newerRemoteAppliedAndLeavesRowClean() async throws {
        let device = try ReaderStore.make(inMemory: true)
        try await device.updateLocator(bookID: "b", locator: Data("local".utf8))   // dirty

        let newer = ReadingState(bookID: "b", locator: Data("remote-newer".utf8),
                                 updatedAt: Date(timeIntervalSinceNow: 60), pendingSync: false)
        let applied = try await device.applyRemote(newer)

        #expect(applied)
        #expect(decode(try await device.readingState(bookID: "b")?.locator) == "remote-newer")
        #expect(try await device.dirtyReadingStates().isEmpty)   // applying remote clears dirty
    }

    // MARK: - Conflict / convergence edge cases

    /// LWW is *strictly* newer: a remote write at the exact same instant must lose,
    /// otherwise two devices saving in the same tick could ping-pong forever.
    @Test func applyRemoteIgnoresEqualTimestamp() async throws {
        let device = try ReaderStore.make(inMemory: true)
        try await device.updateLocator(bookID: "b", locator: Data("local".utf8))
        let stamp = try #require(try await device.readingState(bookID: "b")?.updatedAt)

        let tie = ReadingState(bookID: "b", locator: Data("remote-tie".utf8),
                               updatedAt: stamp, pendingSync: false)
        let applied = try await device.applyRemote(tie)

        #expect(applied == false)
        #expect(decode(try await device.readingState(bookID: "b")?.locator) == "local")
    }

    /// The data-loss case the `ifUpdatedAt` guard exists to prevent: a local edit
    /// lands *after* a push captured the old position but *before* its clear-dirty.
    /// The newer edit must survive AND stay dirty so the next push ships it.
    @Test func editDuringPushIsNotLostByClearDirty() async throws {
        let device = try ReaderStore.make(inMemory: true)

        try await device.updateLocator(bookID: "b", locator: Data("v1".utf8))
        let t1 = try #require(try await device.readingState(bookID: "b")?.updatedAt)

        // User moves again while v1's push is in flight.
        try await device.updateLocator(bookID: "b", locator: Data("v2".utf8))

        // v1's push completes and tries to clear dirty against the stale stamp.
        try await device.clearDirty(bookID: "b", ifUpdatedAt: t1)

        #expect(decode(try await device.readingState(bookID: "b")?.locator) == "v2")
        #expect(try await device.dirtyReadingStates().isEmpty == false)   // v2 still queued
    }

    /// End-to-end through the engine: a local save propagates to the remote and the
    /// row goes clean.
    @Test func pushDirtyPropagatesThenClears() async throws {
        let remote = FakeRemote()
        let device = try ReaderStore.make(inMemory: true)
        let engine = ReadingStateSyncEngine(store: device, remote: remote)
        await engine.start(userID: "u1")

        try await device.updateLocator(bookID: "b", locator: Data("p".utf8))
        await engine.pushDirty()

        #expect(try await device.dirtyReadingStates().isEmpty)
        #expect(decode(try await remote.fetchAll(userID: "u1").first?.locator) == "p")
    }

    /// One reconcile both pulls a newer remote row (book A) and pushes a dirty local
    /// row (book B) — proving pull-before-push converges multiple books in a pass.
    @Test func reconcilePullsNewerAndPushesDirtyInOnePass() async throws {
        let remote = FakeRemote()
        let user = "u1"
        try await remote.push([ReadingState(bookID: "A", locator: Data("A-remote".utf8),
                                            updatedAt: Date(timeIntervalSinceNow: 60))], userID: user)
        let device = try ReaderStore.make(inMemory: true)
        try await device.updateLocator(bookID: "B", locator: Data("B-local".utf8))

        let engine = ReadingStateSyncEngine(store: device, remote: remote)
        await engine.start(userID: user)   // reconcile pulls A, pushes B

        #expect(decode(try await device.readingState(bookID: "A")?.locator) == "A-remote")
        let remoteB = try await remote.fetchAll(userID: user).first { $0.bookID == "B" }
        #expect(decode(remoteB?.locator) == "B-local")
        #expect(try await device.dirtyReadingStates().isEmpty)
    }

    /// Reconciling a clean store pushes nothing — guards the empty-dirty no-op path.
    @Test func pushDirtyIsNoOpWhenClean() async throws {
        let remote = FakeRemote()
        let device = try ReaderStore.make(inMemory: true)
        let engine = ReadingStateSyncEngine(store: device, remote: remote)
        await engine.start(userID: "u1")

        #expect(try await remote.fetchAll(userID: "u1").isEmpty)
    }

    /// Reconciling twice with no new edits is a fixpoint: nothing flips dirty and the
    /// position is unchanged (no self-inflicted churn from echoing our own push back).
    @Test func reconcileIsIdempotent() async throws {
        let remote = FakeRemote()
        let user = "u1"
        let device = try ReaderStore.make(inMemory: true)
        let engine = ReadingStateSyncEngine(store: device, remote: remote)
        await engine.start(userID: user)

        try await device.updateLocator(bookID: "b", locator: Data("x".utf8))
        await engine.reconcile()
        let after1 = try await device.readingState(bookID: "b")?.updatedAt
        await engine.reconcile()
        let after2 = try await device.readingState(bookID: "b")?.updatedAt

        #expect(after1 == after2)
        #expect(try await device.dirtyReadingStates().isEmpty)
    }

    private func decode(_ data: Data?) -> String? {
        data.flatMap { String(data: $0, encoding: .utf8) }
    }
}
