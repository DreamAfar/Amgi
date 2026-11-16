//
//  BrowseView+Search.swift
//  BrowseFeature
//

import SwiftUI

extension BrowseView {
    /// The browser opened on a search, for callers that hand the user over
    /// to it with a query already typed — a card script's `ankiSearchCard`.
    package init(searchText: String) {
        let model = BrowseModel()
        model.searchText = searchText
        self.init(model: model)
    }
}
