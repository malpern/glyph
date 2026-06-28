import Foundation
import Observation
import ReaderCore

/// WebSocket client for the X4 remote session (`ws://crosspoint.local:81`).
///
/// Thin and forward-compatible: it sends `RemoteCommand`s and surfaces decoded
/// `RemoteEvent`s via `onEvent` (unknown events are tolerated by the codec). The
/// X4 emits `{"evt":"ready"}` on connect, which we treat as "connected".
///
/// Host/port are overridable in DEBUG (`READER_X4_HOST` / `READER_X4_PORT`) so the
/// simulator can point at a local mock server.
@MainActor
@Observable
final class X4Client {
    enum ConnectionState: Sendable, Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    private(set) var state: ConnectionState = .disconnected
    /// Decoded inbound events (ready / pong / acks / buttons / unknown).
    var onEvent: ((RemoteEvent) -> Void)?
    /// Fired when the connection drops unexpectedly (not on an intentional disconnect).
    var onDisconnect: (() -> Void)?

    let url: URL
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?

    init() {
        var host = "crosspoint.local"
        var port = 81
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let h = env["READER_X4_HOST"], !h.isEmpty { host = h }
        if let p = env["READER_X4_PORT"], let value = Int(p) { port = value }
        #endif
        url = URL(string: "ws://\(host):\(port)")!
    }

    func connect() {
        guard task == nil else { return }
        state = .connecting
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop = Task { [weak self] in await self?.receiveMessages() }
    }

    func disconnect() {
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .disconnected
    }

    func send(_ command: RemoteCommand) {
        task?.send(.string(command.jsonString())) { _ in
            // Best-effort; a dropped send surfaces as a receive failure -> reconnect.
        }
    }

    // MARK: -

    private func receiveMessages() async {
        guard let task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if state != .connected { state = .connected }
                switch message {
                case let .string(text):
                    if let event = RemoteEvent.decode(text) { onEvent?(event) }
                case let .data(data):
                    if let event = RemoteEvent.decode(data) { onEvent?(event) }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    state = .failed(error.localizedDescription)
                    self.task = nil
                    onDisconnect?()
                }
                return
            }
        }
    }
}
