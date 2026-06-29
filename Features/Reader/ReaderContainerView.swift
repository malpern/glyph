import SwiftUI
import ReaderCore

/// Hosts a reading session: shows loading/error states, presents the EPUB
/// navigator when ready, and provides minimal auto-hiding chrome. Tapping the
/// center toggles the top bar; reading is otherwise distraction-free.
struct ReaderContainerView: View {
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @State private var showChrome = true
    @State private var showingSettings = false

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
                        Button { showingSettings = true } label: {
                            Image(systemName: "textformat.size")
                        }
                        .accessibilityLabel("Reading settings")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let remote = viewModel.remoteSession {
                            Button {
                                remote.toggle()
                            } label: {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(remoteTint(remote.connectionState, active: remote.isActive))
                            }
                            .accessibilityLabel(remote.isActive ? "Stop X4 session" : "Connect X4")
                        }
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
                .sheet(isPresented: $showingSettings) {
                    ReaderSettingsView(store: container.readerSettings)
                }
        }
        .task {
            viewModel.attach(settings: container.readerSettings)
            await viewModel.load()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["READER_AUTOREMOTE"] == "1" { viewModel.remoteSession?.start() }
            if env["READER_AUTOSPEAK"] == "1" { await viewModel.toggleSpeech() }
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
            let tts = viewModel.ttsLocators
            EPUBReaderView(
                publication: publication,
                initialLocator: initialLocator,
                preferences: container.readerSettings.epubPreferences,
                ttsHighlight: tts.highlight,
                ttsFollow: tts.follow,
                onLocationChange: { viewModel.locationChanged($0) },
                onTap: { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
            )
            .ignoresSafeArea()
        }
    }

    private func remoteTint(_ state: X4Client.ConnectionState, active: Bool) -> Color {
        guard active else { return .secondary }
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    private func close() {
        Task {
            viewModel.stopAll()       // stop speech + disconnect X4
            await viewModel.flush()   // make resume exact before tearing down
            dismiss()
        }
    }
}
