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

    private func decode(_ data: Data?) -> String? {
        data.flatMap { String(data: $0, encoding: .utf8) }
    }
}
