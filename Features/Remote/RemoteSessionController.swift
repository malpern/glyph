import Foundation
import Observation
import ReaderCore

/// Orchestrates a remote session with the X4: connects the WebSocket, drives
/// **page-follow** (sends `goto{spine,para}` as TTS crosses into each new
/// paragraph), and routes inbound events back into playback.
///
/// This is where the live `goto` path lives. Per the protocol's forward-compat
/// design, inbound `button` events are routed into the *same* `SpeechController`
/// the on-screen controls use, so the X4's physical buttons (Phase 4) will work
/// with no further wiring once the firmware sends them.
@MainActor
@Observable
final class RemoteSessionController {
    let client = X4Client()
    private(set) var isActive = false

    private weak var speech: SpeechController?
    private var lastSpine = -1
    private var lastPara = -1
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    init(speech: SpeechController) {
        self.speech = speech
        client.onEvent = { [weak self] event in self?.handle(event) }
        client.onDisconnect = { [weak self] in self?.scheduleReconnect() }
        // TTS paragraph crossings drive the X4's page turns.
        speech.onPositionChange = { [weak self] spine, para, _, paragraphChanged in
            guard paragraphChanged else { return }
            self?.sendGoto(spine: spine, para: para)
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

    private func sendGoto(spine: Int, para: Int) {
        guard isActive else { return }
        lastSpine = spine
        lastPara = para
        client.send(.goto(spine: spine, para: para))
    }

    private func handle(_ event: RemoteEvent) {
        switch event {
        case .ready:
            reconnectAttempt = 0   // healthy connection
            // On (re)connect, re-announce where we are so the device re-syncs.
            if lastPara >= 0 { client.send(.goto(spine: lastSpine, para: lastPara)) }
        case let .button(action):
            route(button: action)
        default:
            break   // pong / acks / unknown — nothing to do for page-follow
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
