import Foundation
import SwiftUI

// MARK: - LanguageManager

/// Manages the active language bundle for in-app locale switching.
/// Language preference is persisted via AppStorage("app_language").
///
/// Usage in views:
///   Text(L("key_name"))
///   Text(L("greeting", "Alice"))   // with interpolation
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var bundle: Bundle = .main

    private init() {
        applyStoredLanguage()
    }

    func apply(_ language: AppLanguage) {
        switch language {
        case .system:
            bundle = .main
        default:
            if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
               let b = Bundle(path: path) {
                bundle = b
            } else {
                // Fall back to main bundle if lproj not found
                bundle = .main
            }
        }
    }

    private func applyStoredLanguage() {
        let raw = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.system.rawValue
        apply(AppLanguage(rawValue: raw) ?? .system)
    }
}

// MARK: - Localization helper

/// Returns the localized string for `key` using the active LanguageManager bundle.
/// Falls back to the key itself if no translation is found.
@MainActor
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: LanguageManager.shared.bundle, comment: "")
}

/// Convenience overload for simple string interpolation.
/// Example: `L("deck_count_format", deck.count)` → "3 Decks"
@MainActor
func L(_ key: String, _ args: CVarArg...) -> String {
    let fmt = NSLocalizedString(key, bundle: LanguageManager.shared.bundle, comment: "")
    return String(format: fmt, arguments: args)
}
