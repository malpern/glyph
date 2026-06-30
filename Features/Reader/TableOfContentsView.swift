import SwiftUI

/// The table-of-contents sheet: tap a section to jump there. The section the reader is
/// currently inside is highlighted and scrolled into view on open.
struct TableOfContentsView: View {
    let entries: [TOCEntry]
    let currentID: TOCEntry.ID?
    let onSelect: (TOCEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Contents",
                        systemImage: "list.bullet.indent",
                        description: Text("This book doesn't include a table of contents.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List(entries) { entry in
                            Button { onSelect(entry); dismiss() } label: { row(entry) }
                                .id(entry.id)
                        }
                        .onAppear {
                            guard let currentID else { return }
                            proxy.scrollTo(currentID, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private func row(_ entry: TOCEntry) -> some View {
        let isCurrent = entry.id == currentID
        HStack(spacing: 8) {
            Text(entry.title)
                .font(.body.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                .padding(.leading, CGFloat(entry.depth) * 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}
