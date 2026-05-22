import Foundation

enum TTSTextSanitizer {
    private static let hiddenContentRegex = try! NSRegularExpression(
        pattern: #"(?is)<!--.*?-->|<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>"#
    )

    private static let lineBreakTagRegex = try! NSRegularExpression(
        pattern: #"(?is)</?\s*(?:br|address|article|aside|blockquote|canvas|dd|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|li|main|nav|noscript|ol|output|p|pre|section|table|tfoot|tr|td|th|ul|video)\b[^>]*>"#
    )

    private static let htmlTagRegex = try! NSRegularExpression(
        pattern: #"(?is)<[^>]+>"#
    )

    private static let htmlLikeRegex = try! NSRegularExpression(
        pattern: #"(?is)<!--|<script\b|<style\b|</?[a-z][^>]*>|&#?[a-z0-9]+;"#
    )

    private static let numericEntityRegex = try! NSRegularExpression(
        pattern: #"&#(x?[0-9A-Fa-f]+);"#
    )

    static func sanitizedText(from source: String) -> String {
        guard source.isEmpty == false else {
            return ""
        }

        var sanitized = containsHTMLMarkup(source) ? stripHTMLPreservingBreaks(from: source) : source
        sanitized = decodeEntities(in: sanitized)

        // Handle escaped markup like "&lt;br&gt;" after entity decoding.
        if containsHTMLMarkup(sanitized) {
            sanitized = decodeEntities(in: stripHTMLPreservingBreaks(from: sanitized))
        }

        return collapseWhitespace(in: sanitized)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsHTMLMarkup(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return htmlLikeRegex.firstMatch(in: text, range: range) != nil
    }

    private static func stripHTMLPreservingBreaks(from html: String) -> String {
        let fullRange = NSRange(html.startIndex..., in: html)
        let withoutHiddenContent = hiddenContentRegex.stringByReplacingMatches(
            in: html,
            range: fullRange,
            withTemplate: ""
        )
        let hiddenContentRange = NSRange(withoutHiddenContent.startIndex..., in: withoutHiddenContent)
        let withPreservedBreaks = lineBreakTagRegex.stringByReplacingMatches(
            in: withoutHiddenContent,
            range: hiddenContentRange,
            withTemplate: " "
        )
        let breakRange = NSRange(withPreservedBreaks.startIndex..., in: withPreservedBreaks)
        return htmlTagRegex.stringByReplacingMatches(
            in: withPreservedBreaks,
            range: breakRange,
            withTemplate: ""
        )
    }

    private static func decodeEntities(in text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        let matches = numericEntityRegex.matches(
            in: decoded,
            range: NSRange(decoded.startIndex..., in: decoded)
        )

        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                  let fullRange = Range(match.range(at: 0), in: decoded),
                  let valueRange = Range(match.range(at: 1), in: decoded) else {
                continue
            }

            let rawValue = String(decoded[valueRange])
            let scalarValue: UInt32?
            if rawValue.lowercased().hasPrefix("x") {
                scalarValue = UInt32(rawValue.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(rawValue, radix: 10)
            }

            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }

            decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return decoded
    }

    private static func collapseWhitespace(in text: String) -> String {
        text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }
}
