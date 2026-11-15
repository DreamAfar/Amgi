//
//  BrowseFilters.swift
//  BrowseFeature
//

import AnkiKit
import Foundation

/// What a Browse search depends on besides the collection: the assembled
/// query and the order. Used as the `.task(id:)` key.
struct BrowseSearchKey: Hashable {
    var query: String
    var sort: NoteSortOrder
}

/// The filters of Browse's sort & filter menu. Each group holds at most one
/// choice and contributes one term of Anki's search syntax, so they combine
/// with the deck and tag chips and the typed search like any other term.
struct BrowseFilters: Equatable {
    var state: CardState?
    var flag: Int?
    var notetypeID: NotetypeID?
    var recent: Recent?

    enum CardState: String, CaseIterable, Sendable {
        case new, learning, review, due, suspended, buried

        var searchTerm: String {
            switch self {
            case .new: "is:new"
            case .learning: "is:learn"
            case .review: "is:review"
            case .due: "is:due"
            case .suspended: "is:suspended"
            case .buried: "is:buried"
            }
        }

        var title: String {
            switch self {
            case .new: String(localized: "New", bundle: .module)
            case .learning: String(localized: "Learning", bundle: .module)
            case .review: String(localized: "Review", bundle: .module)
            case .due: String(localized: "Due", bundle: .module)
            case .suspended: String(localized: "Suspended", bundle: .module)
            case .buried: String(localized: "Buried", bundle: .module)
            }
        }
    }

    enum Recent: String, CaseIterable, Sendable {
        case addedToday, addedThisWeek, editedToday, studiedToday, againToday

        var searchTerm: String {
            switch self {
            case .addedToday: "added:1"
            case .addedThisWeek: "added:7"
            case .editedToday: "edited:1"
            case .studiedToday: "rated:1"
            case .againToday: "rated:1:1"
            }
        }

        var title: String {
            switch self {
            case .addedToday: String(localized: "Added Today", bundle: .module)
            case .addedThisWeek: String(localized: "Added in the Last 7 Days", bundle: .module)
            case .editedToday: String(localized: "Edited Today", bundle: .module)
            case .studiedToday: String(localized: "Studied Today", bundle: .module)
            case .againToday: String(localized: "Answered Again Today", bundle: .module)
            }
        }
    }

    /// Flags 1–7 by Anki's numbering; 0 means "no flag".
    static let flags = Array(0...7)

    static func flagTitle(_ flag: Int) -> String {
        switch flag {
        case 1: String(localized: "Red flag", bundle: .module)
        case 2: String(localized: "Orange flag", bundle: .module)
        case 3: String(localized: "Green flag", bundle: .module)
        case 4: String(localized: "Blue flag", bundle: .module)
        case 5: String(localized: "Pink flag", bundle: .module)
        case 6: String(localized: "Turquoise flag", bundle: .module)
        case 7: String(localized: "Purple flag", bundle: .module)
        default: String(localized: "No Flag", bundle: .module)
        }
    }

    var isActive: Bool { self != BrowseFilters() }

    var searchTerms: [String] {
        var terms: [String] = []
        if let state { terms.append(state.searchTerm) }
        if let flag { terms.append("flag:\(flag)") }
        if let notetypeID { terms.append("mid:\(notetypeID.rawValue)") }
        if let recent { terms.append(recent.searchTerm) }
        return terms
    }
}

extension NoteSortColumn {
    var title: String {
        switch self {
        case .sortField: String(localized: "Sort Field", bundle: .module)
        case .created: String(localized: "Created", bundle: .module)
        case .modified: String(localized: "Modified", bundle: .module)
        case .notetype: String(localized: "Note Type", bundle: .module)
        case .deck: String(localized: "Deck", bundle: .module)
        case .tags: String(localized: "Tags", bundle: .module)
        case .cardCount: String(localized: "Number of Cards", bundle: .module)
        case .due: String(localized: "Due", bundle: .module)
        case .interval: String(localized: "Interval", bundle: .module)
        case .ease: String(localized: "Ease", bundle: .module)
        case .reviews: String(localized: "Reviews", bundle: .module)
        case .lapses: String(localized: "Lapses", bundle: .module)
        }
    }
}
