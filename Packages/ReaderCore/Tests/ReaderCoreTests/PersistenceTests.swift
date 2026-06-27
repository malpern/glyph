import Testing
import Foundation
@testable import ReaderCore

/// Round-trip tests for the SwiftData-backed repositories, run against an
/// in-memory store. They pin the persistence contract the rest of the app relies
/// on: live/tombstone semantics, locator round-tripping, and child upserts.
// Serialized: each test builds its own ModelContainer, and running them in
// parallel can occasionally race inside SwiftData. They're fast, so serial is free.
@Suite(.serialized) struct PersistenceTests {

    private func makeStore() throws -> SwiftDataStore {
        try ReaderStore.make(inMemory: true)
    }

    private func sampleBook(_ id: String = "urn:isbn:9780000000001") -> Book {
        Book(id: id, title: "Moby-Dick", author: "Herman Melville", filePath: "books/\(id).epub")
    }

    @Test func upsertThenFetchByIdAndList() async throws {
        let store = try makeStore()
        try await store.upsert(sampleBook())

        let fetched = try await store.book(id: "urn:isbn:9780000000001")
        #expect(fetched?.title == "Moby-Dick")
        #expect(fetched?.author == "Herman Melville")

        let all = try await store.allBooks()
        #expect(all.count == 1)
    }

    @Test func upsertIsIdempotentOnId() async throws {
        let store = try makeStore()
        try await store.upsert(sampleBook())
        var edited = sampleBook()
        edited.title = "Moby-Dick; or, The Whale"
        try await store.upsert(edited)

        let all = try await store.allBooks()
        #expect(all.count == 1)                       // updated, not duplicated
        #expect(all.first?.title == "Moby-Dick; or, The Whale")
    }

    @Test func deleteIsSoftAndHidesFromLibrary() async throws {
        let store = try makeStore()
        try await store.upsert(sampleBook())
        try await store.delete(id: "urn:isbn:9780000000001")

        #expect(try await store.allBooks().isEmpty)   // hidden from the library
        #expect(try await store.book(id: "urn:isbn:9780000000001") == nil)
        // Re-importing the same book revives the same identity rather than dup-ing.
        try await store.upsert(sampleBook())
        #expect(try await store.allBooks().count == 1)
    }

    @Test func updateLocatorCreatesAndRoundTrips() async throws {
        let store = try makeStore()
        let bookID = "urn:isbn:9780000000001"
        #expect(try await store.readingState(bookID: bookID) == nil)

        let locator = Data("{\"href\":\"chapter2.xhtml\",\"locations\":{\"progression\":0.4}}".utf8)
        try await store.updateLocator(bookID: bookID, locator: locator)

        let state = try await store.readingState(bookID: bookID)
        #expect(state?.locator == locator)
        #expect(state?.pendingSync == true)           // marked dirty for the future outbox
    }

    @Test func saveReadingStateWithBookmarkRoundTrips() async throws {
        let store = try makeStore()
        let bookID = "urn:isbn:9780000000001"
        let loc = Data("{\"href\":\"c1.xhtml\"}".utf8)
        let bookmark = Bookmark(bookID: bookID, locator: loc)
        let state = ReadingState(bookID: bookID, locator: loc, bookmarks: [bookmark])

        try await store.save(state)

        let loaded = try await store.readingState(bookID: bookID)
        #expect(loaded?.bookmarks.count == 1)
        #expect(loaded?.bookmarks.first?.id == bookmark.id)
        #expect(loaded?.locator == loc)
    }

    @Test func writeStampsRecentUpdatedAt() async throws {
        let store = try makeStore()
        let before = Date()
        try await store.upsert(sampleBook())
        let book = try await store.book(id: "urn:isbn:9780000000001")
        #expect(book!.updatedAt >= before)            // store owns the write clock
    }
}
