import SwiftUI
import UIKit
import ReadiumNavigator
import ReadiumShared

/// A one-shot request to navigate the reader to a locator (tapping a bookmark/highlight).
/// The `token` makes repeated jumps to the same locator distinct so each tap re-navigates.
struct JumpRequest: Equatable {
    let locator: Locator
    let token: Int
}

/// A saved highlight to render: a stable id, where, and a colour token.
struct HighlightDecoration: Equatable {
    let id: String
    let locator: Locator
    let colorToken: String
}

/// The bridge to Readium's `EPUBNavigatorViewController` — the one sanctioned use of
/// UIKit. The navigator is hosted inside `ReaderHostController` so a custom "Highlight"
/// edit-menu action resolves on the responder chain. Everything above this line is pure
/// SwiftUI working from `Locator`s.
struct EPUBReaderView: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocator: Locator?
    /// Appearance (theme/font/size/spacing); applied live as it changes.
    let preferences: EPUBPreferences
    /// A one-shot jump (bookmark/highlight tap); the navigator goes to it when it changes.
    let pendingJump: JumpRequest?
    /// The read-aloud unit to highlight on screen (`nil` clears it — e.g. page mode).
    let ttsHighlight: Locator?
    /// The locator to keep on screen as read-aloud advances (page-follow); `nil` when not
    /// reading. Changes at the granularity cadence, so the page turns only when the unit
    /// moves off the page.
    let ttsFollow: Locator?
    /// Saved highlights, rendered as persistent decorations.
    let highlights: [HighlightDecoration]
    /// Forwarded from the navigator on every position change (a `Locator`).
    let onLocationChange: (Locator) -> Void
    /// A center tap that the navigator didn't consume — used to toggle chrome.
    let onTap: () -> Void
    /// The user picked "Highlight" on a text selection; carries the selection locator.
    let onHighlightSelected: (Locator) -> Void
    /// The user tapped an existing highlight decoration; carries its id.
    let onHighlightTapped: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLocationChange: onLocationChange,
            onTap: onTap,
            onHighlightSelected: onHighlightSelected,
            onHighlightTapped: onHighlightTapped
        )
    }

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            let highlightAction = EditingAction(title: "Highlight", action: #selector(ReaderHostController.makeHighlight))
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: .init(
                    preferences: preferences,
                    editingActions: EditingAction.defaultActions + [highlightAction]
                )
            )
            navigator.delegate = context.coordinator
            context.coordinator.lastPreferences = preferences

            // Tapping an existing highlight → bubble its id up for an edit/delete menu.
            let coordinator = context.coordinator
            navigator.observeDecorationInteractions(inGroup: "highlights") { event in
                coordinator.onHighlightTapped(event.decoration.id)
            }

            let host = ReaderHostController(navigator: navigator)
            host.onHighlightSelected = { coordinator.onHighlightSelected($0) }
            autoAdvanceIfRequested(navigator)
            return host
        } catch {
            return UIHostingController(rootView: ReaderUnavailableView())
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let navigator = (uiViewController as? ReaderHostController)?.navigator else { return }

        // Appearance changes live when settings change.
        if context.coordinator.lastPreferences != preferences {
            context.coordinator.lastPreferences = preferences
            navigator.submitPreferences(preferences)
        }

        // Read-aloud highlight: decorate the spoken unit (Readium fuzzy-matches the text).
        if context.coordinator.lastTTSHighlight != ttsHighlight {
            context.coordinator.lastTTSHighlight = ttsHighlight
            let decorations: [Decoration] = ttsHighlight.map {
                [Decoration(id: "tts-current", locator: $0, style: .highlight(tint: .systemYellow, isActive: true))]
            } ?? []
            navigator.apply(decorations: decorations, in: "tts")
        }

        // Read-aloud page-follow at the granularity cadence (page turns only on boundary).
        if context.coordinator.lastFollow != ttsFollow {
            context.coordinator.lastFollow = ttsFollow
            if let locator = ttsFollow {
                Task { await navigator.go(to: locator, options: NavigatorGoOptions(animated: false)) }
            }
        }

        // Saved highlights → persistent decorations in their own group.
        if context.coordinator.lastHighlights != highlights {
            context.coordinator.lastHighlights = highlights
            let decorations = highlights.map {
                Decoration(id: $0.id, locator: $0.locator,
                           style: .highlight(tint: HighlightColor.from($0.colorToken).uiColor, isActive: false))
            }
            navigator.apply(decorations: decorations, in: "highlights")
        }

        // One-shot jump to a bookmark/highlight.
        if context.coordinator.lastJump != pendingJump {
            context.coordinator.lastJump = pendingJump
            if let jump = pendingJump {
                Task { await navigator.go(to: jump.locator, options: NavigatorGoOptions(animated: true)) }
            }
        }
    }

    /// DEBUG-only: turn N pages after load so headless simulator runs can exercise the
    /// real save path and demonstrate resume. Never compiled into release.
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
        let onHighlightSelected: (Locator) -> Void
        let onHighlightTapped: (String) -> Void
        var lastPreferences: EPUBPreferences?
        var lastTTSHighlight: Locator?
        var lastFollow: Locator?
        var lastJump: JumpRequest?
        var lastHighlights: [HighlightDecoration] = []

        init(
            onLocationChange: @escaping (Locator) -> Void,
            onTap: @escaping () -> Void,
            onHighlightSelected: @escaping (Locator) -> Void,
            onHighlightTapped: @escaping (String) -> Void
        ) {
            self.onLocationChange = onLocationChange
            self.onTap = onTap
            self.onHighlightSelected = onHighlightSelected
            self.onHighlightTapped = onHighlightTapped
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            onLocationChange(locator)
        }

        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            onTap()
        }

        // Required by NavigatorDelegate (no default). Navigator errors are non-fatal.
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) {}
    }
}

/// Hosts the Readium navigator as a child so a custom "Highlight" `EditingAction`
/// resolves to `makeHighlight` via the responder chain.
final class ReaderHostController: UIViewController {
    let navigator: EPUBNavigatorViewController
    var onHighlightSelected: ((Locator) -> Void)?

    init(navigator: EPUBNavigatorViewController) {
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(navigator)
        navigator.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigator.view)
        NSLayoutConstraint.activate([
            navigator.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigator.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            navigator.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigator.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        navigator.didMove(toParent: self)
    }

    /// Invoked from the text-selection edit menu's "Highlight" item.
    @objc func makeHighlight() {
        guard let selection = navigator.currentSelection else { return }
        onHighlightSelected?(selection.locator)
        navigator.clearSelection()
    }
}

private struct ReaderUnavailableView: View {
    var body: some View {
        ContentUnavailableView("Couldn't Open Book", systemImage: "exclamationmark.triangle")
    }
}
