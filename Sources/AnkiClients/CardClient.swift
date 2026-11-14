//
//  CardClient.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 27.03.2026.
//

public import AnkiKit
public import Dependencies
import DependenciesMacros

@DependencyClient
public struct CardClient: Sendable {
    public var fetchDue: @Sendable (_ deckId: DeckID) async throws -> [CardRecord]
    public var fetchByNote: @Sendable (_ noteId: NoteID) async throws -> [CardRecord]
    public var suspend: @Sendable (_ cardId: CardID) async throws -> Void
    public var bury: @Sendable (_ cardId: CardID) async throws -> Void
    public var flag: @Sendable (_ cardId: CardID, _ value: UInt32) async throws -> Void
    public var resetToNew: @Sendable (_ cardId: CardID) async throws -> Void
    public var setDueDate: @Sendable (_ cardId: CardID, _ days: String) async throws -> Void
    public var undoLast: @Sendable () async throws -> Void
    public var getCardFlags: @Sendable (_ cardId: CardID) async throws -> UInt32
    public var hasUndoableAction: @Sendable () async throws -> Bool
    public var removeCards: @Sendable (_ cardIds: [CardID]) async throws -> Void

    // MARK: Batch (Browse) — one backend call, one undo step, for many cards

    /// Card ids of every card belonging to `noteIds`.
    public var cardIDsOfNotes: @Sendable (_ noteIds: [NoteID]) async throws -> [CardID]
    public var setDeckForCards: @Sendable (_ cardIds: [CardID], _ deckId: DeckID) async throws -> Void
    public var suspendCards: @Sendable (_ cardIds: [CardID]) async throws -> Void
    public var buryCards: @Sendable (_ cardIds: [CardID]) async throws -> Void
    /// Unsuspends and unburies.
    public var restoreCards: @Sendable (_ cardIds: [CardID]) async throws -> Void
    public var resetCardsToNew: @Sendable (_ cardIds: [CardID]) async throws -> Void
    public var setDueDateForCards: @Sendable (_ cardIds: [CardID], _ days: String) async throws -> Void
    public var gradeCardsNow: @Sendable (_ cardIds: [CardID], _ rating: Rating) async throws -> Void
}

extension CardClient: TestDependencyKey {
    public static let testValue = CardClient()
}

extension DependencyValues {
    public var cardClient: CardClient {
        get { self[CardClient.self] }
        set { self[CardClient.self] = newValue }
    }
}
