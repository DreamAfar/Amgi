import AnkiBackend
import AnkiProto
public import AnkiKit
public import Dependencies
import DependenciesMacros
import SwiftProtobuf

// MARK: - Service (read-only queries)

@DependencyClient
public struct NoteService: Sendable {
    /// Fetch a single note by ID.
    public var fetch: @Sendable (_ noteId: Int64) throws -> NoteRecord?

    /// Search notes, returning full records.
    public var search: @Sendable (_ query: String, _ limit: Int?) throws -> [NoteRecord]

    /// Fast search returning only note IDs.
    public var searchIds: @Sendable (_ query: String) throws -> [Int64]

    /// Search with backend-builtin column sort, returning note IDs.
    public var searchIdsSorted: @Sendable (_ query: String, _ column: String, _ reverse: Bool) throws -> [Int64]

    /// Batch-fetch full note records for given IDs.
    public var fetchBatch: @Sendable (_ ids: [Int64]) throws -> [NoteRecord]
}

// MARK: - Helpers

private func noteRecordFromProto(_ note: Anki_Notes_Note) -> NoteRecord {
    NoteRecord(
        id: note.id, guid: note.guid, mid: note.notetypeID,
        mod: Int64(note.mtimeSecs), usn: note.usn,
        tags: note.tags.joined(separator: " "),
        flds: note.fields.joined(separator: "\u{1f}"),
        sfld: note.fields.first ?? "", csum: 0,
        flags: 0
    )
}

private func searchNoteIds(
    _ query: String,
    backend: AnkiBackend,
    sortColumn: String? = nil,
    reverse: Bool = false
) throws -> [Int64] {
    var req = Anki_Search_SearchRequest()
    req.search = query.isEmpty ? "deck:*" : query
    if let sortColumn, !sortColumn.isEmpty {
        var builtin = Anki_Search_SortOrder.Builtin()
        builtin.column = sortColumn
        builtin.reverse = reverse
        var order = Anki_Search_SortOrder()
        order.value = .builtin(builtin)
        req.order = order
    }
    let response: Anki_Search_SearchResponse = try backend.invoke(
        service: AnkiBackend.Service.search,
        method: AnkiBackend.SearchMethod.searchNotes,
        request: req
    )
    return response.ids
}

private func fetchNoteBatch(_ ids: [Int64], backend: AnkiBackend) throws -> [NoteRecord] {
    guard !ids.isEmpty else { return [] }
    guard let notePayloads = try? backend.getNotesBatch(noteIds: ids) else {
        return []
    }
    var results: [NoteRecord] = []
    results.reserveCapacity(notePayloads.count)
    for payload in notePayloads {
        if let note = try? Anki_Notes_Note(serializedBytes: payload) {
            results.append(noteRecordFromProto(note))
        }
    }
    return results
}

// MARK: - Live Implementation

extension NoteService: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        return Self(
            fetch: { noteId in
                var req = Anki_Notes_NoteId()
                req.nid = noteId
                let note: Anki_Notes_Note = try backend.invoke(
                    service: AnkiBackend.Service.notes,
                    method: AnkiBackend.NotesMethod.getNote,
                    request: req
                )
                return noteRecordFromProto(note)
            },

            search: { query, limit in
                let ids = try searchNoteIds(query, backend: backend)
                return try fetchNoteBatch(Array(ids.prefix(limit ?? 5000)), backend: backend)
            },

            searchIds: { query in
                try searchNoteIds(query, backend: backend)
            },

            searchIdsSorted: { query, column, reverse in
                try searchNoteIds(query, backend: backend, sortColumn: column, reverse: reverse)
            },

            fetchBatch: { ids in
                try fetchNoteBatch(ids, backend: backend)
            }
        )
    }()
}

// MARK: - Dependency Registration

extension NoteService: TestDependencyKey {
    public static let testValue = NoteService()
}

extension DependencyValues {
    public var noteService: NoteService {
        get { self[NoteService.self] }
        set { self[NoteService.self] = newValue }
    }
}
