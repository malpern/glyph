import Foundation
import AVFoundation

/// ElevenLabs text-to-speech — synthesizes each sentence to MP3
/// (`/v1/text-to-speech/{voiceId}`). Voices are opaque ids; we ship a few well-known
/// defaults for the picker.
@MainActor
final class ElevenLabsSpeechEngine: CloudSpeechEngine {
    /// (id, display name) for the voice picker.
    static let voices: [(id: String, name: String)] = [
        ("21m00Tcm4TlvDq8ikWAM", "Rachel"),
        ("EXAVITQu4vr4xnSDxMaL", "Bella"),
        ("ErXwobaYiN019PkySvjV", "Antoni"),
        ("MF3mGyEYCl7XYWbV9V6O", "Elli"),
        ("TxGEqnHWrfWFTfGW9XjX", "Josh"),
        ("pNInz6obpgDQGcFmaJgB", "Adam"),
    ]
    static let defaultVoiceID = "21m00Tcm4TlvDq8ikWAM"   // Rachel

    static func name(forID id: String) -> String {
        voices.first { $0.id == id }?.name ?? "Custom"
    }

    private let apiKey: String
    private let voiceID: String

    init(apiKey: String, voiceID: String) {
        self.apiKey = apiKey
        self.voiceID = voiceID
    }

    override func synthesize(_ text: String, speed: Double) async throws -> Data {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_flash_v2_5",   // low-latency, good for per-sentence
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "speed": speed],
        ])
        return try await postForAudio(request, label: "ElevenLabsTTS")
    }

    override func speed(forAppleRate rate: Float) -> Double {
        min(max(super.speed(forAppleRate: rate), 0.7), 1.2)   // ElevenLabs accepts ~0.7–1.2
    }
}
