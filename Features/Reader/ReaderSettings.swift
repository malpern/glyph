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
        #endif
    }

    var epubPreferences: EPUBPreferences { settings.epubPreferences }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
