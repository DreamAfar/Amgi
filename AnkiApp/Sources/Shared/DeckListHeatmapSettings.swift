import Foundation

enum DeckListHeatmapScope: String, CaseIterable, Identifiable {
    case allDecks = "all"
    case selectedDeck = "selected"

    var id: String { rawValue }
}

enum DeckListHeatmapSettings {
    static let showKey = "show_deck_list_heatmap"
    static let heightKey = "deck_list_heatmap_height"
    static let scopeKey = "deck_list_heatmap_scope"
    static let selectedDeckIDKey = "deck_list_heatmap_selected_deck_id"

    static let defaultHeight = 164.0
    static let defaultSelectedDeckID = 0
    static let allDecksSearch = "deck:*"
}