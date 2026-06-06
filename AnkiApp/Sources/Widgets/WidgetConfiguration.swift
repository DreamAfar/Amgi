// AmgiApp/Sources/Widgets/WidgetConfiguration.swift
import AppIntents
import WidgetKit
import Foundation

struct DeckEntity: AppEntity {
    var id: String        // String(deckId) — Int64 doesn't conform to EntityIdentifier
    var name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "widget_intent_deck_type",
            defaultValue: "Deck",
            bundle: WidgetLocalization.bundle
        )
    )
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = DeckEntityQuery()
}

struct DeckEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DeckEntity] {
        WidgetSnapshotStore.allSnapshots().compactMap { snapshot in
            guard identifiers.contains(String(snapshot.deckId)) else { return nil }
            return DeckEntity(id: String(snapshot.deckId), name: snapshot.deckName)
        }
    }

    func suggestedEntities() async throws -> [DeckEntity] {
        WidgetSnapshotStore.allSnapshots().map { snapshot in
            DeckEntity(id: String(snapshot.deckId), name: snapshot.deckName)
        }
    }

    func defaultResult() async -> DeckEntity? {
        // Prefer the "All Decks" aggregate; fall back to first available snapshot
        let snapshots = WidgetSnapshotStore.allSnapshots()
        if let allDecks = snapshots.first(where: { $0.deckId == 0 }) {
            return DeckEntity(id: String(allDecks.deckId), name: allDecks.deckName)
        }
        if let first = snapshots.first {
            return DeckEntity(id: String(first.deckId), name: first.deckName)
        }
        return DeckEntity(id: "0", name: WL("widget_all_decks"))
    }
}

struct AmgiWidgetIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource(
        "widget_intent_choose_deck",
        defaultValue: "Choose Deck",
        bundle: WidgetLocalization.bundle
    )

    static let description = IntentDescription(
        LocalizedStringResource(
            "widget_intent_choose_deck_description",
            defaultValue: "Select which deck to display.",
            bundle: WidgetLocalization.bundle
        )
    )

    @Parameter(
        title: LocalizedStringResource(
            "widget_intent_deck_parameter",
            defaultValue: "Deck",
            bundle: WidgetLocalization.bundle
        )
    )
    var deck: DeckEntity?
}
