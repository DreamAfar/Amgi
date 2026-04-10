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

    /// Thread-safe static bundle used by L() functions.
    /// Initialized from UserDefaults at static access time so language is
    /// correct from the very first L() call, even before LanguageManager.shared is created.
    nonisolated(unsafe) static var currentBundle: Bundle = LanguageManager.resolveInitialBundle()

    /// Reads the stored app_language preference from UserDefaults and returns
    /// the matching Bundle without touching any @MainActor state.
    private nonisolated static func resolveInitialBundle() -> Bundle {
        let raw = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.system.rawValue
        guard raw != AppLanguage.system.rawValue else { return .main }
        if let path = Bundle.main.path(forResource: raw, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    @Published private(set) var bundle: Bundle = LanguageManager.resolveInitialBundle() {
        didSet {
            // Keep the nonisolated static in sync with the published property
            Self.currentBundle = bundle
        }
    }

    private init() {
        // bundle is already initialized via resolveInitialBundle() above;
        // sync the currentBundle static once more in case of edge-case ordering.
        Self.currentBundle = bundle
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
}

// MARK: - Localization helper

/// Returns the localized string for `key` using the active LanguageManager bundle.
/// Falls back to the key itself if no translation is found.
/// This function is nonisolated to allow calls from any context (UI or background).
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: LanguageManager.currentBundle, comment: "")
}

/// Convenience overload for simple string interpolation.
/// Example: `L("deck_count_format", deck.count)` → "3 Decks"
/// This function is nonisolated to allow calls from any context (UI or background).
func L(_ key: String, _ args: CVarArg...) -> String {
    let fmt = NSLocalizedString(key, bundle: LanguageManager.currentBundle, comment: "")
    return String(format: fmt, arguments: args)
}
