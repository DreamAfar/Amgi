import AnkiBackend
public import AnkiProto
public import AnkiKit
public import Dependencies
import DependenciesMacros
import Foundation
import Logging

private let logger = Logger(label: "com.ankiapp.cards.service")

// MARK: - Card Mapping Helpers

@Sendable
package func mapCardRecord(from proto: Anki_Cards_Card) -> CardRecord {
    CardRecord(
        id: proto.id, nid: proto.noteID, did: proto.deckID,
        ord: Int32(proto.templateIdx), mod: proto.mtimeSecs,
        usn: proto.usn, type: Int16(proto.ctype),
        queue: Int16(proto.queue), due: proto.due,
        ivl: Int32(proto.interval), factor: Int32(proto.easeFactor),
        reps: Int32(proto.reps), lapses: Int32(proto.lapses),
        left: Int32(proto.remainingSteps), odue: proto.originalDue,
        odid: proto.originalDeckID, flags: Int32(proto.flags),
        data: proto.customData
    )
}

@Sendable
package func mapCardRecord(from queued: Anki_Scheduler_QueuedCards.QueuedCard) -> CardRecord? {
    guard queued.hasCard else { return nil }
    return mapCardRecord(from: queued.card)
}

// MARK: - Service

@DependencyClient
public struct CardsService: Sendable {
    // -- Read-only queries --

    /// Fetch all cards belonging to a note.
    public var fetchByNote: @Sendable (_ noteId: Int64) throws -> [CardRecord]

    /// Search cards by Anki search query.
    public var search: @Sendable (_ query: String) throws -> [CardRecord]

    // -- Single-card mutations (atomic backend calls) --

    /// Set flag (1=red, 2=orange, 3=green, 4=blue).
    public var setFlag: @Sendable (_ cardId: Int64, _ value: UInt32) throws -> Void

    /// Move card to a different deck.
    public var moveToDeck: @Sendable (_ cardId: Int64, _ deckId: Int64) throws -> Void

    /// Suspend a card.
    public var suspend: @Sendable (_ cardId: Int64) throws -> Void

    /// Unsuspend (restore) a card.
    public var unsuspend: @Sendable (_ cardId: Int64) throws -> Void

    /// Bury a card.
    public var bury: @Sendable (_ cardId: Int64) throws -> Void

    /// Unbury (restore) a card.
    public var unbury: @Sendable (_ cardId: Int64) throws -> Void

    /// Reset card to new state.
    public var resetToNew: @Sendable (_ cardId: Int64) throws -> Void

    /// Set due date for a card (days string, e.g. "5" or "5..10").
    public var setDueDate: @Sendable (_ cardId: Int64, _ days: String) throws -> Void

    // -- Collection-level --

    /// Undo last collection operation.
    public var undo: @Sendable () throws -> Void
}

// MARK: - Live Implementation

extension CardsService: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            fetchByNote: { noteId in
                var searchReq = Anki_Search_SearchRequest()
                searchReq.search = "nid:\(noteId)"

                let searchResponse: Anki_Search_SearchResponse = try backend.invoke(
                    service: AnkiBackend.Service.search,
                    method: AnkiBackend.SearchMethod.searchCards,
                    request: searchReq
                )

                logger.info("fetchByNote noteId=\(noteId): found \(searchResponse.ids.count) cards")

                var cards: [CardRecord] = []
                for cardId in searchResponse.ids.prefix(50) {
                    do {
                        var req = Anki_Cards_CardId()
                        req.cid = cardId
                        let card: Anki_Cards_Card = try backend.invoke(
                            service: AnkiBackend.Service.cards,
                            method: AnkiBackend.CardsMethod.getCard,
                            request: req
                        )
                        cards.append(mapCardRecord(from: card))
                    } catch {
                        logger.warning("fetchByNote: failed to fetch card \(cardId): \(error)")
                        continue
                    }
                }
                return cards
            },

            search: { query in
                var req = Anki_Search_SearchRequest()
                req.search = query

                let response: Anki_Search_SearchResponse = try backend.invoke(
                    service: AnkiBackend.Service.search,
                    method: AnkiBackend.SearchMethod.searchCards,
                    request: req
                )

                logger.info("search '\(query)': found \(response.ids.count) cards")

                var cards: [CardRecord] = []
                for cardId in response.ids {
                    do {
                        var cardReq = Anki_Cards_CardId()
                        cardReq.cid = cardId
                        let card: Anki_Cards_Card = try backend.invoke(
                            service: AnkiBackend.Service.cards,
                            method: AnkiBackend.CardsMethod.getCard,
                            request: cardReq
                        )
                        cards.append(mapCardRecord(from: card))
                    } catch {
                        logger.warning("search: failed to fetch card \(cardId): \(error)")
                        continue
                    }
                }
                return cards
            },

            setFlag: { cardId, value in
                var req = Anki_Cards_SetFlagRequest()
                req.cardIds = [cardId]
                req.flag = value
                try backend.callVoid(
                    service: AnkiBackend.Service.cards,
                    method: AnkiBackend.CardsMethod.setFlag,
                    request: req
                )
                logger.info("Card flagged: \(cardId) flag=\(value)")
            },

            moveToDeck: { cardId, deckId in
                var req = Anki_Cards_SetDeckRequest()
                req.cardIds = [cardId]
                req.deckID = deckId
                try backend.callVoid(
                    service: AnkiBackend.Service.cards,
                    method: AnkiBackend.CardsMethod.setDeck,
                    request: req
                )
                logger.info("Card \(cardId) moved to deck \(deckId)")
            },

            suspend: { cardId in
                var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
                req.cardIds = [cardId]
                req.mode = .suspend
                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.buryOrSuspendCards,
                    request: req
                )
                logger.info("Card suspended: \(cardId)")
            },

            unsuspend: { cardId in
                var req = Anki_Cards_CardIds()
                req.cids = [cardId]
                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.restoreBuriedAndSuspendedCards,
                    request: req
                )
                logger.info("Card unsuspended: \(cardId)")
            },

            bury: { cardId in
                var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
                req.cardIds = [cardId]
                req.mode = .buryUser
                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.buryOrSuspendCards,
                    request: req
                )
                logger.info("Card buried: \(cardId)")
            },

            unbury: { cardId in
                var req = Anki_Cards_CardIds()
                req.cids = [cardId]
                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.restoreBuriedAndSuspendedCards,
                    request: req
                )
                logger.info("Card unburied: \(cardId)")
            },

            resetToNew: { cardId in
                var req = Anki_Scheduler_ScheduleCardsAsNewRequest()
                req.cardIds = [cardId]
                req.log = true
                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.scheduleCardsAsNew,
                    request: req
                )
                logger.info("Card reset to new: \(cardId)")
            },

            setDueDate: { cardId, days in
                var req = Anki_Scheduler_SetDueDateRequest()
                req.cardIds = [cardId]
                req.days = days
                var configKey = Anki_Config_OptionalStringConfigKey()
                configKey.key = .setDueReviewer
                req.configKey = configKey
                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.setDueDate,
                    request: req
                )
                logger.info("Card due date set: \(cardId) -> \(days)")
            },

            undo: {
                _ = try backend.call(
                    service: AnkiBackend.Service.collection,
                    method: AnkiBackend.CollectionMethod.undo
                )
                logger.info("Undo completed")
            }
        )
    }()
}

// MARK: - Dependency Registration

extension CardsService: TestDependencyKey {
    public static let testValue = CardsService()
}

extension DependencyValues {
    public var cardsService: CardsService {
        get { self[CardsService.self] }
        set { self[CardsService.self] = newValue }
    }
}
