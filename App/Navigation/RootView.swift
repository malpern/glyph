import SwiftUI

/// App root. For Phase 1 this is simply the library; navigation into the reader
/// is handled inside `LibraryView` via a full-screen cover.
struct RootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        LibraryView(viewModel: LibraryViewModel(
            library: container.library,
            importer: container.makeImporter()
        ))
    }
}
