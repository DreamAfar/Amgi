//
//  RichTextCommand.swift
//  BrowseFeature
//

import Foundation

/// A formatting action of the note field editor, and the script that runs
/// it in the field's page (`RichFieldPage`). The page applies these with
/// the browser's own editing commands, so the stored HTML is what Anki's
/// desktop editor writes for the same action: `<b>`, `<i>`, `<u>`,
/// `<sub>`, `<font color>`, `<ul><li>`, `<div style="text-align: …">`.
enum RichTextCommand: Equatable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case subscriptText
    case superscriptText
    /// A CSS color, e.g. `#e53935`.
    case textColor(String)
    /// A CSS color, or nil to remove the highlight.
    case highlight(String?)
    case bulletList
    case numberedList
    case align(RichTextAlignment)
    case clearFormatting
    case math(RichTextMath)
    case insertImage(filename: String)
    case undo
    case redo

    var script: String {
        switch self {
        case .bold: Self.exec("bold")
        case .italic: Self.exec("italic")
        case .underline: Self.exec("underline")
        case .strikethrough: Self.exec("strikeThrough")
        case .subscriptText: Self.exec("subscript")
        case .superscriptText: Self.exec("superscript")
        case .textColor(let color): Self.exec("foreColor", color)
        case .highlight(let color): Self.exec("hiliteColor", color ?? "transparent")
        case .bulletList: Self.exec("insertUnorderedList")
        case .numberedList: Self.exec("insertOrderedList")
        case .align(let alignment): Self.exec(alignment.command)
        case .clearFormatting: Self.exec("removeFormat")
        case .math(let math):
            "amgi.wrap(\(Self.literal(math.delimiters.open)), \(Self.literal(math.delimiters.close)))"
        case .insertImage(let filename): "amgi.insertImage(\(Self.literal(filename)))"
        case .undo: Self.exec("undo")
        case .redo: Self.exec("redo")
        }
    }

    private static func exec(_ command: String, _ value: String? = nil) -> String {
        if let value {
            "amgi.exec(\(literal(command)), \(literal(value)))"
        } else {
            "amgi.exec(\(literal(command)))"
        }
    }

    /// A string as a JavaScript literal. JSON string syntax is a subset of
    /// JavaScript's, so the JSON encoding is safe to splice into a script
    /// whatever the string contains.
    static func literal(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }
}

enum RichTextAlignment: String, CaseIterable, Sendable {
    case left, center, right

    var command: String {
        switch self {
        case .left: "justifyLeft"
        case .center: "justifyCenter"
        case .right: "justifyRight"
        }
    }

    var symbol: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        }
    }
}

/// MathJax delimiters, as Anki stores them in a field.
enum RichTextMath: CaseIterable, Sendable {
    case inline
    case block
    case chemistry

    var delimiters: (open: String, close: String) {
        switch self {
        case .inline: (#"\("#, #"\)"#)
        case .block: (#"\["#, #"\]"#)
        case .chemistry: (#"\(\ce{"#, #"}\)"#)
        }
    }
}

/// Which formats apply at the caret, reported by the page so the toolbar
/// can show its toggles as on.
struct RichTextFormatting: Equatable, Sendable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var subscriptText = false
    var superscriptText = false
    var bulletList = false
    var numberedList = false
    var alignment = RichTextAlignment.left

    init() {}

    /// From the page's `state` message.
    init(message: [String: Any]) {
        bold = message["bold"] as? Bool ?? false
        italic = message["italic"] as? Bool ?? false
        underline = message["underline"] as? Bool ?? false
        strikethrough = message["strike"] as? Bool ?? false
        subscriptText = message["sub"] as? Bool ?? false
        superscriptText = message["sup"] as? Bool ?? false
        bulletList = message["ul"] as? Bool ?? false
        numberedList = message["ol"] as? Bool ?? false
        alignment = (message["align"] as? String).flatMap(RichTextAlignment.init(rawValue:)) ?? .left
    }
}
