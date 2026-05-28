import AnkiBackend
public import AnkiProto
public import Dependencies
import DependenciesMacros

// MARK: - Service

@DependencyClient
public struct CollectionService: Sendable {
    /// Run database integrity check. Returns list of problems (empty = clean).
    public var checkDatabase: @Sendable () throws -> [String]

    /// Undo last collection operation.
    public var undoLast: @Sendable () throws -> Void

    /// Whether there's an undoable action pending.
    public var hasUndoableAction: @Sendable () throws -> Bool

    /// Fetch collection-level preferences (scheduling, reviewing, etc.).
    public var getPreferences: @Sendable () throws -> Anki_Config_Preferences
}

// MARK: - Live Implementation

extension CollectionService: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        return Self(
            checkDatabase: {
                let response: Anki_Collection_CheckDatabaseResponse = try backend.invoke(
                    service: AnkiBackend.Service.collection,
                    method: AnkiBackend.CheckDatabaseMethod.checkDatabase
                )
                return response.problems
            },
            undoLast: {
                try backend.callVoid(
                    service: AnkiBackend.Service.collection,
                    method: AnkiBackend.CollectionMethod.undo
                )
            },
            hasUndoableAction: {
                let status: Anki_Collection_UndoStatus = try backend.invoke(
                    service: AnkiBackend.Service.collection,
                    method: AnkiBackend.CollectionMethod.getUndoStatus,
                    request: Anki_Generic_Empty()
                )
                return !status.undo.isEmpty
            },
            getPreferences: {
                try backend.getPreferences()
            }
        )
    }()
}

// MARK: - Dependency Registration

extension CollectionService: TestDependencyKey {
    public static let testValue = CollectionService()
}

extension DependencyValues {
    public var collectionService: CollectionService {
        get { self[CollectionService.self] }
        set { self[CollectionService.self] = newValue }
    }
}
