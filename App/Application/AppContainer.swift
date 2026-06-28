import Foundation
import SwiftUI
import Observation
import ReaderCore

/// The composition root. Builds the concrete store, storage, and services once at
/// launch and hands out the protocol-typed dependencies the features need. This
/// is the single place that knows which implementations are wired in — swapping
/// the persistence engine or adding a sync-aware store happens only here.
///
/// Injected with SwiftUI's `@Observable` object environment
/// (`.environment(container)` / `@Environment(AppContainer.self)`).
@MainActor
@Observable
final class AppContainer {
    let store: SwiftDataStore
    let storage: BookStorage
    /// Reconciles local reading positions with the cloud. Started in `startSync()`.
    let syncEngine: ReadingStateSyncEngine

    /// Stub identity for the first cut — a shared dev user so two devices sync to
    /// one account without real auth. Replaced by Firebase email-link in P2.5.
    private let auth: any AuthProviding = StubAuth()

    /// Features depend on the protocols, not the concrete `SwiftDataStore`.
    var library: any LibraryRepository { store }
    var readingState: any ReadingStateRepository { store }

    init() {
        let stack: (store: SwiftDataStore, storage: BookStorage)
        do {
            stack = (try ReaderStore.make(), try BookStorage())
        } catch {
            // Last-resort fallback so the app still launches; a real build would
            // surface this. Phase 1 keeps it simple.
            assertionFailure("Failed to build persistent stack: \(error)")
            stack = (try! ReaderStore.make(inMemory: true), try! BookStorage())
        }
        self.store = stack.store
        self.storage = stack.storage
        self.syncEngine = ReadingStateSyncEngine(store: stack.store, remote: FirebaseSyncClient())
    }

    /// Drive the sync engine from auth state: start on sign-in, stop on sign-out.
    /// With `StubAuth` this fires once for the shared dev user.
    func startSync() async {
        for await userID in auth.userIDs() {
            if let userID {
                await syncEngine.start(userID: userID)
            } else {
                await syncEngine.stop()
            }
        }
    }

    func makeImporter() -> BookImporter {
        BookImporter(library: store, storage: storage)
    }
}
