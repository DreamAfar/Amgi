import AnkiKit
import AnkiBackend
import AnkiProto
import Foundation
public import Dependencies
import DependenciesMacros
import Logging

private let logger = Logger(label: "com.ankiapp.card.client")

extension CardClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            fetchDue: { deckId in
                // Set the current deck so the scheduler knows which deck to study
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

                // Verify the deck was actually set
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

                    logger.info("QueuedCards for deckId=\(deckId): \(response.cards.count) cards, new=\(response.newCount), learn=\(response.learningCount), review=\(response.reviewCount)")

                    let cards = response.cards.compactMap { queued -> CardRecord? in
                        guard queued.hasCard else {
                            logger.warning("Queued entry missing card data")
                            return nil
                        }
                        let c = queued.card
                        return CardRecord(
                            id: c.id, nid: c.noteID, did: c.deckID,
                            ord: Int32(c.templateIdx), mod: c.mtimeSecs,
                            usn: c.usn, type: Int16(c.ctype),
                            queue: Int16(c.queue), due: c.due,
                            ivl: Int32(c.interval), factor: Int32(c.easeFactor),
                            reps: Int32(c.reps), lapses: Int32(c.lapses),
                            left: Int32(c.remainingSteps), odue: c.originalDue,
                            odid: c.originalDeckID, flags: Int32(c.flags),
                            data: c.customData
                        )
                    }

                    if cards.isEmpty && (response.newCount > 0 || response.learningCount > 0 || response.reviewCount > 0) {
                        logger.error("Backend reports cards available (new=\(response.newCount), learn=\(response.learningCount), review=\(response.reviewCount)) but QueuedCards list is empty")
                    }

                    return cards
                } catch {
                    logger.error("fetchDue failed for deckId=\(deckId): \(error)")
                    throw error
                }
            },
            fetchByNote: { noteId in
                // Search for cards by note using search RPC
                var searchReq = Anki_Search_SearchRequest()
                searchReq.search = "nid:\(noteId)"
                
                do {
                    let searchResponse: Anki_Search_SearchResponse = try backend.invoke(
                        service: AnkiBackend.Service.search,
                        method: AnkiBackend.SearchMethod.searchCards,
                        request: searchReq
                    )
                    
                    logger.info("Found \(searchResponse.ids.count) cards for noteId=\(noteId)")
                    
                    // Convert card IDs to CardRecord objects by fetching each card
                    // This is a simplified implementation; optimize with batch fetch if needed
                    var cards: [CardRecord] = []
                    for cardId in searchResponse.ids.prefix(50) {  // Limit to 50 per call
                        do {
                            var req = Anki_Cards_CardId()
                            req.cid = cardId
                            let card: Anki_Cards_Card = try backend.invoke(
                                service: AnkiBackend.Service.cards,
                                method: AnkiBackend.CardsMethod.getCard,
                                request: req
                            )
                            cards.append(CardRecord(
                                id: card.id, nid: card.noteID, did: card.deckID,
                                ord: Int32(card.templateIdx), mod: card.mtimeSecs,
                                usn: card.usn, type: Int16(card.ctype),
                                queue: Int16(card.queue), due: card.due,
                                ivl: Int32(card.interval), factor: Int32(card.easeFactor),
                                reps: Int32(card.reps), lapses: Int32(card.lapses),
                                left: Int32(card.remainingSteps), odue: card.originalDue,
                                odid: card.originalDeckID, flags: Int32(card.flags),
                                data: card.customData
                            ))
                        } catch {
                            logger.warning("Failed to fetch card \(cardId): \(error)")
                            continue
                        }
                    }
                    return cards
                } catch {
                    logger.error("fetchByNote failed for noteId=\(noteId): \(error)")
                    throw error
                }
            },
            save: { card in
                // Rust owns the DB; no direct writes needed
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
            undo: {
                do {
                    _ = try backend.call(
                        service: AnkiBackend.Service.collection,
                        method: AnkiBackend.CollectionMethod.undo
                    )
                    logger.info("Card undo completed")
                } catch {
                    logger.error("Undo failed: \(error)")
                    throw error
                }
            },
            suspend: { cardId in
                var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
                req.cardIds = [cardId]
                req.mode = .suspend
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.scheduler,
                        method: AnkiBackend.SchedulerMethod.buryOrSuspendCards,
                        request: req
                    )
                    logger.info("Card suspended: \(cardId)")
                } catch {
                    logger.error("Suspend failed for cardId=\(cardId): \(error)")
                    throw error
                }
            },
            unsuspend: { cardId in
                var req = Anki_Cards_CardIds()
                req.cids = [cardId]
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.scheduler,
                        method: AnkiBackend.SchedulerMethod.restoreBuriedAndSuspendedCards,
                        request: req
                    )
                    logger.info("Card unsuspended: \(cardId)")
                } catch {
                    logger.error("Unsuspend failed for cardId=\(cardId): \(error)")
                    throw error
                }
            },
            bury: { cardId in
                var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
                req.cardIds = [cardId]
                req.mode = .buryUser
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.scheduler,
                        method: AnkiBackend.SchedulerMethod.buryOrSuspendCards,
                        request: req
                    )
                    logger.info("Card buried: \(cardId)")
                } catch {
                    logger.error("Bury failed for cardId=\(cardId): \(error)")
                    throw error
                }
            },
            flag: { cardId, flag in
                var req = Anki_Cards_SetFlagRequest()
                req.cardIds = [cardId]
                req.flag = flag
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.cards,
                        method: AnkiBackend.CardsMethod.setFlag,
                        request: req
                    )
                    logger.info("Card flagged: \(cardId) with flag=\(flag)")
                } catch {
                    logger.error("Flag failed for cardId=\(cardId): \(error)")
                    throw error
                }
            },
            moveToDeck: { cardId, deckId in
                var req = Anki_Cards_SetDeckRequest()
                req.cardIds = [cardId]
                req.deckID = deckId
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.cards,
                        method: AnkiBackend.CardsMethod.setDeck,
                        request: req
                    )
                    logger.info("Card \(cardId) moved to deck \(deckId)")
                } catch {
                    logger.error("MoveToDeck failed for cardId=\(cardId): \(error)")
                    throw error
                }
            },
            resetToNew: { cardId in
                var req = Anki_Scheduler_ScheduleCardsAsNewRequest()
                req.cardIds = [cardId]
                req.log = true
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.scheduler,
                        method: AnkiBackend.SchedulerMethod.scheduleCardsAsNew,
                        request: req
                    )
                    logger.info("Card reset to new: \(cardId)")
                } catch {
                    logger.error("ResetToNew failed for cardId=\(cardId): \(error)")
                    throw error
                }
            },
            search: { query in
                // Search cards using the search service
                var req = Anki_Search_SearchRequest()
                req.search = query
                
                do {
                    let response: Anki_Search_SearchResponse = try backend.invoke(
                        service: AnkiBackend.Service.search,
                        method: AnkiBackend.SearchMethod.searchCards,
                        request: req
                    )
                    
                    logger.info("Card search for '\(query)': found \(response.ids.count) cards")
                    
                    // Convert card IDs to CardRecord objects
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
                            cards.append(CardRecord(
                                id: card.id, nid: card.noteID, did: card.deckID,
                                ord: Int32(card.templateIdx), mod: card.mtimeSecs,
                                usn: card.usn, type: Int16(card.ctype),
                                queue: Int16(card.queue), due: card.due,
                                ivl: Int32(card.interval), factor: Int32(card.easeFactor),
                                reps: Int32(card.reps), lapses: Int32(card.lapses),
                                left: Int32(card.remainingSteps), odue: card.originalDue,
                                odid: card.originalDeckID, flags: Int32(card.flags),
                                data: card.customData
                            ))
                        } catch {
                            logger.warning("Failed to fetch card \(cardId): \(error)")
                            continue
                        }
                    }
                    return cards
                } catch {
                    logger.error("Card search failed for '\(query)': \(error)")
                    throw error
                }
            }
        )
    }()
}
