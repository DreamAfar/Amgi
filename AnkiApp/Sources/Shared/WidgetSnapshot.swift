// AmgiApp/Sources/Shared/WidgetSnapshot.swift
import Foundation

public struct WidgetSnapshot: Codable, Sendable {
    public var deckId: Int64
    public var deckName: String
    public var newCount: Int
    public var learnCount: Int
    public var reviewCount: Int
    public var reviewedToday: Int
    public var streak: Int
    public var lastSevenDays: [Int]   // index 0 = 6 days ago, index 6 = today
    public var snapshotDate: Date

    public var totalDue: Int { newCount + learnCount + reviewCount }

    public static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            deckId: 0,
            deckName: "All Decks",
            newCount: 5,
            learnCount: 8,
            reviewCount: 22,
            reviewedToday: 18,
            streak: 7,
            lastSevenDays: [20, 15, 22, 18, 25, 12, 8],
            snapshotDate: Date()
        )
    }
}
