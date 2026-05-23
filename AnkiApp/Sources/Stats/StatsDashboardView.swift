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

enum StatsChartLayoutMode: String {
    case single
    case double
}

enum StatsChartSection: String, CaseIterable, Identifiable {
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

enum StatsGroup: String, CaseIterable, Identifiable {
    case overview
    case today
    case cards
    case fsrs
    case heatmap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return L("stats_group_overview")
        case .today:
            return L("common_today")
        case .cards:
            return L("stats_group_cards")
        case .fsrs:
            return L("settings_review_section_fsrs")
        case .heatmap:
            return L("deck_list_heatmap_title")
        }
    }

    var icon: String {
        switch self {
        case .overview:
            return "square.grid.2x2"
        case .today:
            return "sun.max"
        case .cards:
            return "rectangle.stack"
        case .fsrs:
            return "brain.head.profile"
        case .heatmap:
            return "calendar"
        }
    }
}

private struct StatsChartRun: Identifiable {
    let id: Int
    let group: StatsGroup
    let sections: [StatsChartSection]
    let showsAnchor: Bool
}

private struct StatsChartRow: Identifiable {
    let id: Int
    let left: StatsChartSection
    let right: StatsChartSection?
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
    @State private var selectedGroup: StatsGroup = .overview
    @State private var doubleColumnRowHeights: [String: CGFloat] = [:]
    @AppStorage(StatsPreferences.chartOrderKey) private var chartOrderRaw = ""
    @AppStorage(StatsPreferences.chartLayoutKey) private var chartLayoutRaw = StatsChartLayoutMode.single.rawValue
    private let initialDeckID: Int64?
    private let isActive: Bool
    private let externalSelectedDeck: Binding<DeckInfo?>?
    private let externalRevlogRange: Binding<RevlogRange>?
    private let externalSelectedGroup: Binding<StatsGroup>?

    init(
        initialDeckID: Int64? = nil,
        isActive: Bool = true,
        externalSelectedDeck: Binding<DeckInfo?>? = nil,
        externalRevlogRange: Binding<RevlogRange>? = nil,
        externalSelectedGroup: Binding<StatsGroup>? = nil
    ) {
        self.initialDeckID = initialDeckID
        self.isActive = isActive
        self.externalSelectedDeck = externalSelectedDeck
        self.externalRevlogRange = externalRevlogRange
        self.externalSelectedGroup = externalSelectedGroup
        if let externalSelectedDeck, let initialDeck = externalSelectedDeck.wrappedValue {
            _selectedDeck = State(initialValue: initialDeck)
        }
        if let externalRevlogRange {
            _revlogRange = State(initialValue: externalRevlogRange.wrappedValue)
        }
        if let externalSelectedGroup {
            _selectedGroup = State(initialValue: externalSelectedGroup.wrappedValue)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
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
                            Color.clear
                                .frame(height: 1)
                                .id(StatsGroup.overview)
                            TodayStatsCard(today: graphs.today)
                                .id(StatsGroup.today)
                            orderedChartContent(graphs: graphs)
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
                syncExternalStateIntoLocal()
                scrollToSelectedGroup(with: proxy, animated: false)
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
                    scrollToSelectedGroup(with: proxy, animated: false)
                }
            }
            .refreshable { await loadStats() }
            .onAppear {
                syncExternalStateIntoLocal()
                scrollToSelectedGroup(with: proxy, animated: false)
            }
            .onChange(of: externalSelectedDeckID) { _, _ in
                syncExternalStateIntoLocal()
            }
            .onChange(of: externalRevlogRangeValue) { _, _ in
                syncExternalStateIntoLocal()
            }
            .onChange(of: externalSelectedGroupValue) { _, _ in
                syncExternalStateIntoLocal()
                scrollToSelectedGroup(with: proxy, animated: true)
            }
            .onChange(of: selectedDeck) {
                syncLocalStateToExternal()
                Task { await loadStats() }
            }
            .onChange(of: revlogRange) {
                syncLocalStateToExternal()
                Task { await loadStats() }
            }
            .onChange(of: selectedGroup) {
                syncLocalStateToExternal()
                scrollToSelectedGroup(with: proxy, animated: true)
            }
            .onChange(of: isLoading) { _, loading in
                guard !loading else { return }
                scrollToSelectedGroup(with: proxy, animated: false)
            }
        }
    }

    private var externalSelectedDeckID: Int64? {
        externalSelectedDeck?.wrappedValue?.id
    }

    private var externalRevlogRangeValue: RevlogRange? {
        externalRevlogRange?.wrappedValue
    }

    private var externalSelectedGroupValue: StatsGroup? {
        externalSelectedGroup?.wrappedValue
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
        syncExternalStateIntoLocal()
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

    private func syncExternalStateIntoLocal() {
        if let externalSelectedDeck, selectedDeck?.id != externalSelectedDeck.wrappedValue?.id {
            selectedDeck = externalSelectedDeck.wrappedValue
        }
        if let externalRevlogRange, revlogRange != externalRevlogRange.wrappedValue {
            revlogRange = externalRevlogRange.wrappedValue
        }
        if let externalSelectedGroup, selectedGroup != externalSelectedGroup.wrappedValue {
            selectedGroup = externalSelectedGroup.wrappedValue
        }
    }

    private func syncLocalStateToExternal() {
        if let externalSelectedDeck, externalSelectedDeck.wrappedValue?.id != selectedDeck?.id {
            externalSelectedDeck.wrappedValue = selectedDeck
        }
        if let externalRevlogRange, externalRevlogRange.wrappedValue != revlogRange {
            externalRevlogRange.wrappedValue = revlogRange
        }
        if let externalSelectedGroup, externalSelectedGroup.wrappedValue != selectedGroup {
            externalSelectedGroup.wrappedValue = selectedGroup
        }
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
    private func orderedChartContent(graphs: Anki_Stats_GraphsResponse) -> some View {
        ForEach(chartRuns(for: graphs)) { run in
            if run.showsAnchor {
                Color.clear
                    .frame(height: 1)
                    .id(run.group)
            }
            chartRunContent(run, graphs: graphs)
        }
    }

    @ViewBuilder
    private func chartRunContent(_ run: StatsChartRun, graphs: Anki_Stats_GraphsResponse) -> some View {
        if usesDoubleColumnLayout && shouldUseDoubleColumnLayout(for: run.group) && run.sections.count > 1 {
            let rows = chartRows(for: run.sections)
            VStack(spacing: 16) {
                ForEach(rows) { row in
                    let rowKey = chartRowKey(runID: run.id, rowID: row.id)
                    HStack(alignment: .top, spacing: 16) {
                        measuredChartCell(
                            section: row.left,
                            rowKey: rowKey,
                            graphs: graphs
                        )

                        if let right = row.right {
                            measuredChartCell(
                                section: right,
                                rowKey: rowKey,
                                graphs: graphs
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .onPreferenceChange(StatsMeasuredHeightPreferenceKey.self) { heights in
                for (key, height) in heights {
                    if doubleColumnRowHeights[key] != height {
                        doubleColumnRowHeights[key] = height
                    }
                }
            }
        } else {
            ForEach(run.sections, id: \.self) { section in
                chartView(for: section, graphs: graphs)
            }
        }
    }

    private func chartRuns(for graphs: Anki_Stats_GraphsResponse) -> [StatsChartRun] {
        let sections = orderedChartSections(for: graphs)
        var runs: [StatsChartRun] = []
        var anchoredGroups = Set<StatsGroup>()

        for section in sections {
            let group = statsGroup(for: section)
            let showsAnchor = anchoredGroups.insert(group).inserted
            if let lastIndex = runs.indices.last, runs[lastIndex].group == group {
                runs[lastIndex] = StatsChartRun(
                    id: runs[lastIndex].id,
                    group: group,
                    sections: runs[lastIndex].sections + [section],
                    showsAnchor: runs[lastIndex].showsAnchor
                )
            } else {
                runs.append(
                    StatsChartRun(
                        id: runs.count,
                        group: group,
                        sections: [section],
                        showsAnchor: showsAnchor
                    )
                )
            }
        }

        return runs
    }

    private func shouldUseDoubleColumnLayout(for group: StatsGroup) -> Bool {
        group == .overview || group == .cards || group == .fsrs
    }

    private func statsGroup(for section: StatsChartSection) -> StatsGroup {
        switch section {
        case .futureDue, .added:
            return .overview
        case .heatmap:
            return .heatmap
        case .reviews, .cardCounts, .intervals, .ease, .hourly, .buttons:
            return .cards
        case .stability, .retrievability, .retention:
            return .fsrs
        }
    }

    private func scrollToSelectedGroup(with proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(selectedGroup, anchor: .top)
        }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.24)) {
                    action()
                }
            } else {
                action()
            }
        }
    }

    private func chartRows(for sections: [StatsChartSection]) -> [StatsChartRow] {
        stride(from: 0, to: sections.count, by: 2).enumerated().map { index, offset in
            StatsChartRow(
                id: index,
                left: sections[offset],
                right: offset + 1 < sections.count ? sections[offset + 1] : nil
            )
        }
    }

    private func chartRowKey(runID: Int, rowID: Int) -> String {
        "stats-row-\(runID)-\(rowID)"
    }

    private func measuredChartCell(
        section: StatsChartSection,
        rowKey: String,
        graphs: Anki_Stats_GraphsResponse
    ) -> some View {
        chartView(for: section, graphs: graphs)
            .statsCardMinHeight(doubleColumnRowHeights[rowKey])
            .statsMeasureHeight(id: rowKey)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
