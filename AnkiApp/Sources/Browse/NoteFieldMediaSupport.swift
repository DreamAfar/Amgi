import Foundation
import UniformTypeIdentifiers

enum NoteFieldMediaSupport {
    static let importableTypes: [UTType] = [.image, .audio, .movie, .data]

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
