import AnkiKit
import AnkiBackend
import AnkiProto
import AnkiServices
public import Dependencies
import DependenciesMacros
import Foundation
import Logging
import SwiftProtobuf

private let logger = Logger(label: "com.ankiapp.deck.client")

// MARK: - Shared helpers (used by write operations below)

private func deckConfigContext(
    backend: AnkiBackend,
    deckId: Int64
) throws -> Anki_DeckConfig_DeckConfigsForUpdate {
    var req = Anki_Decks_DeckId()
    req.did = deckId
    return try backend.invoke(
        service: AnkiBackend.Service.deckConfig,
        method: AnkiBackend.DeckConfigMethod.getDeckConfigsForUpdate,
        request: req
    )
}

private func makeDeckConfigUpdateRequest(
    deckId: Int64,
    context: Anki_DeckConfig_DeckConfigsForUpdate,
    configs: [Anki_DeckConfig_DeckConfig],
    removedConfigIds: [Int64],
    mode: Anki_DeckConfig_UpdateDeckConfigsMode,
    fsrsEnabled: Bool
) -> Anki_DeckConfig_UpdateDeckConfigsRequest {
    var req = Anki_DeckConfig_UpdateDeckConfigsRequest()
    req.targetDeckID = deckId
    req.configs = configs
    req.removedConfigIds = removedConfigIds
    req.mode = mode
    req.cardStateCustomizer = context.cardStateCustomizer
    req.newCardsIgnoreReviewLimit = context.newCardsIgnoreReviewLimit
    req.applyAllParentLimits = context.applyAllParentLimits
    req.fsrsHealthCheck = context.fsrsHealthCheck
    req.fsrs = fsrsEnabled
    if context.currentDeck.hasLimits {
        req.limits = context.currentDeck.limits
    }
    return req
}

// MARK: - Live Implementation

extension DeckClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        @Dependency(\.deckService) var decks

        return Self(
            fetchAll:                { try decks.fetchAll() },
            fetchNamesOnly:          { try decks.fetchNamesOnly() },
            fetchDeck:               { try decks.fetchDeck($0) },
            fetchCurrentDeck:        { try decks.fetchCurrentDeck() },
            fetchTree:               { try decks.fetchTree() },
            countsForDeck:           { try decks.countsForDeck($0) },
            fetchCustomStudyDefaults: { try decks.fetchCustomStudyDefaults($0) },
            customStudy: { request in
                try backend.callVoid(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.customStudy,
                    request: request
                )
                return try backend.invoke(
                    service: AnkiBackend.Service.decks,
                    method: AnkiBackend.DecksMethod.getCurrentDeck,
                    request: Anki_Generic_Empty()
                )
            },
            create: { name in
                // Create a new deck using AddDeck
                var deck = Anki_Decks_Deck()
                deck.name = name
                // Backend requires deck.kind to be set.
                deck.normal = Anki_Decks_Deck.Normal()
                
                do {
                    let resp: Anki_Collection_OpChangesWithId = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.addDeck,
                        request: deck
                    )
                    logger.info("Created deck '\(name)' with ID: \(resp.id)")
                    return resp.id
                } catch {
                    logger.error("create deck failed for '\(name)': \(error)")
                    throw error
                }
            },
            rename: { deckId, name in
                // Rename a deck
                var req = Anki_Decks_RenameDeckRequest()
                req.deckID = deckId
                req.newName = name
                
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.renameDeck,
                        request: req
                    )
                    logger.info("Renamed deck \(deckId) to '\(name)'")
                } catch {
                    logger.error("rename deck failed: \(error)")
                    throw error
                }
            },
            delete: { deckId in
                var req = Anki_Decks_DeckIds()
                req.dids.append(deckId)
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.removeDecks,
                        request: req
                    )
                    logger.info("Deleted deck \(deckId)")
                } catch {
                    logger.error("delete deck failed: \(error)")
                    throw error
                }
            },
            fetchDeckConfigContext:  { try decks.fetchDeckConfigContext($0) },
            getDeckConfig:           { try decks.getDeckConfig($0) },
            selectDeckPreset: { deckId, config, applyToChildren in
                let context = try deckConfigContext(backend: backend, deckId: deckId)
                let req = makeDeckConfigUpdateRequest(
                    deckId: deckId,
                    context: context,
                    configs: [config],
                    removedConfigIds: [],
                    mode: applyToChildren ? .applyToChildren : .normal,
                    fsrsEnabled: context.fsrs
                )

                try backend.callVoid(
                    service: AnkiBackend.Service.deckConfig,
                    method: AnkiBackend.DeckConfigMethod.updateDeckConfigs,
                    request: req
                )
            },
            createDeckPreset: { deckId, baseConfig, name, applyToChildren in
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else {
                    throw BackendError(kind: .invalidInput, message: "Preset name can't be empty")
                }

                let context = try deckConfigContext(backend: backend, deckId: deckId)
                var newConfig = baseConfig
                newConfig.id = 0
                newConfig.name = trimmedName

                let req = makeDeckConfigUpdateRequest(
                    deckId: deckId,
                    context: context,
                    configs: [newConfig],
                    removedConfigIds: [],
                    mode: applyToChildren ? .applyToChildren : .normal,
                    fsrsEnabled: context.fsrs
                )

                try backend.callVoid(
                    service: AnkiBackend.Service.deckConfig,
                    method: AnkiBackend.DeckConfigMethod.updateDeckConfigs,
                    request: req
                )
            },
            deleteDeckPreset: { deckId, removingConfigId, fallbackConfig, applyToChildren in
                guard removingConfigId != fallbackConfig.id else {
                    throw BackendError(kind: .invalidInput, message: "Fallback preset must differ from removed preset")
                }

                let context = try deckConfigContext(backend: backend, deckId: deckId)
                let req = makeDeckConfigUpdateRequest(
                    deckId: deckId,
                    context: context,
                    configs: [fallbackConfig],
                    removedConfigIds: [removingConfigId],
                    mode: applyToChildren ? .applyToChildren : .normal,
                    fsrsEnabled: context.fsrs
                )

                try backend.callVoid(
                    service: AnkiBackend.Service.deckConfig,
                    method: AnkiBackend.DeckConfigMethod.updateDeckConfigs,
                    request: req
                )
            },
            updateDeckConfig: { deckId, config, applyToChildren, fsrsEnabled, newCardsIgnoreReviewLimit, applyAllParentLimits, fsrsHealthCheck in
                var context = try deckConfigContext(backend: backend, deckId: deckId)
                context.newCardsIgnoreReviewLimit = newCardsIgnoreReviewLimit
                context.applyAllParentLimits = applyAllParentLimits
                context.fsrsHealthCheck = fsrsHealthCheck
                let req = makeDeckConfigUpdateRequest(
                    deckId: deckId,
                    context: context,
                    configs: [config],
                    removedConfigIds: [],
                    mode: applyToChildren ? .applyToChildren : .normal,
                    fsrsEnabled: fsrsEnabled
                )
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.deckConfig,
                        method: AnkiBackend.DeckConfigMethod.updateDeckConfigs,
                        request: req
                    )
                    logger.info("Updated deck config for deckId=\(deckId): \(config.name), fsrs=\(fsrsEnabled)")
                } catch {
                    logger.error("updateDeckConfig failed for deckId=\(deckId), config=\(config.name): \(error)")
                    throw error
                }
            },
            getRetentionWorkload:  { try decks.getRetentionWorkload($0, $1) },
            computeFsrsParams:     { try decks.computeFsrsParams($0) },
            simulateFsrsReview:    { try decks.simulateFsrsReview($0) },
            simulateFsrsWorkload:  { try decks.simulateFsrsWorkload($0) },
            optimizeFsrsPresets: { deckId, selectedConfig in
                let context = try deckConfigContext(backend: backend, deckId: deckId)
                let req = makeDeckConfigUpdateRequest(
                    deckId: deckId,
                    context: context,
                    configs: [selectedConfig],
                    removedConfigIds: [],
                    mode: .computeAllParams,
                    fsrsEnabled: true
                )
                try backend.callVoid(
                    service: AnkiBackend.Service.deckConfig,
                    method: AnkiBackend.DeckConfigMethod.updateDeckConfigs,
                    request: req
                )
            }
        )
    }()
}
