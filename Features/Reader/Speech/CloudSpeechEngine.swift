import Foundation
import AVFoundation

/// Shared base for cloud TTS engines (OpenAI, ElevenLabs). Handles the per-sentence
/// lifecycle — synthesize → play via `AVAudioPlayer` → `onStart`/`onFinish` — plus
/// pause/resume/stop and post-stop callback suppression. Subclasses only implement
/// `synthesize(_:speed:)` (the HTTP call) and, optionally, the rate→speed mapping.
@MainActor
class CloudSpeechEngine: NSObject, SpeechEngine, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var onStart: (() -> Void)?
    private var onFinish: (() -> Void)?
    private var stopped = false
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

    func speak(_ text: String, rate: Float, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish
        stopped = false
        let speed = self.speed(forAppleRate: rate)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await self.synthesize(text, speed: speed)
                guard !Task.isCancelled, !self.stopped else { return }
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                player.play()
                self.onStart?()
            } catch {
                guard !self.stopped else { return }
                if let onError = self.onError { onError(error) } else { self.onFinish?() }
            }
        }
    }

    func pause() { player?.pause() }
    func resume() { player?.play() }

    func stop() {
        stopped = true
        task?.cancel()
        player?.stop()
        player = nil
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
