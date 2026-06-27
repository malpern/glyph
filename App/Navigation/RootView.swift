import SwiftUI
import ReaderCore

/// Temporary root for the M1 scaffold. Replaced by the Library feature in M4.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Reader")
                .font(.largeTitle.weight(.semibold))
            Text("ReaderCore \(ReaderCore.version) linked")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
