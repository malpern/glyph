import Foundation
import Observation
import AVFoundation
import ReaderCore

/// Drives text-to-speech from the **parsed paragraph model** (not the Readium
/// WebView's pagination) and tracks exactly which (spine, paragraph, sentence) is
/// being spoken — the position the X4 page-follow needs.
///
/// Audio is always phone → AirPods (spoken-audio playback session). The controller
/// is the single playback surface: the on-screen controls AND the X4's forwarded
/// physical buttons (Phase 4) both call the same `play/pause/next/previous/rate`
/// methods, so inbound remote events "just work".
@MainActor
@Observable
final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {

    /// A single spoken unit: one sentence, tagged with its X4 address.
    private struct Unit { let paragraph: Int; let sentence: Int; let text: String }

    // Observable position/state
    private(set) var spineIndex = 0
    private(set) var paragraphOrdinal = 0   // 1-based; 0 = nothing spoken yet
    private(set) var sentenceIndex = 0      // 0-based within the paragraph
    private(set) var isPlaying = false
    private(set) var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    /// The sentence currently being spoken, with intra-paragraph context — used to
    /// draw the on-screen highlight (Readium resolves it by fuzzy text match, so no
    /// precise DOM range is needed).
    private(set) var spokenSentence: SpokenSentence?

    struct SpokenSentence: Equatable {
        let spineIndex: Int
        let text: String
        let before: String?
        let after: String?
    }

    /// Fired whenever the spoken position changes; `paragraphChanged` is true when
    /// we cross into a new `<p>` — the trigger to send `goto` to the X4.
    var onPositionChange: ((_ spine: Int, _ paragraph: Int, _ sentence: Int, _ paragraphChanged: Bool) -> Void)?

    private let content: SpineContentProvider
    private let synthesizer = AVSpeechSynthesizer()
    private let nowPlaying: NowPlayingController
    private var units: [Unit] = []
    private var index = 0
    private var spineCount = 0
    private var generation = 0                       // guards stale utterance callbacks
    private var generationByUtterance: [ObjectIdentifier: Int] = [:]

    init(content: SpineContentProvider, bookTitle: String) {
        self.content = content
        self.nowPlaying = NowPlayingController(bookTitle: bookTitle)
        super.init()
        synthesizer.delegate = self
        // Lock screen / AirPods / Control Center → the same playback surface.
        nowPlaying.onPlay = { [weak self] in self?.play() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.nextSentence() }
        nowPlaying.onPrevious = { [weak self] in self?.previousSentence() }
    }

    /// Stop speaking and remove the Now Playing entry / remote handlers.
    func tearDown() {
        pause()
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
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else if !synthesizer.isSpeaking {
            speakCurrent()
        }
        updateNowPlaying()
    }

    func pause() {
        isPlaying = false
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
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
        let changed = unit.paragraph != paragraphOrdinal
        paragraphOrdinal = unit.paragraph
        sentenceIndex = unit.sentence
        onPositionChange?(spineIndex, unit.paragraph, unit.sentence, changed)
        publishSpokenSentence()
        updateNowPlaying()

        #if DEBUG
        print("🔊 TTS spine=\(spineIndex) para=\(unit.paragraph) sent=\(unit.sentence): \(unit.text.prefix(48))")
        #endif

        generation += 1
        let utterance = AVSpeechUtterance(string: unit.text)
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.05
        generationByUtterance[ObjectIdentifier(utterance)] = generation
        synthesizer.speak(utterance)
    }

    private func seek(to newIndex: Int) {
        guard units.indices.contains(newIndex) else { return }
        index = newIndex
        synthesizer.stopSpeaking(at: .immediate)   // old utterance becomes stale (generation bumps below)
        if isPlaying {
            speakCurrent()
        } else {
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
        spokenSentence = SpokenSentence(spineIndex: spineIndex, text: unit.text, before: before, after: after)
    }

    private func advanceToNextSpine() async {
        let next = spineIndex + 1
        guard next < spineCount else { isPlaying = false; return }
        await load(spineIndex: next)
        if isPlaying { speakCurrent() }
    }

    private func finished(_ id: ObjectIdentifier) {
        let isCurrent = generationByUtterance[id] == generation
        generationByUtterance[id] = nil
        guard isCurrent, isPlaying else { return }     // ignore stale (seeked-away) utterances
        index += 1
        if units.indices.contains(index) {
            speakCurrent()
        } else {
            Task { await advanceToNextSpine() }
        }
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

    // MARK: AVSpeechSynthesizerDelegate (called off the main actor → hop back)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.generationByUtterance[id] = nil }   // drop; never auto-advance on cancel
    }
}
