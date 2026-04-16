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
    @AppStorage(DeckListHeatmapSettings.initialDaysKey) private var initialDaysRaw = DeckListHeatmapSettings.defaultInitialDays

    let refreshID: Int

    @State private var graphs: Anki_Stats_GraphsResponse?
    @State private var isLoading = true
    /// True while the user-triggered full-history fetch is running
    @State private var isLoadingMoreHistory = false
    @State private var hasLoadedFullHistory = false
    @State private var loadError = false

    var body: some View {
        Group {
            if let graphs {
                // Always show heatmap; overlay spinner during refresh or full-history load
                HeatmapChart(reviews: graphs.reviews, compactHeight: deckListHeatmapHeight)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .center) {
                        if isLoading {
                            ProgressView()
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if isLoadingMoreHistory {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.65)
                                    .frame(width: 14, height: 14)
                                Text(L("heatmap_loading_full_history"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                        } else if !hasLoadedFullHistory {
                            Button {
                                Task { await loadFullHistory() }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.left.to.line")
                                    Text(L("heatmap_load_all_history"))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                    .animation(.easeInOut(duration: 0.2), value: isLoadingMoreHistory)
                    .animation(.easeInOut(duration: 0.2), value: hasLoadedFullHistory)
            } else if isLoading {
                // First load only — no cached data yet
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if loadError {
                ContentUnavailableView(
                    L("deck_list_heatmap_title"),
                    systemImage: "chart.bar.xaxis",
                    description: Text(L("deck_list_heatmap_load_failed"))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .task(id: refreshID) {
            await loadStats()
        }
    }

    @MainActor
    private func loadStats() async {
        isLoading = true
        isLoadingMoreHistory = false
        hasLoadedFullHistory = false
        loadError = false

        do {
            let query = try resolvedSearchQuery()
            let client = statsClient
            let days = initialDaysRaw  // 0 = all history

            let bytes = try await Task.detached(priority: .userInitiated) {
                try client.fetchGraphs(query, days)
            }.value
            try Task.checkCancellation()
            graphs = try Anki_Stats_GraphsResponse(serializedBytes: bytes)
            // If user already chose "all history" in settings, mark as loaded
            if days == HeatmapInitialDays.allHistory.rawValue {
                hasLoadedFullHistory = true
            }
        } catch {
            loadError = true
        }
        isLoading = false
    }

    @MainActor
    private func loadFullHistory() async {
        guard !isLoadingMoreHistory else { return }
        isLoadingMoreHistory = true
        do {
            let query = try resolvedSearchQuery()
            let client = statsClient
            let bytes = try await Task.detached(priority: .background) {
                try client.fetchGraphs(query, 0)
            }.value
            graphs = try Anki_Stats_GraphsResponse(serializedBytes: bytes)
            hasLoadedFullHistory = true
        } catch {
            // keep existing 180-day data on failure
        }
        isLoadingMoreHistory = false
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