import SwiftUI
import ReaderCore

/// Hosts a reading session: shows loading/error states, presents the EPUB
/// navigator when ready, and provides minimal auto-hiding chrome. Tapping the
/// center toggles the top bar; reading is otherwise distraction-free.
struct ReaderContainerView: View {
    @State private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showChrome = true

    init(book: Book, fileURL: URL, readingState: any ReadingStateRepository) {
        _viewModel = State(initialValue: ReaderViewModel(
            book: book, fileURL: fileURL, readingState: readingState
        ))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            content
            if showChrome { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .statusBarHidden(!showChrome)
        .task { await viewModel.load() }
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

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { close() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Close book")

            Text(viewModel.book.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func close() {
        Task {
            await viewModel.flush()   // make resume exact before tearing down
            dismiss()
        }
    }
}
