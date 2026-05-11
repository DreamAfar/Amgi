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
    @State private var loadError = false
    @State private var isTodayStatsCollapsed = false
    @State private var heatmapSectionHeight: CGFloat = 0
    @State private var todayStatsSectionHeight: CGFloat = 0

    private let todayStatsAnimation = Animation.easeInOut(duration: 0.24)
    private let todayStatsTopSpacing: CGFloat = 14

    let showsExternalLoading: Bool

    init(refreshID: Int, showsExternalLoading: Bool = false) {
        self.refreshID = refreshID
        self.showsExternalLoading = showsExternalLoading
        _graphs = State(initialValue: DeckListHeatmapCache.loadCurrent())
        _isLoading = State(initialValue: true)
    }

    var body: some View {
        let todayStatsExpandedHeight = resolvedTodayStatsExpandedHeight ?? 0
        let cardContentHeight: CGFloat? = resolvedHeatmapSectionHeight.map { heatmapHeight in
            heatmapHeight + (isTodayStatsCollapsed ? 0 : todayStatsExpandedHeight)
        }

        Group {
            if let graphs {
                ZStack(alignment: .topLeading) {
                    HeatmapChart(
                        reviews: graphs.reviews,
                        compactHeight: deckListHeatmapHeight,
                        embedded: true,
                        onTapHeatmap: {
                            isTodayStatsCollapsed.toggle()
                        }
                    )
                    .background(heightReader($heatmapSectionHeight))

                    VStack(alignment: .leading, spacing: 14) {
                        Divider()
                        TodayStatsCard(
                            today: graphs.today,
                            embedded: true,
                            compactText: true
                        )
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, todayStatsTopSpacing)
                    .background(heightReader($todayStatsSectionHeight))
                    .offset(y: resolvedHeatmapSectionHeight ?? 0)
                    .allowsHitTesting(!isTodayStatsCollapsed)
                    .accessibilityHidden(isTodayStatsCollapsed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: cardContentHeight, alignment: .top)
                .clipped()
                .animation(todayStatsAnimation, value: isTodayStatsCollapsed)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.amgiSurfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.amgiBorder.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .center) {
                    if isLoading || showsExternalLoading {
                        ProgressView()
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isLoading)
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
        } catch {
            loadError = (graphs == nil)
        }
        isLoading = false
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
            return Swift.abs(a.timeIntervalSince(b)) < 1
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
        let shiftDays = dayShift(
            from: cachedAt,
            to: Date(),
            rolloverHour: Int(fresh.rolloverHour)
        )
        merged.reviews.count = shiftReviewMap(cached.reviews.count, by: shiftDays)
        merged.reviews.time = shiftReviewMap(cached.reviews.time, by: shiftDays)
        merged.today = fresh.today
        merged.rolloverHour = fresh.rolloverHour

        for (day, reviews) in fresh.reviews.count {
            merged.reviews.count[day] = reviews
        }
        for (day, reviews) in fresh.reviews.time {
            merged.reviews.time[day] = reviews
        }
        return merged
    }

    private func dayShift(from cachedAt: Date, to now: Date, rolloverHour: Int) -> Int32 {
        guard cachedAt > .distantPast else { return 0 }
        let calendar = Calendar.current
        let cachedDay = calendar.startOfDay(for: adjustedStudyDayDate(cachedAt, rolloverHour: rolloverHour))
        let currentDay = calendar.startOfDay(for: adjustedStudyDayDate(now, rolloverHour: rolloverHour))
        let delta = calendar.dateComponents([.day], from: cachedDay, to: currentDay).day ?? 0
        return Int32(delta)
    }

    private func adjustedStudyDayDate(_ date: Date, rolloverHour: Int) -> Date {
        let calendar = Calendar.current
        guard (0..<24).contains(rolloverHour) else { return date }
        if calendar.component(.hour, from: date) < rolloverHour {
            return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return date
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

    private var resolvedTodayStatsExpandedHeight: CGFloat? {
        guard todayStatsSectionHeight > 0 else { return nil }
        return todayStatsSectionHeight + todayStatsTopSpacing
    }

    private var resolvedHeatmapSectionHeight: CGFloat? {
        heatmapSectionHeight > 0 ? heatmapSectionHeight : nil
    }

    private func heightReader(_ height: Binding<CGFloat>) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    let newHeight = proxy.size.height
                    if newHeight > 0, abs(height.wrappedValue - newHeight) > 0.5 {
                        height.wrappedValue = newHeight
                    }
                }
                .onChange(of: proxy.size.height) { _, newHeight in
                    if newHeight > 0, abs(height.wrappedValue - newHeight) > 0.5 {
                        height.wrappedValue = newHeight
                    }
                }
        }
    }
}
