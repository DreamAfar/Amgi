import Foundation
import UniformTypeIdentifiers

enum NoteFieldMediaSupport {
    static let importableTypes: [UTType] = [.image, .audio, .movie, .data]
    private static let firstImagePattern = #"<img[^>]*src\s*=\s*"([^"]+)"[^>]*>"#

    static func suggestedFilename(
        sourceURL: URL? = nil,
        contentType: UTType?,
        fallbackPrefix: String
    ) -> String {
        let baseName: String
        if let sourceURL {
            baseName = sourceURL.lastPathComponent
        } else {
            baseName = "\(fallbackPrefix)-\(Int(Date().timeIntervalSince1970))"
        }

        guard let contentType else { return baseName }
        guard sourceURL?.pathExtension.isEmpty ?? true else { return baseName }
        guard let ext = contentType.preferredFilenameExtension else { return baseName }
        return "\(baseName).\(ext)"
    }

    static func markup(for filename: String, contentType: UTType?) -> String {
        let resolvedContentType = contentType ?? UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
        let escapedName = filename
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        if let resolvedContentType {
            if resolvedContentType.conforms(to: .image) {
                return #"<img src="\#(escapedName)">"#
            }
            if resolvedContentType.conforms(to: .audio) || resolvedContentType.conforms(to: .movie) {
                return "[sound:\(filename)]"
            }
        }

        return #"<a href="\#(escapedName)">\#(escapedName)</a>"#
    }

    static func separator(for existingValue: String, markup: String) -> String {
        guard existingValue.isEmpty == false else { return "" }
        if markup.hasPrefix("<img") || markup.hasPrefix("<a ") {
            return "<br>"
        }
        return " "
    }

    static func shouldOptimizeImage(
        contentType: UTType?,
        filename: String
    ) -> Bool {
        let resolvedContentType = contentType ?? UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension)
        return resolvedContentType?.conforms(to: .image) == true
    }

    static func firstImageFilename(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: firstImagePattern, options: [.caseInsensitive]) else {
            return nil
        }
        let source = html as NSString
        guard
            let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: source.length)),
            match.numberOfRanges > 1
        else {
            return nil
        }
        let value = source.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func replacingFirstImageFilename(
        in html: String,
        oldFilename: String,
        newFilename: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: firstImagePattern, options: [.caseInsensitive]) else {
            return html
        }
        let source = html as NSString
        guard
            let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: source.length)),
            match.numberOfRanges > 1
        else {
            return html
        }

        let current = source.substring(with: match.range(at: 1))
        guard current == oldFilename else { return html }
        return source.replacingCharacters(in: match.range(at: 1), with: newFilename)
    }
}

enum MediaImportError: LocalizedError {
    case loadFailed
    case noTargetField

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return L("note_editor_media_import_load_failed")
        case .noTargetField:
            return L("note_editor_media_import_target_missing")
        }
    }
}
