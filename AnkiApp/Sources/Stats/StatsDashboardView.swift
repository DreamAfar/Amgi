import SwiftUI
import AnkiKit
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf

private enum StatsPreferences {
    static let chartOrderKey = "stats_chart_order"
    static let chartLayoutKey = "stats_chart_layout"
}

private enum StatsChartLayoutMode: String {
    case single
    case double
}

private enum StatsChartSection: String, CaseIterable, Identifiable {
    case futureDue
    case heatmap
    case reviews
    case cardCounts
    case intervals
    case stability
    case ease
    case retrievability
    case retention
    case hourly
    case buttons
    case added

    var id: String { rawValue }

    var title: String {
        switch self {
        case .futureDue: L("stats_future_due_title")
        case .heatmap: L("stats_heatmap_title")
        case .reviews: L("stats_reviews_title")
        case .cardCounts: L("stats_card_counts_title")
        case .intervals: L("stats_intervals_title")
        case .stability: L("stats_stability_title")
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var graphs: Anki_Stats_GraphsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var revlogRange: RevlogRange = .year
    @State private var decks: [DeckInfo] = []
    @State private var selectedDeck: DeckInfo?
    @State private var hasLoadedInitialData = false
    @State private var showChartOrderSheet = false
    @AppStorage(StatsPreferences.chartOrderKey) private var chartOrderRaw = ""
    @AppStorage(StatsPreferences.chartLayoutKey) private var chartLayoutRaw = StatsChartLayoutMode.single.rawValue
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
                        chartCards(for: graphs)
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
            if supportsChartLayoutToggle {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleChartLayout()
                    } label: {
                        Image(systemName: usesDoubleColumnLayout ? "rectangle.grid.1x2" : "square.grid.2x2")
                    }
                    .accessibilityLabel(
                        usesDoubleColumnLayout
                        ? L("stats_chart_layout_single")
                        : L("stats_chart_layout_double")
                    )
                }
            }
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

    private var supportsChartLayoutToggle: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var chartLayoutMode: StatsChartLayoutMode {
        StatsChartLayoutMode(rawValue: chartLayoutRaw) ?? .single
    }

    private var usesDoubleColumnLayout: Bool {
        supportsChartLayoutToggle && chartLayoutMode == .double
    }

    private var chartGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320, maximum: 720), spacing: 16, alignment: .top),
            GridItem(.flexible(minimum: 320, maximum: 720), spacing: 16, alignment: .top)
        ]
    }

    private func toggleChartLayout() {
        chartLayoutRaw = usesDoubleColumnLayout
            ? StatsChartLayoutMode.single.rawValue
            : StatsChartLayoutMode.double.rawValue
    }

    // MARK: - Deck Menu

    private var deckMenu: some View {
        Menu {
            Button { selectedDeck = nil } label: {
                if selectedDeck == nil {
                    Label(L("stats_whole_collection"), systemImage: "checkmark")
                        .foregroundStyle(Color.amgiAccent)
                } else {
                    Text(L("stats_whole_collection"))
                        .foregroundStyle(Color.amgiAccent)
                }
            }
            Divider()
            ForEach(decks.filter({ !$0.name.contains("::") })) { deck in
                Button { selectedDeck = deck } label: {
                    if selectedDeck?.id == deck.id {
                        Label(deck.name, systemImage: "checkmark")
                            .foregroundStyle(Color.amgiAccent)
                    } else {
                        Text(deck.name)
                            .foregroundStyle(Color.amgiAccent)
                    }
                }
            }
        } label: {
            SettingsOptionCapsuleLabel(
                title: selectedDeck?.name ?? L("stats_whole_collection"),
                icon: "rectangle.stack",
                maxWidth: 160
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
                search = ""
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
            if section == .retrievability || section == .stability {
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
    private func chartCards(for graphs: Anki_Stats_GraphsResponse) -> some View {
        let sections = orderedChartSections(for: graphs)
        if usesDoubleColumnLayout {
            LazyVGrid(columns: chartGridColumns, alignment: .leading, spacing: 16) {
                ForEach(sections, id: \.self) { section in
                    chartView(for: section, graphs: graphs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        } else {
            ForEach(sections, id: \.self) { section in
                chartView(for: section, graphs: graphs)
            }
        }
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
            CardCountsChart(
                cardCounts: graphs.cardCounts,
                prefersWideSingleColumnLayout: supportsChartLayoutToggle && !usesDoubleColumnLayout
            )
        case .intervals:
            IntervalsChart(intervals: graphs.intervals, kind: .intervals)
        case .stability:
            IntervalsChart(intervals: graphs.stability, kind: .stability)
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
