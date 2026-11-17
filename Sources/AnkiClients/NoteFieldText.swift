//
//  NoteFieldText.swift
//  AnkiClients
//

import Foundation

/// Plain text made ready for a note field. A field is HTML: line breaks in
/// plain text collapse to spaces there, and `<` or `&` would be read as
/// markup.
public enum NoteFieldText {
    /// `text` escaped, with its line breaks kept as `<br>`.
    public static func html(fromPlain text: String) -> String {
        lines(of: text).map(escape).joined(separator: "<br>")
    }

    /// An AI explanation as HTML: the plain-text conventions models write in
    /// — `【section】` and `#` headings, `**bold**`, `-` bullets — become bold
    /// headings, bold runs and bullet marks, each on its own line.
    public static func html(fromExplanation text: String) -> String {
        lines(of: text).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "" }
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                return "<b>" + inline(title) + "</b>"
            }
            if trimmed.hasPrefix("【"), let end = trimmed.firstIndex(of: "】") {
                let heading = String(trimmed[...end])
                let rest = String(trimmed[trimmed.index(after: end)...])
                return "<b>" + escape(heading) + "</b>" + inline(rest)
            }
            for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
                return "• " + inline(String(trimmed.dropFirst(marker.count)))
            }
            return inline(trimmed)
        }
        .joined(separator: "<br>")
    }

    /// Escapes `text` and turns `**bold**` runs into `<b>`.
    private static func inline(_ text: String) -> String {
        let parts = text.components(separatedBy: "**")
        // An odd count means every `**` has its partner.
        guard parts.count >= 3, parts.count % 2 == 1 else { return escape(text) }
        return parts.enumerated()
            .map { index, part in index % 2 == 1 ? "<b>" + escape(part) + "</b>" : escape(part) }
            .joined()
    }

    private static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
