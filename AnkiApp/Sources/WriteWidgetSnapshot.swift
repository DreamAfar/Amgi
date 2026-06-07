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

    // ── Phase 1: Write base deck-count snapshots (always) ──────────────
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

    let now = Date()

    // ── Step 1: Write snapshots with deck counts only ──────────────────
    do {
        let decks: [DeckInfo] = try deckClient.fetchAll()

        // All-decks aggregate
        try WidgetSnapshotStore.write(WidgetSnapshot(
            deckId: 0,
            deckName: L("widget_all_decks"),
            newCount: decks.reduce(0) { $0 + $1.counts.newCount },
            learnCount: decks.reduce(0) { $0 + $1.counts.learnCount },
            reviewCount: decks.reduce(0) { $0 + $1.counts.reviewCount },
            reviewedToday: 0,
            streak: 0,
            lastSevenDays: Array(repeating: 0, count: 7),
            snapshotDate: now
        ))

        // Per-deck
        for deck in decks {
            try WidgetSnapshotStore.write(WidgetSnapshot(
                deckId: deck.id,
                deckName: deck.name,
                newCount: deck.counts.newCount,
                learnCount: deck.counts.learnCount,
                reviewCount: deck.counts.reviewCount,
                reviewedToday: 0,
                streak: 0,
                lastSevenDays: Array(repeating: 0, count: 7),
                snapshotDate: now
            ))
        }

        WidgetCenter.shared.reloadAllTimelines()
    } catch {
        print("[writeWidgetSnapshot] Phase 1 (counts) failed: \(error)")
        return
    }

    // ── Step 2: Enrich with study stats (best-effort) ─────────────────

    // All-decks stats — single sequential call, no concurrency needed.
    if let stats = try? fetchStudyStats(search: "") {
        updateSnapshot(deckId: 0, stats: stats)
    }

    // Per-deck: fire all queries concurrently with explicit capture list
    // to satisfy Swift 6 StrictConcurrency (local function fetchStudyStats
    // cannot be passed to a concurrent context).
    let decks: [DeckInfo]
    do {
        decks = try deckClient.fetchAll()
    } catch {
        print("[writeWidgetSnapshot] Phase 2 deck re-fetch failed: \(error)")
        return
    }

    let perDeckResults: [(Int64, WidgetStudyStats)] = await withTaskGroup(
        of: (Int64, WidgetStudyStats).self
    ) { group in
        for deck in decks {
            let search = deckStatsSearch(for: deck.name)
            let deckId = deck.id
            group.addTask { [statsClient] in
                if let graphData = try? statsClient.fetchGraphs(search, 28),
                   let graphs = try? Anki_Stats_GraphsResponse(serializedBytes: graphData) {
                    let stats = makeStudyStats(from: graphs)
                    return (deckId, stats)
                }
                return (deckId, .zero)
            }
        }
        var results: [(Int64, WidgetStudyStats)] = []
        for await result in group {
            results.append(result)
        }
        return results
    }

    let perDeckMap = Dictionary(uniqueKeysWithValues: perDeckResults)

    // Update per-deck snapshots with stats
    for deck in decks {
        let stats = perDeckMap[deck.id] ?? .zero
        updateSnapshot(deckId: deck.id, stats: stats)
    }

    WidgetCenter.shared.reloadAllTimelines()

    func updateSnapshot(deckId: Int64, stats: WidgetStudyStats) {
        guard var snap = WidgetSnapshotStore.read(deckId: deckId) else { return }
        snap.reviewedToday = stats.reviewedToday
        snap.streak = stats.streak
        snap.lastSevenDays = stats.lastSevenDays
        do {
            try WidgetSnapshotStore.write(snap)
        } catch {
            print("[writeWidgetSnapshot] Phase 2 update failed for deck \(deckId): \(error)")
        }
    }
}
