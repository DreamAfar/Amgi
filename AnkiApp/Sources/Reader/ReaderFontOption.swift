import Foundation
import SwiftUI

/// Font option for the chapter reader CSS injection.
/// Raw values (the `id`) are persisted in `ReaderPreferences.Keys.selectedFont`.
/// Built-in system fonts are static; imported fonts are discovered at runtime.
struct ReaderFontOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let cssFontFamily: String

    // MARK: - Built-in System Fonts

    static let system = ReaderFontOption(
        id: "system",
        title: "settings_reader_font_system", // localized at display time
        cssFontFamily: "-apple-system, BlinkMacSystemFont, \"Apple SD Gothic Neo\", \"AppleGothic\", sans-serif"
    )

    static let appleSDGothicNeo = ReaderFontOption(
        id: "Apple SD Gothic Neo",
        title: "Apple SD Gothic Neo",
        cssFontFamily: "\"Apple SD Gothic Neo\", \"AppleGothic\", sans-serif"
    )

    static let appleGothic = ReaderFontOption(
        id: "AppleGothic",
        title: "AppleGothic",
        cssFontFamily: "\"AppleGothic\", \"Apple SD Gothic Neo\", sans-serif"
    )

    static let hiraginoMincho = ReaderFontOption(
        id: "Hiragino Mincho ProN",
        title: "Hiragino Mincho ProN",
        cssFontFamily: "\"Hiragino Mincho ProN\", \"Apple SD Gothic Neo\", serif"
    )

    static let hiraginoKakuGothic = ReaderFontOption(
        id: "Hiragino Kaku Gothic ProN",
        title: "Hiragino Kaku Gothic ProN",
        cssFontFamily: "\"Hiragino Kaku Gothic ProN\", \"Apple SD Gothic Neo\", sans-serif"
    )

    static let builtIn: [ReaderFontOption] = [
        .system, .appleSDGothicNeo, .appleGothic, .hiraginoMincho, .hiraginoKakuGothic,
    ]

    static var defaultValue: String { system.id }

    // MARK: - Imported Fonts

    /// Create an option for a user-imported font.
    static func imported(postScriptName: String, displayName: String) -> ReaderFontOption {
        let koreanFallback = "\"Apple SD Gothic Neo\", \"AppleGothic\""
        return ReaderFontOption(
            id: postScriptName,
            title: displayName,
            cssFontFamily: "\"\(postScriptName)\", \(koreanFallback), sans-serif"
        )
    }

    // MARK: - All options (dynamic)

    static var all: [ReaderFontOption] {
        var options = builtIn
        let imported = FontImportManager.shared.importedFontNames
        for name in imported {
            let display = FontImportManager.shared.displayName(for: name)
            options.append(.imported(postScriptName: name, displayName: display))
        }
        return options
    }

    // MARK: - Resolution

    static func resolved(_ id: String) -> ReaderFontOption {
        // Check built-in first
        if let builtIn = builtIn.first(where: { $0.id == id }) {
            return builtIn
        }
        // Check imported
        if FontImportManager.shared.importedFontNames.contains(id) {
            let display = FontImportManager.shared.displayName(for: id)
            return .imported(postScriptName: id, displayName: display)
        }
        return .system
    }
}
