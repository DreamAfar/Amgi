import SwiftUI
import AnkiKit
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf

private enum StatsPreferences {
    static let chartOrderKey = "stats_chart_order"
}

private enum StatsChartSection: String, CaseIterable, Identifiable {
    case futureDue
    case heatmap
    case reviews
    case cardCounts
    case intervals
    case ease
    case hourly
    case buttons
    case added
    case retrievability
    case retention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .futureDue: L("stats_future_due_title")
        case .heatmap: L("stats_heatmap_title")
        case .reviews: L("stats_reviews_title")
        case .cardCounts: L("stats_card_counts_title")
        case .intervals: L("stats_stability_title")
        case .ease: L("stats_difficulty_title")
        case .hourly: L("stats_hourly_title")
        case .buttons: L("stats_buttons_title")
        case .added: L("stats_added_title")
        case .retrievability: L("stats_retrievability_title")
        case .retention: L("stats_retention_title")
        }
    }
}

struct StatsDashboardView: View {
    @Dependency(\.statsClient) var statsClient
    @Dependency(\.deckClient) var deckClient

    @State private var graphs: Anki_Stats_GraphsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var revlogRange: RevlogRange = .year
    @State private var decks: [DeckInfo] = []
    @State private var selectedDeck: DeckInfo?
    @State private var hasLoadedInitialData = false
    @State private var showChartOrderSheet = false
    @AppStorage(StatsPreferences.chartOrderKey) private var chartOrderRaw = ""
    private let initialDeckID: Int64?
    private let isActive: Bool

    init(initialDeckID: Int64? = nil, isActive: Bool = true) {
        self.initialDeckID = initialDeckID
        self.isActive = isActive
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                if isLoading {
                    ProgressView(L("stats_loading"))
                        .padding(.top, 40)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        L("stats_load_failed_title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let graphs {
                    Section {
                        TodayStatsCard(today: graphs.today)
                        ForEach(orderedChartSections(for: graphs), id: \.self) { section in
                            chartView(for: section, graphs: graphs)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                deckMenu
                                Spacer()
                                revlogRangePicker
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.clear)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(L("stats_nav_title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showChartOrderSheet = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel(L("stats_chart_order_button"))
            }
        }
        .task(id: isActive) {
            guard isActive, !hasLoadedInitialData else { return }
            hasLoadedInitialData = true
            async let decksLoad: Void = loadDecks()
            async let statsLoad: Void = loadStats()
            _ = await (decksLoad, statsLoad)
        }
        .sheet(isPresented: $showChartOrderSheet) {
            NavigationStack {
                StatsChartOrderSheet(
                    sections: orderedChartSections(for: graphs),
                    onMove: moveChartSection,
                    onReset: resetChartOrder
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didOpenNotification)) { _ in
            guard isActive else { return }
            Task {
                async let decksLoad: Void = loadDecks()
                async let statsLoad: Void = loadStats()
                _ = await (decksLoad, statsLoad)
            }
        }
        .refreshable { await loadStats() }
        .onChange(of: selectedDeck) {
            Task { await loadStats() }
        }
        .onChange(of: revlogRange) {
            Task { await loadStats() }
        }
    }

    // MARK: - Deck Menu

    private var deckMenu: some View {
        Menu {
            Button { selectedDeck = nil } label: {
                if selectedDeck == nil { Label(L("stats_whole_collection"), systemImage: "checkmark") }
                else { Text(L("stats_whole_collection")) }
            }
            Divider()
            ForEach(decks.filter({ !$0.name.contains("::") })) { deck in
                Button { selectedDeck = deck } label: {
                    if selectedDeck?.id == deck.id { Label(deck.name, systemImage: "checkmark") }
                    else { Text(deck.name) }
                }
            }
        } label: {
            filterCapsule(
                icon: "rectangle.stack",
                label: selectedDeck?.name ?? L("stats_whole_collection")
            )
        }
    }

    // MARK: - RevlogRange Picker

    private var revlogRangePicker: some View {
        Picker("", selection: $revlogRange) {
            ForEach(RevlogRange.allCases, id: \.self) { r in
                Text(r.localizedLabel).tag(r)
            }
        }
        .amgiSegmentedPicker()
        .fixedSize()
    }

    // MARK: - (period menu removed — charts manage their own display range)

    // MARK: - Shared Capsule

    private func filterCapsule(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AmgiFont.micro.font)
                .foregroundStyle(Color.amgiTextSecondary)
            Text(label)
                .amgiFont(.captionBold)
                .foregroundStyle(Color.amgiTextPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(AmgiFont.micro.font)
                .foregroundStyle(Color.amgiTextSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.amgiSurfaceElevated)
        .overlay(
            Capsule()
                .stroke(Color.amgiBorder.opacity(0.28), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    // MARK: - Data

    private func loadDecks() async {
        decks = (try? deckClient.fetchNamesOnly()) ?? []
        if let initialDeckID, selectedDeck == nil {
            selectedDeck = decks.first(where: { $0.id == initialDeckID })
        }
    }

    private func loadStats() async {
        isLoading = graphs == nil
        do {
            let search: String
            if let deck = selectedDeck {
                search = "deck:\"\(deck.name)\""
            } else {
                search = "deck:*"
            }
            let client = statsClient
            let days = revlogRange.requestDays
            let data = try await Task.detached(priority: .userInitiated) {
                try client.fetchGraphs(search, days)
            }.value
            graphs = try Anki_Stats_GraphsResponse(serializedBytes: data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func storedChartOrder() -> [StatsChartSection] {
        let saved = chartOrderRaw
            .split(separator: ",")
            .compactMap { StatsChartSection(rawValue: String($0)) }
        let fallback = StatsChartSection.allCases
        var result: [StatsChartSection] = []
        for section in saved where !result.contains(section) {
            result.append(section)
        }
        for section in fallback where !result.contains(section) {
            result.append(section)
        }
        return result
    }

    private func orderedChartSections(for graphs: Anki_Stats_GraphsResponse?) -> [StatsChartSection] {
        storedChartOrder().filter { section in
            if section == .retrievability {
                return graphs?.fsrs == true
            }
            return true
        }
    }

    private func persistChartOrder(_ sections: [StatsChartSection]) {
        chartOrderRaw = sections.map(\.rawValue).joined(separator: ",")
    }

    private func moveChartSection(from source: IndexSet, to destination: Int) {
        var sections = storedChartOrder()
        sections.move(fromOffsets: source, toOffset: destination)
        persistChartOrder(sections)
    }

    private func resetChartOrder() {
        persistChartOrder(StatsChartSection.allCases)
    }

    @ViewBuilder
    private func chartView(for section: StatsChartSection, graphs: Anki_Stats_GraphsResponse) -> some View {
        switch section {
        case .futureDue:
            FutureDueChart(futureDue: graphs.futureDue)
        case .heatmap:
            HeatmapChart(reviews: graphs.reviews)
        case .reviews:
            ReviewsChart(reviews: graphs.reviews, revlogRange: revlogRange)
        case .cardCounts:
            CardCountsChart(cardCounts: graphs.cardCounts)
        case .intervals:
            IntervalsChart(intervals: graphs.intervals, isFSRS: graphs.fsrs)
        case .ease:
            EaseChart(eases: graphs.eases, difficulty: graphs.difficulty, isFSRS: graphs.fsrs)
        case .hourly:
            HourlyChart(hours: graphs.hours, revlogRange: revlogRange)
        case .buttons:
            ButtonsChart(buttons: graphs.buttons, revlogRange: revlogRange)
        case .added:
            AddedChart(added: graphs.added)
        case .retrievability:
            RetrievabilityChart(retrievability: graphs.retrievability)
        case .retention:
            RetentionChart(trueRetention: graphs.trueRetention, revlogRange: revlogRange)
        }
    }
}

private struct StatsChartOrderSheet: View {
    let sections: [StatsChartSection]
    let onMove: (IndexSet, Int) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section(L("stats_chart_order_title")) {
                ForEach(sections) { section in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        Text(section.title)
                            .foregroundStyle(.primary)
                    }
                }
                .onMove(perform: onMove)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(L("stats_chart_order_button"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L("common_cancel")) { dismiss() }
                    .amgiToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("stats_chart_order_reset")) {
                    onReset()
                }
                .amgiToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_done")) { dismiss() }
                    .amgiToolbarTextButton()
            }
        }
    }
}
