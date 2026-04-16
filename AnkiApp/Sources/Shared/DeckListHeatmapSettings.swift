import Foundation

enum DeckListHeatmapScope: String, CaseIterable, Identifiable {
    case allDecks = "all"
    case selectedDeck = "selected"

    var id: String { rawValue }
}

/// Controls how many days of history are loaded on the initial heatmap render.
enum HeatmapInitialDays: Int, CaseIterable, Identifiable {
    case threeMonths = 90
    case sixMonths   = 180
    case oneYear     = 365
    case allHistory  = 0

    var id: Int { rawValue }

    var localizedLabel: String {
        switch self {
        case .threeMonths: return L("heatmap_range_3_months")
        case .sixMonths:   return L("heatmap_range_6_months")
        case .oneYear:     return L("heatmap_range_1_year")
        case .allHistory:  return L("heatmap_range_all")
        }
    }
}

enum DeckListHeatmapSettings {
    static let showKey = "show_deck_list_heatmap"
    static let heightKey = "deck_list_heatmap_height"
    static let scopeKey = "deck_list_heatmap_scope"
    static let selectedDeckIDKey = "deck_list_heatmap_selected_deck_id"
    static let initialDaysKey = "deck_list_heatmap_initial_days"

    static let defaultHeight = 164.0
    static let defaultSelectedDeckID = 0
    static let defaultInitialDays = HeatmapInitialDays.sixMonths.rawValue
    static let allDecksSearch = "deck:*"
}