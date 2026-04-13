import SwiftUI
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf

struct DeckListHeatmapCard: View {
    @Dependency(\.statsClient) var statsClient
    @Dependency(\.deckClient) var deckClient
    @AppStorage(DeckListHeatmapSettings.heightKey) private var deckListHeatmapHeight = DeckListHeatmapSettings.defaultHeight
    @AppStorage(DeckListHeatmapSettings.scopeKey) private var heatmapScopeRaw = DeckListHeatmapScope.allDecks.rawValue
    @AppStorage(DeckListHeatmapSettings.selectedDeckIDKey) private var selectedDeckID = DeckListHeatmapSettings.defaultSelectedDeckID

    let refreshID: Int

    @State private var graphs: Anki_Stats_GraphsResponse?
    @State private var isLoading = true
    @State private var loadError = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView(L("stats_loading"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if let graphs {
                HeatmapChart(reviews: graphs.reviews, compactHeight: deckListHeatmapHeight)
            } else if loadError {
                ContentUnavailableView(
                    L("deck_list_heatmap_title"),
                    systemImage: "chart.bar.xaxis",
                    description: Text(L("deck_list_heatmap_load_failed"))
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task(id: refreshID) {
            await loadStats()
        }
    }

    @MainActor
    private func loadStats() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try statsClient.fetchGraphs(resolvedSearchQuery(), StatsPeriod.all.requestDays)
            graphs = try Anki_Stats_GraphsResponse(serializedBytes: data)
            loadError = false
        } catch {
            graphs = nil
            loadError = true
        }
    }

    @MainActor
    private func resolvedSearchQuery() throws -> String {
        let scope = DeckListHeatmapScope(rawValue: heatmapScopeRaw) ?? .allDecks
        guard scope == .selectedDeck else {
            return DeckListHeatmapSettings.allDecksSearch
        }

        let selectedID = Int64(selectedDeckID)
        guard selectedID > 0 else {
            heatmapScopeRaw = DeckListHeatmapScope.allDecks.rawValue
            return DeckListHeatmapSettings.allDecksSearch
        }

        let availableDeckIDs = Set(try deckClient.fetchAll().map(\.id))
        guard availableDeckIDs.contains(selectedID) else {
            heatmapScopeRaw = DeckListHeatmapScope.allDecks.rawValue
            selectedDeckID = DeckListHeatmapSettings.defaultSelectedDeckID
            return DeckListHeatmapSettings.allDecksSearch
        }

        return "did:\(selectedID)"
    }
}