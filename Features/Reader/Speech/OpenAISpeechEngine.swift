import Foundation
import AVFoundation

/// OpenAI text-to-speech — synthesizes each sentence to MP3 (`/v1/audio/speech`).
@MainActor
final class OpenAISpeechEngine: CloudSpeechEngine {
    static let voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer", "ash", "sage", "coral"]

    private let apiKey: String
    private let voice: String

    init(apiKey: String, voice: String) {
        self.apiKey = apiKey
        self.voice = voice
    }

    override func synthesize(_ text: String, speed: Double) async throws -> Data {
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
        return try await postForAudio(request, label: "OpenAITTS")
    }

    override func speed(forAppleRate rate: Float) -> Double {
        min(max(super.speed(forAppleRate: rate), 0.25), 4.0)   // OpenAI accepts 0.25–4.0
    }
}
