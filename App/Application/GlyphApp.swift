import SwiftUI
import FirebaseCore

@main
struct GlyphApp: App {
    /// Built once and injected into the environment for the whole app.
    @State private var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()                       // must precede any Firestore use
        _container = State(initialValue: AppContainer())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .task { await container.startSync() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await container.syncEngine.reconcile() }
                    }
                }
        }
    }
}
