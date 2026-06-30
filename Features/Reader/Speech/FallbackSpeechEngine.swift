import Foundation

/// Wraps a cloud engine with an on-device Apple fallback. If the cloud synthesis fails
/// (no key, network, rate limit, bad response), it re-speaks the current sentence with
/// Apple and stays on Apple for the rest of the session — so read-aloud never just dies.
@MainActor
final class FallbackSpeechEngine: SpeechEngine {
    private let primary: CloudSpeechEngine
    private let fallback: SpeechEngine
    private var usingFallback = false

    // Remember the in-flight request so we can re-issue it to the fallback on error.
    private var text = ""
    private var rate: Float = 0
    private var onStart: (() -> Void)?
    private var onFinish: (() -> Void)?

    init(primary: CloudSpeechEngine, fallback: SpeechEngine) {
        self.primary = primary
        self.fallback = fallback
        primary.onError = { [weak self] _ in self?.switchToFallback() }
    }

    private var active: SpeechEngine { usingFallback ? fallback : primary }

    func speak(_ text: String, rate: Float, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.text = text
        self.rate = rate
        self.onStart = onStart
        self.onFinish = onFinish
        active.speak(text, rate: rate, onStart: onStart, onFinish: onFinish)
    }

    private func switchToFallback() {
        guard !usingFallback else { return }
        usingFallback = true
        // Re-speak the sentence that just failed, on Apple.
        fallback.speak(text, rate: rate, onStart: onStart ?? {}, onFinish: onFinish ?? {})
    }

    func pause() { active.pause() }
    func resume() { active.resume() }
    func stop() { active.stop() }
    func prefetch(_ text: String, rate: Float) { active.prefetch(text, rate: rate) }
}
