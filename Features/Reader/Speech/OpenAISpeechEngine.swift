import Foundation
import AVFoundation

/// OpenAI text-to-speech. Synthesizes one sentence to MP3 (`/v1/audio/speech`) and
/// plays it via `AVAudioPlayer`. Per-sentence playback means no word-timing is needed —
/// the controller advances when each clip finishes.
@MainActor
final class OpenAISpeechEngine: NSObject, SpeechEngine, AVAudioPlayerDelegate {
    static let voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer", "ash", "sage", "coral"]

    private let apiKey: String
    private let voice: String
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var onStart: (() -> Void)?
    private var onFinish: (() -> Void)?
    private var stopped = false
    /// Called when synthesis fails — lets a wrapper fall back to another engine.
    var onError: ((Error) -> Void)?

    init(apiKey: String, voice: String) {
        self.apiKey = apiKey
        self.voice = voice
    }

    func speak(_ text: String, rate: Float, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish
        stopped = false
        let speed = Self.speed(forAppleRate: rate)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await Self.synthesize(text: text, apiKey: self.apiKey, voice: self.voice, speed: speed)
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

    // MARK: HTTP

    private static func synthesize(text: String, apiKey: String, voice: String, speed: Double) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": voice,
            "response_format": "mp3",
            "speed": speed,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "OpenAITTS", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI TTS HTTP \(code)"])
        }
        return data
    }

    /// Apple's default utterance rate is ~0.5; map to OpenAI `speed` (1.0 = normal).
    static func speed(forAppleRate rate: Float) -> Double {
        let normalized = Double(rate) / Double(AVSpeechUtteranceDefaultSpeechRate)
        return min(max(normalized, 0.25), 4.0)
    }
}
