//
//  ReaderFieldSlot.swift
//  Reader
//

import Foundation

/// One row of the reader's field mapping: the role a notetype field plays
/// when notes are assembled into books and chapters.
public enum ReaderFieldSlot: String, CaseIterable, Sendable, Hashable {
    case bookID
    case bookTitle
    case bookCover
    case chapterTitle
    case chapterOrder
    case content
    case language

    /// Cover and language may be left unmapped; every other slot has to
    /// point at a field before the library loads.
    public var isOptional: Bool {
        switch self {
        case .bookCover, .language: true
        default: false
        }
    }

    /// Lowercased field names that clearly fill this slot. Checked against
    /// every field before any `containsHints`, so an exact "Title" wins over
    /// a field that merely mentions it.
    var exactHints: [String] {
        switch self {
        case .bookID: ["book id", "bookid", "book_id", "书籍id", "书id", "書籍id"]
        case .bookTitle: ["book title", "booktitle", "book_title", "title", "book", "书名", "標題", "标题", "書名"]
        case .bookCover: ["cover", "book cover", "封面"]
        case .chapterTitle: ["chapter title", "chaptertitle", "chapter_title", "chapter", "章节标题", "章节", "章節標題", "章節"]
        case .chapterOrder: ["chapter order", "chapterorder", "chapter_order", "order", "index", "number", "序号", "顺序", "序號", "順序"]
        case .content: ["content", "text", "body", "正文", "内容", "內容"]
        case .language: ["language", "lang", "语言", "語言"]
        }
    }

    /// Fallback substrings for names like "Chapter Number" or "Book Cover Image".
    var containsHints: [String] {
        switch self {
        case .bookID: ["book id", "bookid", "book_id"]
        case .bookTitle: ["title", "书名"]
        case .bookCover: ["cover", "封面"]
        case .chapterTitle: ["chapter", "章节", "章節"]
        case .chapterOrder: ["order", "index", "number", "序号", "顺序"]
        case .content: ["content", "text", "body", "正文", "内容"]
        case .language: ["language", "语言"]
        }
    }

    /// Guesses a field for each slot from the notetype's field names. Each
    /// field is used at most once, and a slot with no convincing candidate
    /// is left out so the caller keeps whatever is already set.
    public static func guessMapping(fieldNames: [String]) -> [ReaderFieldSlot: String] {
        var result: [ReaderFieldSlot: String] = [:]
        var used = Set<String>()
        let normalized = fieldNames.map {
            ($0, $0.trimmingCharacters(in: .whitespaces).lowercased())
        }

        for slot in allCases {
            if let match = normalized.first(where: { !used.contains($0.0) && slot.exactHints.contains($0.1) }) {
                result[slot] = match.0
                used.insert(match.0)
            }
        }
        // Specific slots first, so "Chapter Number" is taken as the order
        // before the broader "chapter" hint can claim it as the title.
        let fallbackOrder: [ReaderFieldSlot] = [.bookID, .chapterOrder, .bookCover, .language, .content, .bookTitle, .chapterTitle]
        for slot in fallbackOrder where result[slot] == nil {
            let match = normalized.first { field in
                !used.contains(field.0) && slot.containsHints.contains { field.1.contains($0) }
            }
            if let match {
                result[slot] = match.0
                used.insert(match.0)
            }
        }
        return result
    }
}
