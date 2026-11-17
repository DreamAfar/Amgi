//
//  GlossaryHTML.swift
//  Reader
//

import Foundation

/// A dictionary's definitions as HTML for a note field, in the shape
/// Yomitan and Hoshi Reader export to Anki: the glossary inside a
/// `.yomitan-glossary` wrapper, followed by the dictionary's own stylesheet
/// with every rule scoped to that wrapper. The markup carries the same
/// `gloss-sc-*` classes and `data-sc-*` attributes the lookup popup renders,
/// so the dictionary's CSS styles a card the way it styles the popup.
///
/// Pure text in, text out — the popup builds its copy in a web view, but a
/// card can be made before that view exists.
public enum GlossaryHTML {
    /// One field's worth of HTML for `dictionary`'s `glossaries`.
    public static func styled(
        dictionary: String,
        glossaries: [DictionaryLookupGlossary],
        style: String
    ) -> String {
        let items = glossaries
            .map { render(content: $0.content) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return "" }

        let body = items.count == 1
            ? items[0]
            : "<ol>" + items.map { "<li>\($0)</li>" }.joined() + "</ol>"
        var html = #"<div style="text-align: left;" class="yomitan-glossary">"#
        html += #"<div data-dictionary=""# + escapeAttribute(dictionary) + #"">"#
        if !dictionary.isEmpty {
            html += "<i>(" + escapeText(dictionary) + ")</i> "
        }
        html += body + "</div>"
        let css = scopedCSS(style, dictionary: dictionary)
        if !css.isEmpty {
            html += "<style>" + css + "</style>"
        }
        return html + "</div>"
    }

    // MARK: - Structured content

    /// HTML for one glossary's stored content: a JSON structured-content
    /// tree, or plain text when it isn't JSON.
    static func render(content raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return text(raw)
        }
        return render(json, insideSpan: false)
    }

    private static let tags: Set<String> = [
        "br", "ruby", "rt", "rp", "table", "thead", "tbody", "tfoot", "tr", "td", "th",
        "span", "div", "ol", "ul", "li", "details", "summary", "a",
    ]

    private static func render(_ node: Any, insideSpan: Bool) -> String {
        switch node {
        case let string as String:
            return text(string)
        case let number as NSNumber:
            return escapeText(number.stringValue)
        case let array as [Any]:
            // A bare list of strings is a list of senses.
            let strings = array.compactMap { $0 as? String }
            if strings.count == array.count, array.count > 1, !insideSpan {
                return #"<ul class="glossary-list">"#
                    + strings.map { "<li>" + escapeText($0) + "</li>" }.joined()
                    + "</ul>"
            }
            return array.map { render($0, insideSpan: insideSpan) }.joined()
        case let object as [String: Any]:
            return render(object)
        default:
            return ""
        }
    }

    private static func render(_ node: [String: Any]) -> String {
        switch node["type"] as? String {
        case "structured-content":
            guard let content = node["content"] else { return "" }
            return #"<span class="structured-content">"# + render(content, insideSpan: true) + "</span>"
        case "text":
            return text(node["text"] as? String ?? "")
        case "image":
            return ""
        default:
            break
        }

        let requested = (node["tag"] as? String)?.lowercased() ?? "span"
        // Images live in the dictionary's own storage, not the collection's
        // media folder, so a card couldn't show them.
        if requested == "img" { return "" }
        let tag = tags.contains(requested) ? requested : "span"
        if tag == "br" { return "<br>" }

        var attributes = #" class="gloss-sc-"# + tag + "\""
        if tag == "a", let href = node["href"] as? String,
           href.lowercased().hasPrefix("http://") || href.lowercased().hasPrefix("https://") {
            attributes += #" href=""# + escapeAttribute(href) + "\""
        }
        if let title = node["title"] as? String {
            attributes += #" title=""# + escapeAttribute(title) + "\""
        }
        if let lang = node["lang"] as? String {
            attributes += #" lang=""# + escapeAttribute(lang) + "\""
        }
        if let data = node["data"] as? [String: Any] {
            for key in data.keys.sorted() {
                guard let name = dataAttributeName(key), let value = scalar(data[key]) else { continue }
                attributes += " " + name + "=\"" + escapeAttribute(value) + "\""
            }
        }
        if let style = node["style"] as? [String: Any] {
            let declarations = inlineStyle(style)
            if !declarations.isEmpty {
                attributes += #" style=""# + escapeAttribute(declarations) + "\""
            }
        }
        if let span = scalar(node["colSpan"]) { attributes += #" colspan=""# + escapeAttribute(span) + "\"" }
        if let span = scalar(node["rowSpan"]) { attributes += #" rowspan=""# + escapeAttribute(span) + "\"" }

        let inner = node["content"].map { render($0, insideSpan: tag == "span") } ?? ""
        let element = "<" + tag + attributes + ">" + inner + "</" + tag + ">"
        return tag == "table"
            ? #"<div class="gloss-sc-table-container">"# + element + "</div>"
            : element
    }

    /// `data-sc-<kebab-case>`; a key starting with a CJK character is
    /// appended as is, which some dictionaries' stylesheets rely on.
    static func dataAttributeName(_ key: String) -> String? {
        guard let first = key.unicodeScalars.first else { return nil }
        let isCJK = (0x3000...0x9FFF).contains(first.value) || (0xF900...0xFAFF).contains(first.value)
        let name = "data-sc" + (isCJK ? "" : "-") + kebabCase(key)
        let valid = name.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F: true
            case 0x3000...0x9FFF, 0xF900...0xFAFF: true
            default: false
            }
        }
        return valid ? name : nil
    }

    static func kebabCase(_ text: String) -> String {
        var result = ""
        for (index, character) in text.enumerated() {
            if character.isUppercase, character.isASCII {
                if index > 0 { result += "-" }
                result += character.lowercased()
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func inlineStyle(_ style: [String: Any]) -> String {
        style.keys.sorted().compactMap { key -> String? in
            let property = kebabCase(key)
            guard property.unicodeScalars.allSatisfy({ (0x61...0x7A).contains($0.value) || $0.value == 0x2D }) else {
                return nil
            }
            let value: String
            if let list = style[key] as? [Any] {
                value = list.compactMap(scalar).joined(separator: " ")
            } else if let single = scalar(style[key]) {
                value = single
            } else {
                return nil
            }
            // One declaration only: nothing that could end it and start another.
            guard !value.isEmpty, !value.contains(where: { ";{}<>".contains($0) }) else { return nil }
            return property + ": " + value + ";"
        }
        .joined(separator: " ")
    }

    private static func scalar(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func text(_ string: String) -> String {
        string.components(separatedBy: .newlines).map(escapeText).joined(separator: "<br>")
    }

    static func escapeText(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ string: String) -> String {
        escapeText(string).replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Stylesheet

    /// `css` with every rule's selectors under
    /// `.yomitan-glossary [data-dictionary="…"]`, so a dictionary's styles
    /// reach only its own definitions on a card. Rules inside `@media` and
    /// its kin are scoped too; `@import` and other statements are dropped.
    public static func scopedCSS(_ css: String, dictionary: String) -> String {
        let prefix = #".yomitan-glossary [data-dictionary=""#
            + dictionary.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            + "\"]"
        // A field's `<style>` ends at the first `</style`, wherever it is.
        let safe = stripComments(css).replacingOccurrences(of: "</", with: "<\\/")
        return scope(rules: Array(safe), prefix: prefix)
    }

    private static let nestingAtRules: Set<String> = ["@media", "@supports", "@layer", "@container", "@document"]
    private static let verbatimAtRules: Set<String> = [
        "@font-face", "@keyframes", "@-webkit-keyframes", "@page", "@property", "@counter-style",
    ]

    private static func scope(rules: [Character], prefix: String) -> String {
        var output: [String] = []
        var index = 0
        while index < rules.count {
            // The prelude runs to this rule's `{`, or to a `;` for a statement.
            var prelude = ""
            var quote: Character?
            var opened = false
            while index < rules.count {
                let character = rules[index]
                if let open = quote {
                    if character == "\\", index + 1 < rules.count {
                        prelude.append(character)
                        prelude.append(rules[index + 1])
                        index += 2
                        continue
                    }
                    if character == open { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "{" {
                    opened = true
                    index += 1
                    break
                } else if character == ";" || character == "}" {
                    index += 1
                    break
                }
                prelude.append(character)
                index += 1
            }
            guard opened else { continue }

            // The body runs to the matching `}`.
            var body = ""
            var depth = 1
            quote = nil
            while index < rules.count {
                let character = rules[index]
                if let open = quote {
                    if character == "\\", index + 1 < rules.count {
                        body.append(character)
                        body.append(rules[index + 1])
                        index += 2
                        continue
                    }
                    if character == open { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        break
                    }
                }
                body.append(character)
                index += 1
            }

            let head = collapse(prelude)
            guard !head.isEmpty else { continue }
            if head.hasPrefix("@") {
                let name = head.prefix { !$0.isWhitespace && $0 != "(" }.lowercased()
                if nestingAtRules.contains(name) {
                    output.append(head + " { " + scope(rules: Array(body), prefix: prefix) + " }")
                } else if verbatimAtRules.contains(name) {
                    output.append(head + " { " + collapse(body) + " }")
                }
                continue
            }
            let selectors = splitSelectors(head).map { selector -> String in
                let lowered = selector.lowercased()
                return lowered == ":root" || lowered == "html" || lowered == "body" ? prefix : prefix + " " + selector
            }
            guard !selectors.isEmpty else { continue }
            output.append(selectors.joined(separator: ", ") + " { " + collapse(body) + " }")
        }
        return output.joined(separator: "\n")
    }

    /// A selector list split at its top-level commas — not the ones inside
    /// `:is(a, b)`, `[x="a,b"]` or a string.
    private static func splitSelectors(_ list: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in list {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" || character == "[" {
                depth += 1
            } else if character == ")" || character == "]" {
                depth = max(0, depth - 1)
            } else if character == ",", depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func stripComments(_ css: String) -> String {
        var result = ""
        var rest = Substring(css)
        while let start = rest.range(of: "/*") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].range(of: "*/") else { return result }
            rest = rest[end.upperBound...]
        }
        return result + rest
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
