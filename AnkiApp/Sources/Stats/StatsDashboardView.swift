import SwiftUI
import AnkiKit
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf

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
                        FutureDueChart(futureDue: graphs.futureDue)
                        HeatmapChart(reviews: graphs.reviews)
                        ReviewsChart(reviews: graphs.reviews, revlogRange: revlogRange)
                        CardCountsChart(cardCounts: graphs.cardCounts)
                        IntervalsChart(intervals: graphs.intervals, isFSRS: graphs.fsrs)
                        EaseChart(eases: graphs.eases, difficulty: graphs.difficulty, isFSRS: graphs.fsrs)
                        HourlyChart(hours: graphs.hours, revlogRange: revlogRange)
                        ButtonsChart(buttons: graphs.buttons, revlogRange: revlogRange)
                        AddedChart(added: graphs.added)
                        RetentionChart(trueRetention: graphs.trueRetention, revlogRange: revlogRange)
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
        .task(id: isActive) {
            guard isActive, !hasLoadedInitialData else { return }
            hasLoadedInitialData = true
            async let decksLoad: Void = loadDecks()
            async let statsLoad: Void = loadStats()
            _ = await (decksLoad, statsLoad)
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
}
