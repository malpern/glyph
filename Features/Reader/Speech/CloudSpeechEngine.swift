import Foundation
import AVFoundation

/// Shared base for cloud TTS engines (OpenAI, ElevenLabs). Handles the per-sentence
/// lifecycle — synthesize → play via `AVAudioPlayer` → `onStart`/`onFinish` — plus
/// pause/resume/stop, post-stop suppression, and **prefetch** (synthesize the next
/// sentence while the current one plays, so cloud latency is hidden).
///
/// Subclasses implement only `synthesize(_:speed:)` (the HTTP call) and optionally the
/// rate→speed mapping.
@MainActor
class CloudSpeechEngine: NSObject, SpeechEngine, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var heldPlayer: AVAudioPlayer?     // ready, but paused before it could start
    private var playTask: Task<Void, Never>?
    private var dataTasks: [String: Task<Data, Error>] = [:]   // in-flight / prefetched audio
    private var onStart: (() -> Void)?
    private var onFinish: (() -> Void)?
    private var stopped = false
    private var paused = false
    /// Set by a wrapper to fall back to another engine when synthesis fails.
    var onError: ((Error) -> Void)?

    /// Synthesize one sentence to playable audio (e.g. MP3). Override per provider.
    func synthesize(_ text: String, speed: Double) async throws -> Data {
        fatalError("CloudSpeechEngine subclasses must override synthesize(_:speed:)")
    }

    /// Map Apple's utterance rate (~0.5 default) to the provider's speed. Override to clamp.
    func speed(forAppleRate rate: Float) -> Double {
        Double(rate) / Double(AVSpeechUtteranceDefaultSpeechRate)
    }

    private func cacheKey(_ text: String, _ speed: Double) -> String { "\(speed)|\(text)" }

    /// Reuse an in-flight/prefetched task for this text, or start one.
    private func dataTask(_ text: String, speed: Double) -> Task<Data, Error> {
        let key = cacheKey(text, speed)
        if let existing = dataTasks[key] { return existing }
        let task = Task<Data, Error> { try await self.synthesize(text, speed: speed) }
        dataTasks[key] = task
        return task
    }

    func prefetch(_ text: String, rate: Float) {
        _ = dataTask(text, speed: speed(forAppleRate: rate))   // warms the cache; result kept on the task
    }

    func speak(_ text: String, rate: Float, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish
        stopped = false
        paused = false
        heldPlayer = nil
        let speed = speed(forAppleRate: rate)
        let key = cacheKey(text, speed)
        let dataT = dataTask(text, speed: speed)
        playTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await dataT.value
                self.dataTasks[key] = nil
                guard !Task.isCancelled, !self.stopped else { return }
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                if self.paused {
                    self.heldPlayer = player      // don't blast audio if paused mid-synth
                } else {
                    player.play()
                    self.onStart?()
                }
            } catch {
                self.dataTasks[key] = nil
                guard !self.stopped else { return }
                if let onError = self.onError { onError(error) } else { self.onFinish?() }
            }
        }
    }

    func pause() {
        paused = true
        player?.pause()
    }

    func resume() {
        paused = false
        if let held = heldPlayer {
            heldPlayer = nil
            held.play()
            onStart?()                            // the sentence's audio starts now
        } else {
            player?.play()
        }
    }

    func stop() {
        stopped = true
        playTask?.cancel()
        dataTasks.values.forEach { $0.cancel() }   // discard prefetched audio (we've jumped)
        dataTasks.removeAll()
        player?.stop()
        player = nil
        heldPlayer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if !self.stopped { self.onFinish?() } }
    }

    // MARK: HTTP helper for subclasses

    func postForAudio(_ request: URLRequest, label: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: label, code: code, userInfo: [NSLocalizedDescriptionKey: "\(label) HTTP \(code)"])
        }
        return data
    }
}
