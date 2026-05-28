import AnkiKit
import AnkiBackend
import AnkiProto
import AnkiServices
import Foundation
public import Dependencies
import DependenciesMacros
import Logging

private let logger = Logger(label: "com.ankiapp.card.client")

extension CardClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        @Dependency(\.cardsService) var cards

        return Self(
            // MARK: Orchestration (cross-service)
            fetchDue: { deckId in
                var deckReq = Anki_Decks_DeckId()
                deckReq.did = deckId
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.setCurrentDeck,
                        request: deckReq
                    )
                    logger.info("Set current deck to \(deckId)")
                } catch {
                    logger.error("setCurrentDeck failed for deckId=\(deckId): \(error)")
                    throw error
                }

                do {
                    let currentDeck: Anki_Decks_Deck = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.getCurrentDeck,
                        request: Anki_Generic_Empty()
                    )
                    logger.info("Verified current deck: id=\(currentDeck.id), name=\(currentDeck.name)")
                } catch {
                    logger.warning("Could not verify current deck (non-fatal): \(error)")
                }

                var req = Anki_Scheduler_GetQueuedCardsRequest()
                req.fetchLimit = 50

                do {
                    let response: Anki_Scheduler_QueuedCards = try backend.invoke(
                        service: AnkiBackend.Service.scheduler,
                        method: AnkiBackend.SchedulerMethod.getQueuedCards,
                        request: req
                    )

                    logger.info("QueuedCards for deckId=\(deckId): \(response.cards.count) cards")

                    let cards = response.cards.compactMap(mapCardRecord(from:))

                    if cards.isEmpty && (response.newCount > 0 || response.learningCount > 0 || response.reviewCount > 0) {
                        logger.error("Backend reports cards available but QueuedCards list is empty")
                    }

                    return cards
                } catch {
                    logger.error("fetchDue failed for deckId=\(deckId): \(error)")
                    throw error
                }
            },

            answer: { cardId, rating, timeSpent in
                var answer = Anki_Scheduler_CardAnswer()
                answer.cardID = cardId
                answer.rating = switch rating {
                case .again: .again
                case .hard: .hard
                case .good: .good
                case .easy: .easy
                }
                answer.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
                answer.millisecondsTaken = UInt32(timeSpent)

                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.answerCard,
                    request: answer
                )
            },

            save: { _ in
                // Rust owns the DB; no direct writes needed
            },

            // MARK: Delegated to CardsService
            fetchByNote: { try cards.fetchByNote($0) },
            undo:          { try cards.undo() },
            suspend:       { try cards.suspend($0) },
            unsuspend:     { try cards.unsuspend($0) },
            bury:          { try cards.bury($0) },
            unbury:        { try cards.unbury($0) },
            flag:          { try cards.setFlag($0, $1) },
            moveToDeck:    { try cards.moveToDeck($0, $1) },
            resetToNew:    { try cards.resetToNew($0) },
            setDueDate:    { try cards.setDueDate($0, $1) },
            search:        { try cards.search($0) }
        )
    }()
}
