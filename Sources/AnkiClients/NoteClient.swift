public import AnkiKit
public import Dependencies
import DependenciesMacros

@DependencyClient
public struct NoteClient: Sendable {
    public var fetch: @Sendable (_ noteId: Int64) throws -> NoteRecord?
    public var search: @Sendable (_ query: String, _ limit: Int?) throws -> [NoteRecord]
    /// Returns only note IDs for the query (fast, no full-note fetch).
    public var searchIds: @Sendable (_ query: String) throws -> [Int64]
    /// Fetches full note records for the given IDs in order.
    public var fetchBatch: @Sendable (_ ids: [Int64]) throws -> [NoteRecord]
    public var save: @Sendable (_ note: NoteRecord) throws -> Void
    public var delete: @Sendable (_ noteId: Int64) throws -> Void
}

extension NoteClient: TestDependencyKey {
    public static let testValue = NoteClient()
}

extension DependencyValues {
    public var noteClient: NoteClient {
        get { self[NoteClient.self] }
        set { self[NoteClient.self] = newValue }
    }
}
