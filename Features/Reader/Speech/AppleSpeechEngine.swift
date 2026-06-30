import Foundation
import AVFoundation

/// The on-device Apple TTS engine (`AVSpeechSynthesizer`). Zero network, zero cost —
/// the default and the fallback when a cloud provider isn't configured or errors.
@MainActor
final class AppleSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceIdentifier: String?
    private var onStart: (() -> Void)?
    private var onFinish: (() -> Void)?
    private var stopped = false

    init(voiceIdentifier: String? = nil) {
        self.voiceIdentifier = voiceIdentifier
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Float, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish
        stopped = false
        let utterance = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    func pause() {
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        stopped = true                                  // suppress the pending didFinish
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    // MARK: AVSpeechSynthesizerDelegate (off the main actor → hop back)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.stopped { self.onStart?() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.stopped { self.onFinish?() } }
    }
}
