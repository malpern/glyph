import Foundation
import Observation
import AVFoundation
import ReaderCore

/// Drives text-to-speech from the **parsed paragraph model** (not the Readium
/// WebView's pagination) and tracks exactly which (spine, paragraph, sentence) is
/// being spoken — the position the X4 page-follow and on-screen highlight need.
///
/// Playback goes through a pluggable `SpeechEngine` (Apple / OpenAI / ElevenLabs);
/// this controller owns only the *queue* and *position*. It speaks one sentence at a
/// time and publishes the position on **audio start**, so the highlight + X4 stay in
/// sync with the voice even when a cloud engine adds network latency.
///
/// Audio is always phone → AirPods (spoken-audio playback session). The controller is
/// the single playback surface: the on-screen controls AND the X4's forwarded physical
/// buttons both call the same `play/pause/next/previous/rate` methods.
@MainActor
@Observable
final class SpeechController {

    /// A single spoken unit: one sentence, tagged with its X4 address.
    private struct Unit { let paragraph: Int; let sentence: Int; let text: String }

    // Observable position/state
    private(set) var spineIndex = 0
    private(set) var paragraphOrdinal = 0   // 1-based; 0 = nothing spoken yet
    private(set) var sentenceIndex = 0      // 0-based within the paragraph
    private(set) var isPlaying = false
    private(set) var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    /// The sentence currently being spoken, with intra-paragraph context — used to
    /// draw the on-screen highlight (Readium resolves it by fuzzy text match).
    private(set) var spokenSentence: SpokenSentence?

    struct SpokenSentence: Equatable {
        let spineIndex: Int
        let sentenceText: String
        let before: String?
        let after: String?
        /// The full text of the current `<p>` — for paragraph-granularity highlighting.
        let paragraphText: String
    }

    /// Fired whenever the spoken position changes; `paragraphChanged` is true when we
    /// cross into a new `<p>` — the trigger to send `goto` to the X4.
    var onPositionChange: ((_ spine: Int, _ paragraph: Int, _ sentence: Int, _ paragraphChanged: Bool) -> Void)?

    private let content: SpineContentProvider
    private var engine: SpeechEngine
    private let nowPlaying: NowPlayingController
    private var units: [Unit] = []
    private var index = 0
    private var spineCount = 0
    private var speaking = false   // an utterance is in flight (possibly paused)
    private var paused = false     // paused mid-utterance

    init(content: SpineContentProvider, bookTitle: String, engine: SpeechEngine = AppleSpeechEngine()) {
        self.content = content
        self.engine = engine
        self.nowPlaying = NowPlayingController(bookTitle: bookTitle)
        // Lock screen / AirPods / Control Center → the same playback surface.
        nowPlaying.onPlay = { [weak self] in self?.play() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.nextSentence() }
        nowPlaying.onPrevious = { [weak self] in self?.previousSentence() }
    }

    /// Swap the TTS engine live (the user changed voice/provider). Re-speaks the current
    /// sentence on the new voice if we were playing.
    func setEngine(_ newEngine: SpeechEngine) {
        let wasPlaying = isPlaying
        engine.stop()
        engine = newEngine
        speaking = false
        paused = false
        if wasPlaying { speakCurrent() }
    }

    /// Stop speaking and remove the Now Playing entry / remote handlers.
    func tearDown() {
        isPlaying = false
        engine.stop()
        speaking = false
        paused = false
        spokenSentence = nil
        nowPlaying.clear()
    }

    private func updateNowPlaying() {
        let sentence = units.indices.contains(index) ? units[index].text : ""
        nowPlaying.update(isPlaying: isPlaying, sentence: sentence)
    }

    // MARK: Playback surface (UI + remote both call these)

    func start(spineIndex: Int) async {
        spineCount = (try? await content.spineCount()) ?? 0
        // Skip front matter (cover/title pages have no <p>) to the first spine with text.
        var idx = max(0, spineIndex)
        while idx < spineCount {
            await load(spineIndex: idx)
            if !units.isEmpty { break }
            idx += 1
        }
        play()
    }

    func play() {
        guard !units.isEmpty else { return }
        activateAudioSession()
        isPlaying = true
        if paused {
            engine.resume()
            paused = false
        } else if !speaking {
            speakCurrent()
        }
        updateNowPlaying()
    }

    func pause() {
        isPlaying = false
        if speaking {
            engine.pause()
            paused = true
        }
        updateNowPlaying()
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func nextSentence() { seek(to: index + 1) }
    func previousSentence() { seek(to: index - 1) }

    /// Cycle through a few speaking rates; applies immediately to the current sentence.
    func cycleRate() {
        let rates: [Float] = [0.45, 0.5, 0.55, 0.6]
        let next = rates.first(where: { $0 > rate }) ?? rates[0]
        rate = next
        if isPlaying { seek(to: index) }   // re-speak current at the new rate
    }

    // MARK: - Content

    private func load(spineIndex: Int) async {
        self.spineIndex = spineIndex
        let paragraphs = (try? await content.paragraphs(spineIndex: spineIndex)) ?? []
        units = paragraphs.flatMap { paragraph in
            paragraph.sentences.enumerated().map {
                Unit(paragraph: paragraph.ordinal, sentence: $0.offset, text: $0.element)
            }
        }
        index = 0
    }

    private func speakCurrent() {
        guard units.indices.contains(index) else { return }
        let unit = units[index]
        speaking = true
        paused = false
        engine.speak(
            unit.text, rate: rate,
            onStart: { [weak self] in self?.didStartSpeaking(unit) },
            onFinish: { [weak self] in self?.didFinishSpeaking() }
        )
    }

    /// The current sentence's audio actually started — publish its position now so the
    /// on-screen highlight and the X4 land in sync with the voice.
    private func didStartSpeaking(_ unit: Unit) {
        let changed = unit.paragraph != paragraphOrdinal
        paragraphOrdinal = unit.paragraph
        sentenceIndex = unit.sentence
        onPositionChange?(spineIndex, unit.paragraph, unit.sentence, changed)
        publishSpokenSentence()
        updateNowPlaying()

        // Warm the next sentence's audio while this one plays (hides cloud latency).
        if units.indices.contains(index + 1) {
            engine.prefetch(units[index + 1].text, rate: rate)
        }

        #if DEBUG
        print("🔊 TTS spine=\(spineIndex) para=\(unit.paragraph) sent=\(unit.sentence): \(unit.text.prefix(48))")
        #endif
    }

    private func didFinishSpeaking() {
        speaking = false
        guard isPlaying else { return }
        index += 1
        if units.indices.contains(index) {
            speakCurrent()
        } else {
            Task { await advanceToNextSpine() }
        }
    }

    private func seek(to newIndex: Int) {
        guard units.indices.contains(newIndex) else { return }
        index = newIndex
        engine.stop()              // suppresses the in-flight utterance's onFinish
        speaking = false
        paused = false
        if isPlaying {
            speakCurrent()
        } else {
            // Scrubbing while paused: move the position without speaking.
            let unit = units[newIndex]
            paragraphOrdinal = unit.paragraph
            sentenceIndex = unit.sentence
            onPositionChange?(spineIndex, unit.paragraph, unit.sentence, true)
            publishSpokenSentence()
        }
    }

    /// Publish the current sentence (plus intra-paragraph neighbours for fuzzy-match
    /// context) so the reader can highlight it on screen.
    private func publishSpokenSentence() {
        guard units.indices.contains(index) else { spokenSentence = nil; return }
        let unit = units[index]
        let before = (index > 0 && units[index - 1].paragraph == unit.paragraph)
            ? String(units[index - 1].text.suffix(40)) : nil
        let after = (units.indices.contains(index + 1) && units[index + 1].paragraph == unit.paragraph)
            ? String(units[index + 1].text.prefix(40)) : nil
        let paragraphText = units.filter { $0.paragraph == unit.paragraph }.map(\.text).joined(separator: " ")
        spokenSentence = SpokenSentence(
            spineIndex: spineIndex, sentenceText: unit.text,
            before: before, after: after, paragraphText: paragraphText
        )
    }

    private func advanceToNextSpine() async {
        let next = spineIndex + 1
        guard next < spineCount else { isPlaying = false; return }
        await load(spineIndex: next)
        if isPlaying { speakCurrent() }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP, .duckOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal: speech still plays through the default route.
        }
    }
}
