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
            getDeckConfig: { deckId in
                // Get the deck configuration using GetDeckConfigsForUpdate
                var req = Anki_Decks_DeckId()
                req.did = deckId
                
                logger.info("Loading deck config for deckId=\(deckId)")
                
                do {
                    let response: Anki_DeckConfig_DeckConfigsForUpdate = try backend.invoke(
                        service: AnkiBackend.Service.deckConfig,
                        method: AnkiBackend.DeckConfigMethod.getDeckConfigsForUpdate,
                        request: req
                    )
                    
                    logger.info("Got response with \(response.allConfig.count) configs, currentDeck=\(response.currentDeck.name), configID=\(response.currentDeck.configID)")
                    
                    if response.allConfig.isEmpty {
                        // No configs found - try to get a config directly by the deck's configID
                        // or return an empty default config (the backend will use defaults)
                        logger.warning("allConfig is empty for deckId=\(deckId), returning empty DeckConfig")
                        var emptyConfig = Anki_DeckConfig_DeckConfig()
                        emptyConfig.name = "Default"
                        return emptyConfig
                    }

                    // Match the current deck's active config first, then fallback to first.
                    let currentConfigId = response.currentDeck.configID
                    let config = response.allConfig.first(where: { $0.config.id == currentConfigId })?.config
                        ?? response.allConfig[0].config
                    logger.info("Retrieved deck config for deckId=\(deckId): configID=\(config.id), name=\(config.name)")
                    return config
                } catch {
                    logger.error("getDeckConfig failed for deckId=\(deckId): \(error)")
                    throw error
                }
            },
            updateDeckConfig: { deckId, config, applyToChildren in
                // Update the deck configuration
                var req = Anki_DeckConfig_UpdateDeckConfigsRequest()
                req.targetDeckID = deckId
                req.configs = [config]
                req.mode = applyToChildren ? .applyToChildren : .normal
                req.fsrs = !config.config.fsrsParams6.isEmpty
                
                do {
                    try backend.callVoid(
                        service: AnkiBackend.Service.deckConfig,
                        method: AnkiBackend.DeckConfigMethod.updateDeckConfigs,
                        request: req
                    )
                    logger.info("Updated deck config for deckId=\(deckId): \(config.name)")
                } catch {
                    logger.error("updateDeckConfig failed for deckId=\(deckId), config=\(config.name): \(error)")
                    throw error
                }
            }
        )
    }()
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
