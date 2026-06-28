import SwiftUI
import ReaderCore

/// Hosts a reading session: shows loading/error states, presents the EPUB
/// navigator when ready, and provides minimal auto-hiding chrome. Tapping the
/// center toggles the top bar; reading is otherwise distraction-free.
struct ReaderContainerView: View {
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showChrome = true

    init(
        book: Book,
        fileURL: URL,
        readingState: any ReadingStateRepository,
        syncEngine: ReadingStateSyncEngine?
    ) {
        _viewModel = State(initialValue: ReaderViewModel(
            book: book, fileURL: fileURL, readingState: readingState, syncEngine: syncEngine
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.book.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "chevron.left") { close() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let speech = viewModel.speech {
                            Button {
                                Task { await viewModel.toggleSpeech() }
                            } label: {
                                Image(systemName: speech.isPlaying ? "pause.fill" : "play.fill")
                            }
                            .accessibilityLabel(speech.isPlaying ? "Pause read-aloud" : "Read aloud")
                        }
                    }
                }
                // Native Liquid Glass nav bar that auto-hides for distraction-free
                // reading; tapping the page toggles it.
                .toolbarVisibility(showChrome ? .visible : .hidden, for: .navigationBar)
                .statusBarHidden(!showChrome)
        }
        .task {
            await viewModel.load()
            #if DEBUG
            if ProcessInfo.processInfo.environment["READER_AUTOSPEAK"] == "1" {
                await viewModel.toggleSpeech()
            }
            #endif
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case let .failed(message):
            VStack(spacing: 16) {
                ContentUnavailableView("Couldn't Open Book", systemImage: "exclamationmark.triangle", description: Text(message))
                Button("Close") { dismiss() }
            }
        case let .ready(publication, initialLocator):
            EPUBReaderView(
                publication: publication,
                initialLocator: initialLocator,
                onLocationChange: { viewModel.locationChanged($0) },
                onTap: { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
            )
            .ignoresSafeArea()
        }
    }

    private func close() {
        Task {
            await viewModel.flush()   // make resume exact before tearing down
            dismiss()
        }
    }
}
