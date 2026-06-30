import Foundation
import Observation
import ReadiumNavigator

/// User-facing reading appearance. Persisted app-wide (UserDefaults) and mapped to
/// Readium's `EPUBPreferences`, which the navigator applies live.
struct ReaderSettings: Codable, Equatable, Sendable {
    var theme: ReaderTheme = .light
    var fontScale: Double = 1.0     // 1.0 == 100%
    var lineHeight: Double = 1.4
    var font: ReaderFont = .original
    /// How read-aloud highlights/follows on the phone, and what's emitted to the X4.
    var highlightGranularity: HighlightGranularity = .sentence
    /// Which TTS engine reads aloud.
    var ttsProvider: TTSProvider = .apple
    /// Selected OpenAI voice (one of `OpenAISpeechEngine.voices`).
    var openAIVoice: String = "onyx"
    /// Selected ElevenLabs voice id.
    var elevenLabsVoiceID: String = "21m00Tcm4TlvDq8ikWAM"   // Rachel

    var epubPreferences: EPUBPreferences {
        EPUBPreferences(
            fontFamily: font.readiumFontFamily,
            fontSize: fontScale,
            lineHeight: lineHeight,
            // A custom font only takes effect with the publisher's styles disabled.
            publisherStyles: font == .original ? nil : false,
            theme: theme.readiumTheme
        )
    }

    init() {}

    /// Tolerant decode: missing keys fall back to defaults so adding a setting never
    /// wipes a user's existing preferences on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? .light
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 1.4
        font = try c.decodeIfPresent(ReaderFont.self, forKey: .font) ?? .original
        highlightGranularity = try c.decodeIfPresent(HighlightGranularity.self, forKey: .highlightGranularity) ?? .sentence
        ttsProvider = try c.decodeIfPresent(TTSProvider.self, forKey: .ttsProvider) ?? .apple
        openAIVoice = try c.decodeIfPresent(String.self, forKey: .openAIVoice) ?? "onyx"
        elevenLabsVoiceID = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceID) ?? "21m00Tcm4TlvDq8ikWAM"
    }
}

/// The TTS engine that reads aloud. Cloud providers need an API key (Keychain);
/// without one they fall back to Apple.
enum TTSProvider: String, Codable, CaseIterable, Sendable {
    case apple, openai, elevenlabs
    var label: String {
        switch self {
        case .apple: return "Apple"
        case .openai: return "OpenAI"
        case .elevenlabs: return "ElevenLabs"
        }
    }
}

/// Read-aloud granularity — how often the highlight moves and the page follows on
/// the phone, and (per the firmware contract) what command the X4 receives:
/// - `.sentence` → highlight each sentence; emit `highlight{spine,para,sent}`.
/// - `.paragraph` → highlight each paragraph; emit `highlight{spine,para}` (no `sent`).
/// - `.page` → no text highlight, page-follow only; emit `goto{spine,para}`.
/// - `.off` → no highlight, no page-follow, nothing sent to the X4 (audio only).
/// The X4's e-ink refresh is slow, so coarser granularity = calmer screen.
enum HighlightGranularity: String, Codable, CaseIterable, Sendable {
    case sentence, paragraph, page, off
    var label: String {
        switch self {
        case .sentence: return "Sentence"
        case .paragraph: return "Paragraph"
        case .page: return "Page"
        case .off: return "Off"
        }
    }
}

enum ReaderTheme: String, Codable, CaseIterable, Sendable {
    case light, sepia, dark
    var readiumTheme: Theme {
        switch self {
        case .light: return .light
        case .sepia: return .sepia
        case .dark: return .dark
        }
    }
    var label: String { rawValue.capitalized }
}

enum ReaderFont: String, Codable, CaseIterable, Sendable {
    case original, serif, sans, dyslexic
    var readiumFontFamily: FontFamily? {
        switch self {
        case .original: return nil
        case .serif: return .serif
        case .sans: return .sansSerif
        case .dyslexic: return .openDyslexic
        }
    }
    var label: String {
        switch self {
        case .original: return "Original"
        case .serif: return "Serif"
        case .sans: return "Sans-serif"
        case .dyslexic: return "Dyslexic"
        }
    }
}

/// Holds the current `ReaderSettings`, persisting changes and exposing the Readium
/// preferences. Shared app-wide so settings stick across books and sessions.
@MainActor
@Observable
final class ReaderSettingsStore {
    var settings: ReaderSettings {
        didSet { save() }
    }

    private let key = "reader.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data) {
            settings = decoded
        } else {
            settings = ReaderSettings()
        }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["READER_THEME"], let theme = ReaderTheme(rawValue: raw) { settings.theme = theme }
        if let raw = env["READER_FONT_SCALE"], let scale = Double(raw) { settings.fontScale = scale }
        if let raw = env["READER_GRANULARITY"], let g = HighlightGranularity(rawValue: raw) { settings.highlightGranularity = g }
        #endif
    }

    var epubPreferences: EPUBPreferences { settings.epubPreferences }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
