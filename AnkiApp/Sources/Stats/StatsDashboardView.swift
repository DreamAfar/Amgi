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
    @State private var period: StatsPeriod = .month
    @State private var decks: [DeckInfo] = []
    @State private var selectedDeck: DeckInfo?
    private let initialDeckID: Int64?

    init(initialDeckID: Int64? = nil) {
        self.initialDeckID = initialDeckID
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
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
                    // Filters row
                    HStack(spacing: 8) {
                        deckMenu
                        periodMenu
                        Spacer()
                    }

                    TodayStatsCard(today: graphs.today)
                    FutureDueChart(futureDue: graphs.futureDue, period: period)
                    HeatmapChart(reviews: graphs.reviews)
                    ReviewsChart(reviews: graphs.reviews, period: period)
                    CardCountsChart(cardCounts: graphs.cardCounts)
                    IntervalsChart(intervals: graphs.intervals)
                    EaseChart(eases: graphs.eases)
                    HourlyChart(hours: graphs.hours, period: period)
                    ButtonsChart(buttons: graphs.buttons, period: period)
                    AddedChart(added: graphs.added, period: period)
                    RetentionChart(trueRetention: graphs.trueRetention)
                }
            }
            .padding()
        }
        .navigationTitle(L("stats_nav_title"))
        .task {
            await loadDecks()
            await loadStats()
        }
        .refreshable { await loadStats() }
        .onChange(of: selectedDeck) {
            Task { await loadStats() }
        }
        .onChange(of: period) {
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

    // MARK: - Period Menu

    private var periodMenu: some View {
        Menu {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Button { period = p } label: {
                    if period == p { Label(p.localizedLabel, systemImage: "checkmark") }
                    else { Text(p.localizedLabel) }
                }
            }
        } label: {
            filterCapsule(
                icon: "calendar",
                label: period.shortLabel
            )
        }
    }

    // MARK: - Shared Capsule

    private func filterCapsule(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .fontWeight(.medium)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(Capsule())
    }

    // MARK: - Data

    private func loadDecks() async {
        decks = (try? deckClient.fetchAll()) ?? []
        if let initialDeckID, selectedDeck == nil {
            selectedDeck = decks.first(where: { $0.id == initialDeckID })
        }
    }

    private func loadStats() async {
        isLoading = graphs == nil
        do {
            let search = selectedDeck.map { "did:\($0.id)" } ?? ""
            let data = try statsClient.fetchGraphs(search, period.requestDays)
            graphs = try Anki_Stats_GraphsResponse(serializedBytes: data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
