import SwiftUI
import ReaderCore

/// A single library cell: cover (or a typographic placeholder) with title and
/// author beneath. Apple-Books-like proportions (2:3 cover).
struct BookCard: View {
    let book: Book
    @Environment(AppContainer.self) private var container
    @State private var coverImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .multilineTextAlignment(.leading)
        // Read the cover off the main thread, once per book — decoding it synchronously in
        // `body` hitches grid scrolling.
        .task(id: book.coverPath) { await loadCover() }
    }

    @ViewBuilder private var cover: some View {
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
        } else {
            placeholder
        }
    }

    private func loadCover() async {
        guard let path = book.coverPath else { coverImage = nil; return }
        let url = container.storage.absoluteURL(for: path)
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        coverImage = data.flatMap(UIImage.init(data:))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
            Text(book.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(8)
        }
    }
}
