import SwiftUI
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf

struct DeckListHeatmapCard: View {
    @Dependency(\.statsClient) var statsClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.syncClient) var syncClient
    @ObservedObject private var collectionState = AppCollectionState.shared
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

    let showsExternalLoading: Bool

    init(refreshID: Int, showsExternalLoading: Bool = false) {
        self.refreshID = refreshID
        self.showsExternalLoading = showsExternalLoading
        _graphs = State(initialValue: DeckListHeatmapCache.loadCurrent())
        _isLoading = State(initialValue: true)
        _hasLoadedFullHistory = State(
            initialValue: UserDefaults.standard.integer(forKey: DeckListHeatmapSettings.initialDaysKey)
                == HeatmapInitialDays.allHistory.rawValue
        )
    }

    var body: some View {
        Group {
            if let graphs {
                // Always show heatmap; overlay spinner during refresh or full-history load
                HeatmapChart(reviews: graphs.reviews, compactHeight: deckListHeatmapHeight)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .center) {
                        if isLoading || showsExternalLoading {
                            ProgressView()
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if isLoadingMoreHistory {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.65)
                                    .frame(width: 14, height: 14)
                                Text(L("heatmap_loading_full_history"))
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
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
                                .amgiFont(.micro)
                                .foregroundStyle(Color.amgiTextSecondary)
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
            } else if isLoading || showsExternalLoading {
                // First load only — no cached data yet
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .allowsHitTesting(false)
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
            guard collectionState.isReady else {
                isLoading = graphs != nil
                return
            }
            await loadStats()
        }
        .onChange(of: collectionState.isReady) { _, isReady in
            guard isReady else { return }
            Task { await loadStats() }
        }
    }

    @MainActor
    private func loadStats() async {
        guard collectionState.isReady else { return }
        isLoading = true
        isLoadingMoreHistory = false
        hasLoadedFullHistory = false
        loadError = false

        do {
            let query = try resolvedSearchQuery()
            let days = initialDaysRaw  // 0 = all history
            let lastSyncAt = syncClient.lastSyncDate()
            let response = try await loadBestResponse(query: query, days: days, lastSyncAt: lastSyncAt)
            graphs = response
            DeckListHeatmapCache.save(
                response,
                searchQuery: query,
                requestedDays: days,
                lastSyncAt: lastSyncAt
            )
            // If user already chose "all history" in settings, mark as loaded
            if days == HeatmapInitialDays.allHistory.rawValue {
                hasLoadedFullHistory = true
            }
        } catch {
            loadError = (graphs == nil)
        }
        isLoading = false
    }

    @MainActor
    private func loadFullHistory() async {
        guard collectionState.isReady, !isLoadingMoreHistory else { return }
        isLoadingMoreHistory = true
        do {
            let query = try resolvedSearchQuery()
            let lastSyncAt = syncClient.lastSyncDate()
            let response = try await fetchGraphsResponse(query: query, days: 0, priority: .background)
            graphs = response
            DeckListHeatmapCache.save(
                response,
                searchQuery: query,
                requestedDays: 0,
                lastSyncAt: lastSyncAt
            )
            hasLoadedFullHistory = true
        } catch {
            // keep existing 180-day data on failure
        }
        isLoadingMoreHistory = false
    }

    private func loadBestResponse(
        query: String,
        days: Int,
        lastSyncAt: Date?
    ) async throws -> Anki_Stats_GraphsResponse {
        guard let cached = DeckListHeatmapCache.loadEntry(),
              cached.searchQuery == query,
              cached.requestedDays == days,
              sameSyncState(cached.lastSyncAt, lastSyncAt),
              let cachedResponse = cached.response
        else {
            return try await fetchGraphsResponse(query: query, days: UInt32(days), priority: .userInitiated)
        }

        let recentDays = incrementalRefreshDays(for: days)
        guard recentDays > 0 else {
            return try await fetchGraphsResponse(query: query, days: UInt32(days), priority: .userInitiated)
        }

        let recentResponse = try await fetchGraphsResponse(
            query: query,
            days: UInt32(recentDays),
            priority: .userInitiated
        )
        return merge(cached: cachedResponse, cachedAt: cached.cachedAt, fresh: recentResponse)
    }

    private func fetchGraphsResponse(
        query: String,
        days: UInt32,
        priority: TaskPriority
    ) async throws -> Anki_Stats_GraphsResponse {
        let client = statsClient
        var lastError: Error?

        for attempt in 0..<2 {
            do {
                let bytes = try await Task.detached(priority: priority) {
                    try client.fetchGraphs(query, days)
                }.value
                try Task.checkCancellation()
                return try Anki_Stats_GraphsResponse(serializedBytes: bytes)
            } catch {
                lastError = error
                guard attempt == 0 else { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        throw lastError ?? CancellationError()
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

        let availableDeckIDs = Set(try deckClient.fetchNamesOnly().map(\.id))
        guard availableDeckIDs.contains(selectedID) else {
            heatmapScopeRaw = DeckListHeatmapScope.allDecks.rawValue
            selectedDeckID = DeckListHeatmapSettings.defaultSelectedDeckID
            return DeckListHeatmapSettings.allDecksSearch
        }

        return "did:\(selectedID)"
    }

    private func incrementalRefreshDays(for requestedDays: Int) -> Int {
        let refreshWindow = 7
        if requestedDays == 0 {
            return refreshWindow
        }
        return min(requestedDays, refreshWindow)
    }

    private func sameSyncState(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(a), .some(b)):
            return abs(a.timeIntervalSince(b)) < 1
        default:
            return false
        }
    }

    private func merge(
        cached: Anki_Stats_GraphsResponse,
        cachedAt: Date,
        fresh: Anki_Stats_GraphsResponse
    ) -> Anki_Stats_GraphsResponse {
        var merged = cached
        let shiftDays = dayShift(from: cachedAt, to: Date())
        merged.reviews.count = shiftReviewMap(cached.reviews.count, by: shiftDays)
        merged.reviews.time = shiftReviewMap(cached.reviews.time, by: shiftDays)

        for (day, reviews) in fresh.reviews.count {
            merged.reviews.count[day] = reviews
        }
        for (day, reviews) in fresh.reviews.time {
            merged.reviews.time[day] = reviews
        }
        return merged
    }

    private func dayShift(from cachedAt: Date, to now: Date) -> Int32 {
        guard cachedAt > .distantPast else { return 0 }
        let calendar = Calendar.current
        let cachedDay = calendar.startOfDay(for: cachedAt)
        let currentDay = calendar.startOfDay(for: now)
        let delta = calendar.dateComponents([.day], from: cachedDay, to: currentDay).day ?? 0
        return Int32(delta)
    }

    private func shiftReviewMap(
        _ map: [Int32: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews],
        by shiftDays: Int32
    ) -> [Int32: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews] {
        guard shiftDays != 0 else { return map }

        var shifted: [Int32: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews] = [:]
        for (offset, value) in map {
            let newOffset = offset - shiftDays
            guard newOffset <= 0 else { continue }
            shifted[newOffset] = value
        }
        return shifted
    }
}
