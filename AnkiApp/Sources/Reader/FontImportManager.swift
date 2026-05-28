import CoreText
import Foundation
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.ankiapp.reader", category: "FontImport")

/// Manages user-imported fonts: register, persist, list, remove.
@MainActor
final class FontImportManager: ObservableObject, Sendable {
    static let shared = FontImportManager()

    private static let importedFontsKey = "ReaderImportedFonts"

    /// PostScript names of currently imported fonts.
    @Published private(set) var importedFontNames: [String] = []

    private var fontsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        loadPersistedFonts()
    }

    // MARK: - Persistence

    private func loadPersistedFonts() {
        let names = UserDefaults.standard.stringArray(forKey: Self.importedFontsKey) ?? []
        var valid: [String] = []
        for name in names {
            let url = fontsDirectory.appendingPathComponent(fontFileName(for: name))
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if registerFont(at: url) {
                valid.append(name)
            } else {
                logger.warning("Failed to re-register font: \(name)")
            }
        }
        importedFontNames = valid
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(importedFontNames, forKey: Self.importedFontsKey)
    }

    // MARK: - Registration

    private func fontFileName(for postScriptName: String) -> String {
        "\(postScriptName.replacingOccurrences(of: " ", with: "_")).ttf"
    }

    private func registerFont(at url: URL) -> Bool {
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            logger.error("Cannot create data provider for \(url.lastPathComponent)")
            return false
        }
        guard let cgFont = CGFont(dataProvider) else {
            logger.error("Cannot create CGFont from \(url.lastPathComponent)")
            return false
        }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterGraphicsFont(cgFont, &error) {
            return true
        }
        if let error = error?.takeRetainedValue() {
            // If already registered, that's fine
            if CFErrorGetDomain(error) == kCTFontManagerErrorDomain,
               CTFontManagerError(rawValue: CFErrorGetCode(error)) == .alreadyRegistered {
                return true
            }
            logger.error("CTFontManager error: \(error)")
        }
        return false
    }

    // MARK: - Import

    /// Import a font from a security-scoped URL, copy to app storage, and register.
    func importFont(from sourceURL: URL) throws -> String {
        let needsRelease = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsRelease { sourceURL.stopAccessingSecurityScopedResource() } }

        // Read font to get PostScript name
        guard let dataProvider = CGDataProvider(url: sourceURL as CFURL),
              let cgFont = CGFont(dataProvider),
              let postScriptName = cgFont.postScriptName as String? else {
            throw FontImportError.invalidFont
        }

        let destURL = fontsDirectory.appendingPathComponent(fontFileName(for: postScriptName))

        // Copy to app storage
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Register
        guard registerFont(at: destURL) else {
            try? FileManager.default.removeItem(at: destURL)
            throw FontImportError.registrationFailed
        }

        // Persist
        if !importedFontNames.contains(postScriptName) {
            importedFontNames.append(postScriptName)
            persist()
        }

        logger.info("Imported font: \(postScriptName)")
        return postScriptName
    }

    /// Remove an imported font.
    func removeFont(named postScriptName: String) {
        let url = fontsDirectory.appendingPathComponent(fontFileName(for: postScriptName))
        try? FileManager.default.removeItem(at: url)

        // Unregister
        if let dataProvider = CGDataProvider(url: url as CFURL),
           let cgFont = CGFont(dataProvider) {
            CTFontManagerUnregisterGraphicsFont(cgFont, nil)
        }

        importedFontNames.removeAll { $0 == postScriptName }
        persist()
        logger.info("Removed font: \(postScriptName)")
    }

    // MARK: - Query

    /// Display name for an imported font.
    func displayName(for postScriptName: String) -> String {
        let url = fontsDirectory.appendingPathComponent(fontFileName(for: postScriptName))
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(dataProvider),
              let fullName = cgFont.fullName as String? else {
            return postScriptName
        }
        return fullName
    }
}

enum FontImportError: LocalizedError {
    case invalidFont
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFont: return "The selected file is not a valid font."
        case .registrationFailed: return "Failed to register the font with the system."
        }
    }
}
