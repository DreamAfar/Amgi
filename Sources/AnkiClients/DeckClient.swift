public import AnkiKit
public import AnkiProto
public import Dependencies
import DependenciesMacros

@DependencyClient
public struct DeckClient: Sendable {
    public var fetchAll: @Sendable () throws -> [DeckInfo]
    /// Lightweight fetch: returns deck id+name only, no review counts. Use for filter menus.
    public var fetchNamesOnly: @Sendable () throws -> [DeckInfo]
    public var fetchTree: @Sendable () throws -> [DeckTreeNode]
    public var countsForDeck: @Sendable (_ deckId: Int64) throws -> DeckCounts
    public var create: @Sendable (_ name: String) throws -> Int64
    public var rename: @Sendable (_ deckId: Int64, _ name: String) throws -> Void
    public var delete: @Sendable (_ deckId: Int64) throws -> Void
    public var fetchDeckConfigContext: @Sendable (_ deckId: Int64) throws -> Anki_DeckConfig_DeckConfigsForUpdate
    public var getDeckConfig: @Sendable (_ deckId: Int64) throws -> Anki_DeckConfig_DeckConfig
    public var selectDeckPreset: @Sendable (_ deckId: Int64, _ config: Anki_DeckConfig_DeckConfig, _ applyToChildren: Bool) throws -> Void
    public var createDeckPreset: @Sendable (_ deckId: Int64, _ baseConfig: Anki_DeckConfig_DeckConfig, _ name: String, _ applyToChildren: Bool) throws -> Void
    public var deleteDeckPreset: @Sendable (_ deckId: Int64, _ removingConfigId: Int64, _ fallbackConfig: Anki_DeckConfig_DeckConfig, _ applyToChildren: Bool) throws -> Void
    public var updateDeckConfig: @Sendable (
        _ deckId: Int64,
        _ config: Anki_DeckConfig_DeckConfig,
        _ applyToChildren: Bool,
        _ fsrsEnabled: Bool,
        _ newCardsIgnoreReviewLimit: Bool,
        _ applyAllParentLimits: Bool,
        _ fsrsHealthCheck: Bool
    ) throws -> Void
    public var getRetentionWorkload: @Sendable (_ weights: [Float], _ search: String) throws -> [UInt32: Float]
    public var computeFsrsParams: @Sendable (_ request: Anki_Scheduler_ComputeFsrsParamsRequest) throws -> Anki_Scheduler_ComputeFsrsParamsResponse
    public var simulateFsrsReview: @Sendable (_ request: Anki_Scheduler_SimulateFsrsReviewRequest) throws -> Anki_Scheduler_SimulateFsrsReviewResponse
    public var simulateFsrsWorkload: @Sendable (_ request: Anki_Scheduler_SimulateFsrsReviewRequest) throws -> Anki_Scheduler_SimulateFsrsWorkloadResponse
    public var optimizeFsrsPresets: @Sendable (_ deckId: Int64, _ selectedConfig: Anki_DeckConfig_DeckConfig) throws -> Void
}

extension DeckClient: TestDependencyKey {
    public static let testValue = DeckClient()
}

extension DependencyValues {
    public var deckClient: DeckClient {
        get { self[DeckClient.self] }
        set { self[DeckClient.self] = newValue }
    }
}
