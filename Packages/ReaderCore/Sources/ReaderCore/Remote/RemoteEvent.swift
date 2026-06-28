import Foundation

/// An event received **X4 → phone** over the remote-session WebSocket.
///
/// Decoding is intentionally tolerant (forward-compatible): unknown event types
/// become `.unknown` rather than failing, and extra/unexpected fields are ignored.
/// That lets the firmware add fields and events (e.g. the planned `button` events)
/// without breaking older clients.
public enum RemoteEvent: Sendable, Equatable {
    /// `{"evt":"ready","spine":S,"para":P,"bookId":"…"}` on connect — optionally
    /// carrying the device's current position + loaded book, for resume reconciliation.
    case ready(spine: Int?, para: Int?, bookID: String?)
    /// `{"evt":"pos","spine":S,"para":P}` — the user navigated **on the X4**; lets the
    /// phone mirror live X4 reading into the cloud. [PLANNED]
    case position(spine: Int?, para: Int?)
    /// `{"evt":"pong"}`. [LIVE]
    case pong
    /// `{"evt":"goto",…,"ok":true}` — ack of a `goto`. [LIVE]
    case gotoAck(spine: Int?, para: Int?, ok: Bool?)
    /// `{"evt":"hl",…,"ok":true}` — ack of a precise highlight. [PLANNED]
    case highlightAck(spine: Int?, para: Int?, sentence: Int?, ok: Bool?)
    /// `{"evt":"button","action":"play"}` — forwarded physical button. [PLANNED, Phase 4]
    case button(action: String)
    /// Any event type this client doesn't recognize — preserved for forward-compat.
    case unknown(type: String)

    public static func decode(_ data: Data) -> RemoteEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let evt = object["evt"] as? String
        else { return nil }

        func int(_ key: String) -> Int? { (object[key] as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool? { (object[key] as? NSNumber)?.boolValue }

        switch evt {
        case "ready": return .ready(spine: int("spine"), para: int("para") ?? int("page"), bookID: object["bookId"] as? String)
        case "pos": return .position(spine: int("spine"), para: int("para"))
        case "pong": return .pong
        case "goto": return .gotoAck(spine: int("spine"), para: int("para"), ok: bool("ok"))
        case "hl": return .highlightAck(spine: int("spine"), para: int("para"), sentence: int("sent"), ok: bool("ok"))
        case "button": return .button(action: (object["action"] as? String) ?? "")
        default: return .unknown(type: evt)
        }
    }

    public static func decode(_ text: String) -> RemoteEvent? {
        decode(Data(text.utf8))
    }
}
