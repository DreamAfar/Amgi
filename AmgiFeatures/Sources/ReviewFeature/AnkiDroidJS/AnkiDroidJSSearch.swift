//
//  AnkiDroidJSSearch.swift
//  ReviewFeature
//

import AnkiKit
import BrowseFeature
import Foundation
import SwiftUI

/// A card script's `ankiSearchCard`: the browser, opened on its query.
struct AnkiDroidJSBrowseRequest: Identifiable, Equatable {
    let id = UUID()
    let query: String
}

private struct AnkiDroidJSBrowseSheet: ViewModifier {
    @Binding var request: AnkiDroidJSBrowseRequest?

    func body(content: Content) -> some View {
        content.sheet(item: $request) { request in
            NavigationStack {
                BrowseView(searchText: request.query)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Done", bundle: .module)) { self.request = nil }
                        }
                    }
            }
        }
    }
}

extension View {
    func reviewCardScriptBrowse(_ request: Binding<AnkiDroidJSBrowseRequest?>) -> some View {
        modifier(AnkiDroidJSBrowseSheet(request: request))
    }
}

/// One card of an `ankiSearchCardWithCallback` result, in the shape
/// AnkiDroid hands a card's hook: `{cardId, noteId, fieldsData}`.
enum AnkiDroidJSSearchResult {
    /// The most notes one search returns to a script. AnkiDroid has no
    /// limit; a loose query on a large collection would otherwise serialise
    /// every note into the page.
    static let noteLimit = 100

    static func entry(cardID: CardID, note: NoteRecord, fieldNames: [String]) -> [String: Any] {
        let values = note.flds.components(separatedBy: "\u{1f}")
        var fields: [String: String] = [:]
        for (name, value) in zip(fieldNames, values) {
            fields[name] = value
        }
        return [
            "cardId": cardID.rawValue,
            "noteId": note.id.rawValue,
            "fieldsData": fields,
        ]
    }
}
