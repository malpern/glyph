import SwiftUI
import ReadiumNavigator
import ReadiumShared

/// The bridge to Readium's `EPUBNavigatorViewController` — the one sanctioned use
/// of UIKit. We wrap the navigator rather than reimplement it: its WebView-based
/// pagination, theming, and locator mapping are exactly what we don't want to
/// rebuild. Everything above this line is pure SwiftUI working from `Locator`s.
struct EPUBReaderView: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocator: Locator?
    /// Appearance (theme/font/size/spacing); applied live as it changes.
    let preferences: EPUBPreferences
    /// Forwarded from the navigator on every position change (a `Locator`).
    let onLocationChange: (Locator) -> Void
    /// A center tap that the navigator didn't consume — used to toggle chrome.
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLocationChange: onLocationChange, onTap: onTap)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: .init(preferences: preferences)
            )
            navigator.delegate = context.coordinator
            context.coordinator.lastPreferences = preferences
            autoAdvanceIfRequested(navigator)
            return navigator
        } catch {
            return UIHostingController(rootView: ReaderUnavailableView())
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Apply appearance changes live when settings change.
        guard let navigator = uiViewController as? EPUBNavigatorViewController,
              context.coordinator.lastPreferences != preferences else { return }
        context.coordinator.lastPreferences = preferences
        navigator.submitPreferences(preferences)
    }

    /// DEBUG-only: turn N pages after load so headless simulator runs can exercise
    /// the real save path (navigator → locationDidChange → debounced persist) and
    /// demonstrate resume. Never compiled into release.
    private func autoAdvanceIfRequested(_ navigator: EPUBNavigatorViewController) {
        #if DEBUG
        guard let count = Int(ProcessInfo.processInfo.environment["READER_AUTOADVANCE"] ?? "") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))   // let the initial location settle
            for _ in 0..<count {
                _ = await navigator.goForward(options: .init())
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        #endif
    }

    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        private let onLocationChange: (Locator) -> Void
        private let onTap: () -> Void
        var lastPreferences: EPUBPreferences?

        init(onLocationChange: @escaping (Locator) -> Void, onTap: @escaping () -> Void) {
            self.onLocationChange = onLocationChange
            self.onTap = onTap
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            onLocationChange(locator)
        }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            onTap()
        }

        // Required by NavigatorDelegate (no default). Phase 1 treats navigator
        // errors as non-fatal.
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
    }
}

private struct ReaderUnavailableView: View {
    var body: some View {
        ContentUnavailableView("Couldn't Open Book", systemImage: "exclamationmark.triangle")
    }
}
