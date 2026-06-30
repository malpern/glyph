import Foundation
import Observation
import ReaderCore

/// Orchestrates a remote session with the X4: connects the WebSocket, drives
/// **per-sentence highlight** (sends `highlight{spine,para,sent}` as TTS speaks
/// each sentence — the device navigates to the paragraph *and* highlights the
/// sentence), and routes inbound events back into playback.
///
/// `highlight` is the live drive path now that the firmware supports it; if the
/// device acks `ok:false` (the sentence wasn't on the resolved page), we fall back
/// to `goto{spine,para}` so the page still follows. Inbound `button` events route
/// into the *same* `SpeechController` the on-screen controls use, so the X4's
/// physical buttons (Phase 4) work with no further wiring once the firmware sends them.
@MainActor
@Observable
final class RemoteSessionController {
    let client = X4Client()
    private(set) var isActive = false

    /// Fired when the X4 user takes control (a physical `pos` page-turn): the reader
    /// pauses TTS, follows to that position, and mirrors it into cloud sync.
    var onRemotePosition: ((_ spine: Int, _ para: Int, _ bookID: String?) -> Void)?
    /// The phone's current reading position, queried on connect so the phone can push it
    /// to the X4 (`goto`) — phone-wins-on-connect, since the X4 has no trustworthy clock.
    var phonePosition: (() async -> (spine: Int, para: Int)?)?

    private weak var speech: SpeechController?
    private let granularity: () -> HighlightGranularity
    private var lastSpine = -1
    private var lastPara = -1
    private var lastSent = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var suspended = false   // app backgrounded: keep the session intent, stop the radio

    init(speech: SpeechController, granularity: @escaping () -> HighlightGranularity) {
        self.speech = speech
        self.granularity = granularity
        client.onEvent = { [weak self] event in self?.handle(event) }
        client.onDisconnect = { [weak self] in self?.scheduleReconnect() }
        // Drive the X4 at the user's chosen granularity (sentence / paragraph / page).
        speech.onPositionChange = { [weak self] spine, para, sent, paragraphChanged in
            self?.emit(spine: spine, para: para, sent: sent, paragraphChanged: paragraphChanged)
        }
    }

    var connectionState: X4Client.ConnectionState { client.state }

    func toggle() { isActive ? stop() : start() }

    func start() {
        isActive = true
        suspended = false
        reconnectAttempt = 0
        client.connect()
    }

    func stop() {
        isActive = false
        suspended = false
        reconnectTask?.cancel()
        reconnectTask = nil
        client.disconnect()
    }

    /// App backgrounded: drop the socket and stop reconnecting so the X4 (a local-network
    /// WebSocket, not covered by the audio background mode) doesn't churn the radio. The
    /// `isActive` intent is kept; `resume()` reconnects on return to foreground. Read-aloud
    /// audio is independent and keeps playing.
    func suspend() {
        guard isActive, !suspended else { return }
        suspended = true
        reconnectTask?.cancel()
        reconnectTask = nil
        client.disconnect()
    }

    func resume() {
        guard isActive, suspended else { return }
        suspended = false
        reconnectAttempt = 0
        client.connect()
    }

    /// Retry the connection with capped exponential backoff while the session is active.
    private func scheduleReconnect() {
        guard isActive, !suspended else { return }
        reconnectTask?.cancel()
        let delay = min(pow(2.0, Double(reconnectAttempt)), 10.0)   // 1, 2, 4, 8, 10, 10…
        reconnectAttempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isActive, !self.suspended else { return }
            self.client.connect()
        }
    }

    // MARK: -

    /// Record the current position and emit it at the chosen granularity. Paragraph
    /// and page modes only fire on a paragraph boundary, so the slow e-ink screen
    /// refreshes calmly instead of flashing on every sentence.
    private func emit(spine: Int, para: Int, sent: Int, paragraphChanged: Bool) {
        guard isActive else { return }
        lastSpine = spine
        lastPara = para
        lastSent = sent
        send(spine: spine, para: para, sent: sent, paragraphChanged: paragraphChanged)
    }

    private func send(spine: Int, para: Int, sent: Int, paragraphChanged: Bool) {
        switch granularity() {
        case .sentence:
            client.send(.highlight(spine: spine, para: para, sentence: sent, text: nil))
        case .paragraph:
            guard paragraphChanged else { return }
            client.send(.highlight(spine: spine, para: para, sentence: nil, text: nil))
        case .page:
            guard paragraphChanged else { return }
            client.send(.goto(spine: spine, para: para))
        case .off:
            return   // nothing sent to the X4
        }
    }

    private func handle(_ event: RemoteEvent) {
        switch event {
        case .ready:
            reconnectAttempt = 0   // healthy connection
            // Phone wins on connect: push our current cloud position to the X4 so it
            // resumes where the phone is. (The X4 has no clock, so it can't arbitrate.)
            Task { [weak self] in
                guard let self, let pos = await self.phonePosition?() else { return }
                self.lastSpine = pos.spine
                self.lastPara = pos.para
                self.client.send(.goto(spine: pos.spine, para: pos.para))
            }
        case let .position(spine, para):
            // The X4 user turned a page with the buttons — they took control.
            if let para { onRemotePosition?(spine ?? lastSpine, para, nil) }
        case let .highlightAck(spine, para, _, ok):
            // Sentence wasn't on the resolved page — fall back to page-follow.
            if ok == false, let para {
                client.send(.goto(spine: spine ?? lastSpine, para: para))
            }
        case let .button(action):
            route(button: action)
        default:
            break   // pong / goto ack / unknown — nothing to do
        }
    }

    private func route(button action: String) {
        guard let speech else { return }
        switch action {
        case "play": speech.play()
        case "pause": speech.pause()
        case "next": speech.nextSentence()
        case "prev": speech.previousSentence()
        case "speed": speech.cycleRate()
        default: break
        }
    }
}
