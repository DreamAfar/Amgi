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
    /// True while the background full-history fetch is running
    @State private var isLoadingFull = false
    @State private var loadError = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView(L("stats_loading"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let graphs {
                VStack(spacing: 0) {
                    HeatmapChart(reviews: graphs.reviews, compactHeight: deckListHeatmapHeight)
                        .frame(maxWidth: .infinity)

                    if isLoadingFull {
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 14, height: 14)
                            Text(L("heatmap_loading_full_history"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                    }
                }
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
        .animation(.easeInOut(duration: 0.2), value: isLoadingFull)
        .task(id: refreshID) {
            await loadStats()
        }
    }

    @MainActor
    private func loadStats() async {
        isLoading = true
        isLoadingFull = false
        loadError = false

        do {
            let query = try resolvedSearchQuery()
            // Capture the Sendable closure to safely use from a detached task
            let client = statsClient

            // ── Phase 1: load 6 months (≈50 ms) off the MainActor ─────────────
            let fastBytes = try await Task.detached(priority: .userInitiated) {
                try client.fetchGraphs(query, 180)
            }.value
            try Task.checkCancellation()
            graphs = try Anki_Stats_GraphsResponse(serializedBytes: fastBytes)
            isLoading = false   // Show immediately – no UI freeze

            // ── Phase 2: load full history silently in background ──────────────
            isLoadingFull = true
            let fullBytes = try await Task.detached(priority: .background) {
                try client.fetchGraphs(query, 0)    // 0 = all-time
            }.value
            try Task.checkCancellation()
            graphs = try Anki_Stats_GraphsResponse(serializedBytes: fullBytes)
            isLoadingFull = false

        } catch {
            isLoading = false
            isLoadingFull = false
            // Only show error state if we have no partial data to fall back to
            if graphs == nil {
                loadError = true
            }
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