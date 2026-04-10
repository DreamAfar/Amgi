public import AnkiKit
public import AnkiProto
public import Dependencies
import DependenciesMacros

@DependencyClient
public struct DeckClient: Sendable {
    public var fetchAll: @Sendable () throws -> [DeckInfo]
    public var fetchTree: @Sendable () throws -> [DeckTreeNode]
    public var countsForDeck: @Sendable (_ deckId: Int64) throws -> DeckCounts
    public var create: @Sendable (_ name: String) throws -> Int64
    public var rename: @Sendable (_ deckId: Int64, _ name: String) throws -> Void
    public var delete: @Sendable (_ deckId: Int64) throws -> Void
    public var getDeckConfig: @Sendable (_ deckId: Int64) throws -> Anki_DeckConfig_DeckConfig
    public var updateDeckConfig: @Sendable (_ deckId: Int64, _ config: Anki_DeckConfig_DeckConfig) throws -> Void
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
