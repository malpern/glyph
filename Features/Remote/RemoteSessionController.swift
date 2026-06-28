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

    private weak var speech: SpeechController?
    private var lastSpine = -1
    private var lastPara = -1
    private var lastSent = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    init(speech: SpeechController) {
        self.speech = speech
        client.onEvent = { [weak self] event in self?.handle(event) }
        client.onDisconnect = { [weak self] in self?.scheduleReconnect() }
        // Every spoken sentence drives a precise highlight on the X4.
        speech.onPositionChange = { [weak self] spine, para, sent, _ in
            self?.sendHighlight(spine: spine, para: para, sent: sent)
        }
    }

    var connectionState: X4Client.ConnectionState { client.state }

    func toggle() { isActive ? stop() : start() }

    func start() {
        isActive = true
        reconnectAttempt = 0
        client.connect()
    }

    func stop() {
        isActive = false
        reconnectTask?.cancel()
        reconnectTask = nil
        client.disconnect()
    }

    /// Retry the connection with capped exponential backoff while the session is active.
    private func scheduleReconnect() {
        guard isActive else { return }
        reconnectTask?.cancel()
        let delay = min(pow(2.0, Double(reconnectAttempt)), 10.0)   // 1, 2, 4, 8, 10, 10…
        reconnectAttempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isActive else { return }
            self.client.connect()
        }
    }

    // MARK: -

    private func sendHighlight(spine: Int, para: Int, sent: Int) {
        guard isActive else { return }
        lastSpine = spine
        lastPara = para
        lastSent = sent
        client.send(.highlight(spine: spine, para: para, sentence: sent, text: nil))
    }

    private func handle(_ event: RemoteEvent) {
        switch event {
        case .ready:
            reconnectAttempt = 0   // healthy connection
            // On (re)connect, re-announce where we are so the device re-syncs.
            if lastPara >= 0 {
                client.send(.highlight(spine: lastSpine, para: lastPara, sentence: lastSent, text: nil))
            }
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
