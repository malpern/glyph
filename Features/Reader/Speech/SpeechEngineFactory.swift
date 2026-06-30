import Foundation

/// Builds the `SpeechEngine` for the user's chosen provider + voice, reading API keys
/// from the Keychain. Falls back to Apple when a cloud provider isn't configured.
@MainActor
enum SpeechEngineFactory {
    static func make(from settings: ReaderSettings) -> SpeechEngine {
        switch settings.ttsProvider {
        case .apple:
            return AppleSpeechEngine()
        case .openai:
            guard let key = KeychainHelper.read(account: KeychainHelper.Account.openAI), !key.isEmpty else {
                return AppleSpeechEngine()   // not configured → fall back
            }
            return OpenAISpeechEngine(apiKey: key, voice: settings.openAIVoice)
        case .elevenlabs:
            guard let key = KeychainHelper.read(account: KeychainHelper.Account.elevenLabs), !key.isEmpty else {
                return AppleSpeechEngine()
            }
            return ElevenLabsSpeechEngine(apiKey: key, voiceID: settings.elevenLabsVoiceID)
        }
    }
}
