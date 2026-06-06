// AmgiApp/Sources/WriteWidgetSnapshot.swift
import AnkiClients
import AnkiKit
import AnkiProto
import Dependencies
import Foundation
import SwiftProtobuf
import WidgetKit

/// Fetches current deck data + streak, writes per-deck snapshot files to the
/// App Group container, then signals WidgetKit to reload all timelines.
/// Safe to call from any async context.
func writeWidgetSnapshot() async {
    // Skip during XCTest runs — the lifecycle hooks that call this run inside
    // the host app's scene phase / didFinishLaunching, which fire even when
    // the app is hosting a test bundle. Calling unimplemented dependency stubs
    // there registers as a test failure even though the caller catches the
    // error. Tests that genuinely need widget-snapshot behavior can call this
    // directly inside their own withDependencies overrides.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        return
    }

    @Dependency(\.deckClient) var deckClient
    @Dependency(\.statsClient) var statsClient

    do {
        struct WidgetStudyStats {
            let reviewedToday: Int
            let streak: Int
            let lastSevenDays: [Int]

            static let zero = WidgetStudyStats(
                reviewedToday: 0,
                streak: 0,
                lastSevenDays: Array(repeating: 0, count: 7)
            )
        }

        func dayTotal(_ rev: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews) -> Int {
            Int(rev.learn) + Int(rev.relearn) + Int(rev.young) + Int(rev.mature) + Int(rev.filtered)
        }

        func makeStudyStats(from graphs: Anki_Stats_GraphsResponse) -> WidgetStudyStats {
            let todayTotal = graphs.reviews.count[Int32(0)].map { dayTotal($0) } ?? 0
            let startOffset = todayTotal > 0 ? Int32(0) : Int32(-1)

            var streak = 0
            for offset in stride(from: startOffset, through: Int32(-27), by: -1) {
                guard let rev = graphs.reviews.count[offset] else { break }
                guard dayTotal(rev) > 0 else { break }
                streak += 1
            }

            let lastSevenDays: [Int] = (-6 ... 0).map { offset in
                guard let rev = graphs.reviews.count[Int32(offset)] else { return 0 }
                return dayTotal(rev)
            }

            return WidgetStudyStats(
                reviewedToday: Int(graphs.today.answerCount),
                streak: streak,
                lastSevenDays: lastSevenDays
            )
        }

        func deckStatsSearch(for deckName: String) -> String {
            let escaped = deckName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "deck:\"\(escaped)\""
        }

        func fetchStudyStats(search: String) throws -> WidgetStudyStats {
            let graphData = try statsClient.fetchGraphs(search, 28)
            let graphs = try Anki_Stats_GraphsResponse(serializedBytes: graphData)
            return makeStudyStats(from: graphs)
        }

        // 1. Fetch deck list
        let decks: [DeckInfo] = try deckClient.fetchAll()

        // 2. Fetch all-decks stats once; per-deck widgets need their own queries.
        let allDeckStats = try fetchStudyStats(search: "")
        let now = Date()

        // 3. Write all-decks aggregate snapshot (deckId = 0)
        let allDecksSnapshot = WidgetSnapshot(
            deckId: 0,
            deckName: L("widget_all_decks"),
            newCount: decks.reduce(0) { $0 + $1.counts.newCount },
            learnCount: decks.reduce(0) { $0 + $1.counts.learnCount },
            reviewCount: decks.reduce(0) { $0 + $1.counts.reviewCount },
            reviewedToday: allDeckStats.reviewedToday,
            streak: allDeckStats.streak,
            lastSevenDays: allDeckStats.lastSevenDays,
            snapshotDate: now
        )
        try WidgetSnapshotStore.write(allDecksSnapshot)

        // 4. Write per-deck snapshots using per-deck stats queries.
        for deck in decks {
            let deckStats: WidgetStudyStats
            do {
                deckStats = try fetchStudyStats(search: deckStatsSearch(for: deck.name))
            } catch {
                print("[writeWidgetSnapshot] Deck stats failed for \(deck.name): \(error)")
                deckStats = .zero
            }

            let snapshot = WidgetSnapshot(
                deckId: deck.id,
                deckName: deck.name,
                newCount: deck.counts.newCount,
                learnCount: deck.counts.learnCount,
                reviewCount: deck.counts.reviewCount,
                reviewedToday: deckStats.reviewedToday,
                streak: deckStats.streak,
                lastSevenDays: deckStats.lastSevenDays,
                snapshotDate: now
            )
            try WidgetSnapshotStore.write(snapshot)
        }

        // 5. Tell WidgetKit to reload all widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    } catch {
        print("[writeWidgetSnapshot] Failed: \(error)")
    }
}
