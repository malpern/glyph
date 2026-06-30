import UIKit

/// Highlight colours offered to the user. The `rawValue` token is what's persisted in
/// `Highlight.color`, so it stays stable across versions and (later) sync.
enum HighlightColor: String, CaseIterable, Sendable {
    case yellow, green, blue, pink

    var uiColor: UIColor {
        switch self {
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .blue:   return .systemBlue
        case .pink:   return .systemPink
        }
    }

    var label: String { rawValue.capitalized }

    static func from(_ token: String?) -> HighlightColor {
        token.flatMap(HighlightColor.init(rawValue:)) ?? .yellow
    }
}
