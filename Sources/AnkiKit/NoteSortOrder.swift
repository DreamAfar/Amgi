//
//  NoteSortOrder.swift
//  AnkiKit
//

/// A column Anki's backend can order a note search by. The raw value is the
/// backend's key for the column (`rslib` `browser_table::Column`).
public enum NoteSortColumn: String, CaseIterable, Sendable {
    case sortField = "noteFld"
    case created = "noteCrt"
    case modified = "noteMod"
    case notetype = "note"
    case deck = "deck"
    case tags = "noteTags"
    case cardCount = "template"
    case due = "cardDue"
    case interval = "cardIvl"
    case ease = "cardEase"
    case reviews = "cardReps"
    case lapses = "cardLapses"
}

/// How a note search is ordered. Sorting happens in the backend's query, so
/// it covers every match rather than only the rows loaded so far.
public struct NoteSortOrder: Hashable, Sendable {
    public var column: NoteSortColumn
    public var descending: Bool

    public init(column: NoteSortColumn, descending: Bool) {
        self.column = column
        self.descending = descending
    }

    /// Most recently modified first.
    public static let modifiedNewestFirst = NoteSortOrder(column: .modified, descending: true)
}
