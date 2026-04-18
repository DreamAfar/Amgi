import AnkiKit
import AnkiBackend
import AnkiProto
public import Dependencies
import DependenciesMacros
import Foundation
import Logging
import SwiftProtobuf

private let logger = Logger(label: "com.ankiapp.deck.client")

extension DeckClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            fetchNamesOnly: {
                let req = Anki_Decks_GetDeckNamesRequest()
                let resp: Anki_Decks_DeckNames = try backend.invoke(
                    service: AnkiBackend.Service.decks,
                    method: AnkiBackend.DecksMethod.getDeckNames,
                    request: req
                )
                return resp.entries.map { DeckInfo(id: $0.id, name: $0.name, counts: .zero) }
                    .sorted(by: { $0.name < $1.name })
            },
            fetchAll: {
                // Try getDeckTree WITH timestamp for accurate counts
                var treeReq = Anki_Decks_DeckTreeRequest()
                treeReq.now = Int64(Date().timeIntervalSince1970)

                do {
                    let tree: Anki_Decks_DeckTreeNode = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.getDeckTree,
                        request: treeReq
                    )
                    let decks = flattenDeckTree(tree)
                    logger.info("DeckTree with counts: \(decks.count) decks")
                    for d in decks {
                        if d.counts.total > 0 {
                            logger.info("  [\(d.id)] \(d.name) — new:\(d.counts.newCount) learn:\(d.counts.learnCount) review:\(d.counts.reviewCount)")
                        }
                    }
                    return decks.sorted(by: { $0.name < $1.name })
                } catch {
                    // Fallback to getDeckNames without counts
                    logger.warning("getDeckTree failed (\(error)), falling back to getDeckNames")
                    let namesReq = Anki_Decks_GetDeckNamesRequest()
                    let namesResp: Anki_Decks_DeckNames = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.getDeckNames,
                        request: namesReq
                    )
                    return namesResp.entries.map { entry in
                        DeckInfo(id: entry.id, name: entry.name, counts: .zero)
                    }.sorted(by: { $0.name < $1.name })
                }
            },
            fetchTree: {
                var req = Anki_Decks_DeckTreeRequest()
                req.now = Int64(Date().timeIntervalSince1970)
                let tree: Anki_Decks_DeckTreeNode = try backend.invoke(
                    service: AnkiBackend.Service.decks,
                    method: AnkiBackend.DecksMethod.getDeckTree,
                    request: req
                )
                return tree.children.map { mapDeckTreeNode($0) }
            },
            countsForDeck: { deckId in
                // Use getDeckTree with timestamp — it calculates counts accurately
                var treeReq = Anki_Decks_DeckTreeRequest()
                treeReq.now = Int64(Date().timeIntervalSince1970)

                do {
                    let tree: Anki_Decks_DeckTreeNode = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.getDeckTree,
                        request: treeReq
                    )
                    // Find the deck in the tree
                    if let node = findNode(in: tree, deckId: deckId) {
                        let counts = DeckCounts(
                            newCount: Int(node.newCount),
                            learnCount: Int(node.learnCount),
                            reviewCount: Int(node.reviewCount)
                        )
                        logger.info("Counts for deck \(deckId): new=\(counts.newCount), learn=\(counts.learnCount), review=\(counts.reviewCount)")
                        return counts
                    }
                } catch {
                    logger.error("getDeckTree for counts failed: \(error)")
                }
                return .zero
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
                // Delete a deck using RemoveDecks
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
            fetchDeckConfigContext: { deckId in
                var req = Anki_Decks_DeckId()
                req.did = deckId

                return try backend.invoke(
                    service: AnkiBackend.Service.deckConfig,
                    method: AnkiBackend.DeckConfigMethod.getDeckConfigsForUpdate,
                    request: req
                )
            },
            getDeckConfig: { deckId in
                var req = Anki_Decks_DeckId()
                req.did = deckId

                logger.info("Loading deck config for deckId=\(deckId)")

                do {
                    let response: Anki_DeckConfig_DeckConfigsForUpdate = try backend.invoke(
                        service: AnkiBackend.Service.deckConfig,
                        method: AnkiBackend.DeckConfigMethod.getDeckConfigsForUpdate,
                        request: req
                    )

                    logger.info("Got response with \(response.allConfig.count) configs, currentDeck=\(response.currentDeck.name), configID=\(response.currentDeck.configID), fsrs=\(response.fsrs)")

                    let currentConfigId = response.currentDeck.configID
                    if currentConfigId != 0,
                       let matched = response.allConfig.first(where: { $0.config.id == currentConfigId })?.config {
                        logger.info("Retrieved deck config from allConfig for deckId=\(deckId): configID=\(matched.id), name=\(matched.name)")
                        return matched
                    }

                    if currentConfigId != 0 {
                        var configReq = Anki_DeckConfig_DeckConfigId()
                        configReq.dcid = currentConfigId
                        let config: Anki_DeckConfig_DeckConfig = try backend.invoke(
                            service: AnkiBackend.Service.deckConfig,
                            method: AnkiBackend.DeckConfigMethod.getDeckConfig,
                            request: configReq
                        )
                        logger.info("Loaded deck config directly for deckId=\(deckId): configID=\(config.id), name=\(config.name)")
                        return config
                    }

                    if response.hasDefaults {
                        logger.warning("Deck \(deckId) has configID=0; using response.defaults as fallback")
                        return response.defaults
                    }

                    throw BackendError(
                        kind: .invalidInput,
                        message: "Deck \(deckId) has no valid config id and no defaults returned"
                    )
                } catch {
                    let primaryError = error
                    logger.warning("GetDeckConfigsForUpdate failed for deckId=\(deckId), falling back to direct deck lookup: \(primaryError)")

                    do {
                        let deck: Anki_Decks_Deck = try backend.invoke(
                            service: AnkiBackend.Service.decks,
                            method: AnkiBackend.DecksMethod.getDeck,
                            request: req
                        )

                        guard case .normal(let normalDeck)? = deck.kind else {
                            throw BackendError(
                                kind: .invalidInput,
                                message: "Study options are only available for normal decks."
                            )
                        }

                        var configReq = Anki_DeckConfig_DeckConfigId()
                        configReq.dcid = normalDeck.configID
                        let config: Anki_DeckConfig_DeckConfig = try backend.invoke(
                            service: AnkiBackend.Service.deckConfig,
                            method: AnkiBackend.DeckConfigMethod.getDeckConfig,
                            request: configReq
                        )
                        logger.info("Loaded deck config via direct deck lookup for deckId=\(deckId): configID=\(config.id), name=\(config.name)")
                        return config
                    } catch {
                        let fallbackError = error
                        logger.error("getDeckConfig failed for deckId=\(deckId): primary=\(primaryError), fallback=\(fallbackError)")
                        throw BackendError(
                            kind: .invalidInput,
                            message: "Failed to load study options for deck \(deckId). Primary error: \(primaryError.localizedDescription). Fallback error: \(fallbackError.localizedDescription)"
                        )
                    }
                }
            },
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
            updateDeckConfig: { deckId, config, applyToChildren, fsrsEnabled in
                let context = try deckConfigContext(backend: backend, deckId: deckId)
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
            getRetentionWorkload: { weights, search in
                var req = Anki_DeckConfig_GetRetentionWorkloadRequest()
                req.w = weights
                req.search = search

                let response: Anki_DeckConfig_GetRetentionWorkloadResponse = try backend.invoke(
                    service: AnkiBackend.Service.deckConfig,
                    method: AnkiBackend.DeckConfigMethod.getRetentionWorkload,
                    request: req
                )
                return response.costs
            },
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

private func flattenDeckTree(_ node: Anki_Decks_DeckTreeNode, parentPath: String = "") -> [DeckInfo] {
    var result: [DeckInfo] = []
    for child in node.children {
        let fullPath = parentPath.isEmpty ? child.name : "\(parentPath)::\(child.name)"
        result.append(DeckInfo(
            id: child.deckID,
            name: fullPath,
            counts: DeckCounts(
                newCount: Int(child.newCount),
                learnCount: Int(child.learnCount),
                reviewCount: Int(child.reviewCount)
            )
        ))
        result.append(contentsOf: flattenDeckTree(child, parentPath: fullPath))
    }
    return result
}

private func findNode(in node: Anki_Decks_DeckTreeNode, deckId: Int64) -> Anki_Decks_DeckTreeNode? {
    if node.deckID == deckId { return node }
    for child in node.children {
        if let found = findNode(in: child, deckId: deckId) { return found }
    }
    return nil
}

private func mapDeckTreeNode(_ node: Anki_Decks_DeckTreeNode, parentPath: String = "") -> DeckTreeNode {
    let fullPath = parentPath.isEmpty ? node.name : "\(parentPath)::\(node.name)"
    return DeckTreeNode(
        id: node.deckID,
        name: node.name,
        fullName: fullPath,
        counts: DeckCounts(
            newCount: Int(node.newCount),
            learnCount: Int(node.learnCount),
            reviewCount: Int(node.reviewCount)
        ),
        children: node.children.map { mapDeckTreeNode($0, parentPath: fullPath) }
    )
}
