import Foundation
import SwiftUI

/// Font family the chapter reader injects via CSS.
/// Raw values are persisted in `ReaderPreferences.Keys.selectedFont`.
/// Only system fonts are used (no bundled fonts).
enum ReaderFontOption: String, CaseIterable, Identifiable, Sendable {
    case system
    case appleSDGothicNeo = "Apple SD Gothic Neo"
    case appleGothic = "AppleGothic"
    case hiraginoMincho = "Hiragino Mincho ProN"
    case hiraginoKakuGothic = "Hiragino Kaku Gothic ProN"

    static let defaultValue = ReaderFontOption.system.rawValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("settings_reader_font_system")
        case .appleSDGothicNeo: return "Apple SD Gothic Neo"
        case .appleGothic: return "AppleGothic"
        case .hiraginoMincho: return "Hiragino Mincho ProN"
        case .hiraginoKakuGothic: return "Hiragino Kaku Gothic ProN"
        }
    }

    /// CSS `font-family` value with Korean-aware fallback chain.
    var cssFontFamily: String {
        let koreanFallback = "\"Apple SD Gothic Neo\", \"AppleGothic\""
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, \(koreanFallback), sans-serif"
        case .appleSDGothicNeo, .appleGothic:
            return "\"\(rawValue)\", \(koreanFallback), sans-serif"
        case .hiraginoMincho:
            return "\"\(rawValue)\", \(koreanFallback), serif"
        case .hiraginoKakuGothic:
            return "\"\(rawValue)\", \(koreanFallback), sans-serif"
        }
    }

    static func resolved(_ rawValue: String) -> ReaderFontOption {
        ReaderFontOption(rawValue: rawValue) ?? .system
    }
}
