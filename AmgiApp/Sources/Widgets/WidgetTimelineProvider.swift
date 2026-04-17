// AmgiApp/Sources/Widgets/WidgetTimelineProvider.swift
import WidgetKit
import Foundation

struct WidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct WidgetTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = AmgiWidgetIntent
    typealias Entry = WidgetEntry

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func snapshot(for configuration: AmgiWidgetIntent, in context: Context) async -> WidgetEntry {
        let deckId = Int64(configuration.deck?.id ?? "0") ?? 0
        let snapshot = WidgetSnapshotStore.read(deckId: deckId) ?? .placeholder
        return WidgetEntry(date: Date(), snapshot: snapshot)
    }

    func timeline(for configuration: AmgiWidgetIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let deckId = Int64(configuration.deck?.id ?? "0") ?? 0
        // Distinguish between "found a snapshot" and "fell back to placeholder".
        // Freshness / reload policy must be based on the real snapshot date, not
        // the placeholder's Date() which would always look like "today".
        let maybeSnapshot = WidgetSnapshotStore.read(deckId: deckId)
        let snapshot = maybeSnapshot ?? .placeholder
        let cal = Calendar.current
        let now = Date()

        var entries: [WidgetEntry] = [WidgetEntry(date: now, snapshot: snapshot)]

        // Generate a midnight entry so reviewedToday corrects to 0 when the day rolls over,
        // and the bar chart shifts forward by one day without requiring an app open.
        // Only add this entry when we have a real, fresh snapshot — not for the placeholder.
        let nextMidnight = cal.startOfDay(
            for: cal.date(byAdding: .day, value: 1, to: now) ?? now
        )
        if let real = maybeSnapshot, cal.isDateInToday(real.snapshotDate) {
            let shiftedDays = Array(real.lastSevenDays.dropFirst()) + [0]
            let midnightSnapshot = WidgetSnapshot(
                deckId: real.deckId,
                deckName: real.deckName,
                newCount: real.newCount,
                learnCount: real.learnCount,
                reviewCount: real.reviewCount,
                reviewedToday: 0,
                streak: real.streak,
                lastSevenDays: shiftedDays,
                snapshotDate: nextMidnight
            )
            entries.append(WidgetEntry(date: nextMidnight, snapshot: midnightSnapshot))
        }

        // Request a full reload 15 minutes after midnight when we have a fresh snapshot.
        // Poll every 5 minutes if there is no snapshot yet or the snapshot is stale,
        // so the widget self-corrects quickly once the app writes fresh data.
        let reloadAfter: Date
        if let real = maybeSnapshot, cal.isDateInToday(real.snapshotDate) {
            reloadAfter = cal.date(byAdding: .minute, value: 15, to: nextMidnight) ?? nextMidnight
        } else {
            reloadAfter = cal.date(byAdding: .minute, value: 5, to: now) ?? now
        }

        return Timeline(entries: entries, policy: .after(reloadAfter))
    }
}
