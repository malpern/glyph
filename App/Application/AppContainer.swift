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

    /// Key-based identity: the app derives a real Firebase login from a sync key
    /// the user moves between devices. Exposed so the sync settings UI can show /
    /// replace the key.
    let keyAuth = FirebaseKeyAuth(keyStore: KeychainKeyStore())

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
    func startSync() async {
        for await userID in keyAuth.userIDs() {
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
