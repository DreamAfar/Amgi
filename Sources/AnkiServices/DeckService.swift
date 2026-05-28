import AnkiBackend
public import AnkiProto
public import AnkiKit
public import Dependencies
import DependenciesMacros
import Foundation
import Logging

private let logger = Logger(label: "com.ankiapp.decks.service")

// MARK: - Service (read-only queries)

@DependencyClient
public struct DeckService: Sendable {
    /// All decks with review counts (prefers getDeckTree with timestamp).
    public var fetchAll: @Sendable () throws -> [DeckInfo]

    /// Deck id+name only, no review counts. Lightweight for filter menus.
    public var fetchNamesOnly: @Sendable () throws -> [DeckInfo]

    /// Fetch a single deck as raw proto.
    public var fetchDeck: @Sendable (_ deckId: Int64) throws -> Anki_Decks_Deck

    /// Fetch the currently selected deck.
    public var fetchCurrentDeck: @Sendable () throws -> Anki_Decks_Deck

    /// Deck tree with children and counts.
    public var fetchTree: @Sendable () throws -> [DeckTreeNode]

    /// Review counts for a specific deck.
    public var countsForDeck: @Sendable (_ deckId: Int64) throws -> DeckCounts

    /// Custom study defaults for a deck.
    public var fetchCustomStudyDefaults: @Sendable (_ deckId: Int64) throws -> Anki_Scheduler_CustomStudyDefaultsResponse

    /// Deck config context (for update — read phase).
    public var fetchDeckConfigContext: @Sendable (_ deckId: Int64) throws -> Anki_DeckConfig_DeckConfigsForUpdate

    /// Resolve the effective deck config for a deck.
    public var getDeckConfig: @Sendable (_ deckId: Int64) throws -> Anki_DeckConfig_DeckConfig

    /// Retention workload chart data.
    public var getRetentionWorkload: @Sendable (_ weights: [Float], _ search: String) throws -> [UInt32: Float]

    /// Compute FSRS parameters.
    public var computeFsrsParams: @Sendable (_ request: Anki_Scheduler_ComputeFsrsParamsRequest) throws -> Anki_Scheduler_ComputeFsrsParamsResponse

    /// Simulate FSRS review schedule.
    public var simulateFsrsReview: @Sendable (_ request: Anki_Scheduler_SimulateFsrsReviewRequest) throws -> Anki_Scheduler_SimulateFsrsReviewResponse

    /// Simulate FSRS workload.
    public var simulateFsrsWorkload: @Sendable (_ request: Anki_Scheduler_SimulateFsrsReviewRequest) throws -> Anki_Scheduler_SimulateFsrsWorkloadResponse
}

// MARK: - Live Implementation

extension DeckService: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        return Self(
            fetchAll: {
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
                    return decks.sorted { $0.name < $1.name }
                } catch {
                    logger.warning("getDeckTree failed (\(error)), falling back to getDeckNames")
                    let namesReq = Anki_Decks_GetDeckNamesRequest()
                    let namesResp: Anki_Decks_DeckNames = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.getDeckNames,
                        request: namesReq
                    )
                    return namesResp.entries.map {
                        DeckInfo(id: $0.id, name: $0.name, counts: .zero)
                    }.sorted { $0.name < $1.name }
                }
            },

            fetchNamesOnly: {
                let req = Anki_Decks_GetDeckNamesRequest()
                let resp: Anki_Decks_DeckNames = try backend.invoke(
                    service: AnkiBackend.Service.decks,
                    method: AnkiBackend.DecksMethod.getDeckNames,
                    request: req
                )
                return resp.entries.map { DeckInfo(id: $0.id, name: $0.name, counts: .zero) }
                    .sorted { $0.name < $1.name }
            },

            fetchDeck: { deckId in
                var req = Anki_Decks_DeckId()
                req.did = deckId
                return try backend.invoke(
                    service: AnkiBackend.Service.decks,
                    method: AnkiBackend.DecksMethod.getDeck,
                    request: req
                )
            },

            fetchCurrentDeck: {
                try backend.invoke(
                    service: AnkiBackend.Service.decks,
                    method: AnkiBackend.DecksMethod.getCurrentDeck,
                    request: Anki_Generic_Empty()
                )
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
                var treeReq = Anki_Decks_DeckTreeRequest()
                treeReq.now = Int64(Date().timeIntervalSince1970)

                do {
                    let tree: Anki_Decks_DeckTreeNode = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.getDeckTree,
                        request: treeReq
                    )
                    if let node = findNode(in: tree, deckId: deckId) {
                        return DeckCounts(
                            newCount: Int(node.newCount),
                            learnCount: Int(node.learnCount),
                            reviewCount: Int(node.reviewCount)
                        )
                    }
                } catch {
                    logger.error("getDeckTree for counts failed: \(error)")
                }
                return .zero
            },

            fetchCustomStudyDefaults: { deckId in
                var req = Anki_Scheduler_CustomStudyDefaultsRequest()
                req.deckID = deckId
                return try backend.invoke(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.customStudyDefaults,
                    request: req
                )
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

                    let currentConfigId = response.currentDeck.configID
                    if currentConfigId != 0,
                       let matched = response.allConfig.first(where: { $0.config.id == currentConfigId })?.config {
                        return matched
                    }

                    if currentConfigId != 0 {
                        var configReq = Anki_DeckConfig_DeckConfigId()
                        configReq.dcid = currentConfigId
                        return try backend.invoke(
                            service: AnkiBackend.Service.deckConfig,
                            method: AnkiBackend.DeckConfigMethod.getDeckConfig,
                            request: configReq
                        )
                    }

                    if response.hasDefaults {
                        logger.warning("Deck \(deckId) has configID=0; using defaults as fallback")
                        return response.defaults
                    }

                    throw BackendError(kind: .invalidInput, message: "Deck \(deckId) has no valid config")
                } catch {
                    logger.warning("getDeckConfig fallback via direct deck lookup for deckId=\(deckId)")
                    let deck: Anki_Decks_Deck = try backend.invoke(
                        service: AnkiBackend.Service.decks,
                        method: AnkiBackend.DecksMethod.getDeck,
                        request: req
                    )
                    guard case .normal(let normalDeck)? = deck.kind else {
                        throw BackendError(kind: .invalidInput, message: "Study options only for normal decks")
                    }
                    var configReq = Anki_DeckConfig_DeckConfigId()
                    configReq.dcid = normalDeck.configID
                    return try backend.invoke(
                        service: AnkiBackend.Service.deckConfig,
                        method: AnkiBackend.DeckConfigMethod.getDeckConfig,
                        request: configReq
                    )
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

            computeFsrsParams: { request in
                try backend.invoke(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.computeFsrsParams,
                    request: request
                )
            },

            simulateFsrsReview: { request in
                try backend.invoke(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.simulateFsrsReview,
                    request: request
                )
            },

            simulateFsrsWorkload: { request in
                try backend.invoke(
                    service: AnkiBackend.Service.scheduler,
                    method: AnkiBackend.SchedulerMethod.simulateFsrsWorkload,
                    request: request
                )
            }
        )
    }()
}

// MARK: - Dependency Registration

extension DeckService: TestDependencyKey {
    public static let testValue = DeckService()
}

extension DependencyValues {
    public var deckService: DeckService {
        get { self[DeckService.self] }
        set { self[DeckService.self] = newValue }
    }
}

// MARK: - Shared Helpers

func deckConfigContext(
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

func makeDeckConfigUpdateRequest(
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

func flattenDeckTree(_ node: Anki_Decks_DeckTreeNode, parentPath: String = "") -> [DeckInfo] {
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

func findNode(in node: Anki_Decks_DeckTreeNode, deckId: Int64) -> Anki_Decks_DeckTreeNode? {
    if node.deckID == deckId { return node }
    for child in node.children {
        if let found = findNode(in: child, deckId: deckId) { return found }
    }
    return nil
}

func mapDeckTreeNode(_ node: Anki_Decks_DeckTreeNode, parentPath: String = "") -> DeckTreeNode {
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
