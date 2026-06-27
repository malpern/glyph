import SwiftUI

@main
struct ReaderApp: App {
    /// Built once and injected into the environment for the whole app.
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
        }
    }
}
