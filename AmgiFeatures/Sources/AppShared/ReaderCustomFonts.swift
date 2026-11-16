//
//  ReaderCustomFonts.swift
//  AppShared
//

import AppCore
import CoreText
import Foundation

/// A font file the user imported for the readers.
public struct ReaderCustomFont: Identifiable, Hashable, Sendable {
    /// The file's name in the fonts folder; unique, so it's the identity.
    public let fileName: String
    /// The font's own family name, as it should appear in pickers.
    public let displayName: String
    /// PostScript name of the first face, for previews in SwiftUI.
    public let postScriptName: String
    public let fileSize: Int64

    public var id: String { fileName }

    /// What a reader font preference stores when this font is chosen.
    public var selectionValue: String { ReaderCustomFonts.selectionPrefix + fileName }

    /// The family name the readers' `@font-face` rule declares. Derived from
    /// the file name, so two imports of fonts with the same family name
    /// don't collide.
    public var cssFamilyName: String { ReaderCustomFonts.cssFamilyName(forFileName: fileName) }
}

/// The readers' imported fonts: kept as files in Application Support, shown
/// to the readers' web views through the `amgi-reader-font` URL scheme
/// (`ReaderFontScheme`), and listed by reading the files themselves, so
/// there's no separate index to fall out of step.
///
/// A web view can't use fonts registered in the app's process, which is why
/// the readers load them with `@font-face` rather than by name.
public enum ReaderCustomFonts {
    public static let selectionPrefix = "custom:"
    public static let scheme = "amgi-reader-font"
    /// Every preference that can hold a reader font.
    public static let selectionKeys = [
        ReaderPreferences.Keys.selectedFont,
        ReaderPreferences.Keys.typographyFontFamily,
    ]

    public enum ImportError: LocalizedError {
        case notAFont(String)

        public var errorDescription: String? {
            switch self {
            case .notAFont(let name):
                String(localized: "“\(name)” isn't a font file that can be used.", bundle: .module)
            }
        }
    }

    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ReaderFonts", isDirectory: true)
    }

    /// Imported fonts, by name.
    public static func all() -> [ReaderCustomFont] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap(font(at:))
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// The imported font a preference value names, if it still exists.
    public static func font(forSelection value: String) -> ReaderCustomFont? {
        guard value.hasPrefix(selectionPrefix) else { return nil }
        let fileName = String(value.dropFirst(selectionPrefix.count))
        guard isPlainFileName(fileName) else { return nil }
        return font(at: directory.appendingPathComponent(fileName))
    }

    /// Copies a picked font file in. Refuses anything CoreText can't read
    /// as a font; a name already taken gets " 2", " 3", … before its
    /// extension.
    @discardableResult
    public static func importFont(from source: URL) throws -> ReaderCustomFont {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        guard descriptors(at: source).first != nil else {
            throw ImportError.notAFont(source.lastPathComponent)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = availableURL(for: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        guard let font = font(at: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.notAFont(source.lastPathComponent)
        }
        return font
    }

    /// Removes the file and resets any reader preference that pointed at it
    /// to the default font.
    public static func delete(_ font: ReaderCustomFont, defaults: UserDefaults = .standard) throws {
        let url = directory.appendingPathComponent(font.fileName)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try FileManager.default.removeItem(at: url)
        for key in selectionKeys where defaults.string(forKey: key) == font.selectionValue {
            defaults.removeObject(forKey: key)
        }
    }

    /// Makes the font usable by name in this process, for previews.
    public static func registerForPreview(_ font: ReaderCustomFont) {
        let url = directory.appendingPathComponent(font.fileName)
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    // MARK: - CSS

    /// The `@font-face` rule and the `font-family` value a reader page uses
    /// for a preference that names an imported font; nil for anything else,
    /// including an imported font that has since been deleted.
    ///
    /// Cheap enough to call on every render: it only checks that the file
    /// exists, without parsing it.
    public static func css(forSelection value: String, fallback: String) -> (fontFace: String, family: String)? {
        guard value.hasPrefix(selectionPrefix) else { return nil }
        let fileName = String(value.dropFirst(selectionPrefix.count))
        guard isPlainFileName(fileName),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) else { return nil }
        let family = cssFamilyName(forFileName: fileName)
        let src = "\(scheme)://fonts/" + (fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName)
        let fontFace = "@font-face { font-family: \"\(family)\"; src: url(\"\(src)\"); font-display: swap; }"
        return (fontFace, "\"\(family)\", \(fallback)")
    }

    static func cssFamilyName(forFileName fileName: String) -> String {
        "AmgiReaderFont-" + fileName.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
    }

    /// The font file a scheme request asks for. Only a plain file name in
    /// the fonts folder resolves — nothing outside it.
    public static func fileURL(forRequest url: URL) -> URL? {
        let name = url.lastPathComponent
        guard isPlainFileName(name) else { return nil }
        let file = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    public static func mimeType(forFileName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "otf": "font/otf"
        case "ttc", "otc": "font/collection"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        default: "font/ttf"
        }
    }

    // MARK: - Helpers

    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.hasPrefix(".")
    }

    private static func descriptors(at url: URL) -> [CTFontDescriptor] {
        (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
    }

    private static func font(at url: URL) -> ReaderCustomFont? {
        guard let first = descriptors(at: url).first else { return nil }
        let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String
        let display = CTFontDescriptorCopyAttribute(first, kCTFontDisplayNameAttribute) as? String
        let postScript = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ReaderCustomFont(
            fileName: url.lastPathComponent,
            displayName: family ?? display ?? url.deletingPathExtension().lastPathComponent,
            postScriptName: postScript ?? "",
            fileSize: size
        )
    }

    private static func availableURL(for fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}
