import AnkiKit
import AnkiBackend
import AnkiProto
import SwiftProtobuf
public import Dependencies
import DependenciesMacros

extension NoteClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        @Sendable func noteRecordFromProto(_ note: Anki_Notes_Note) -> NoteRecord {
            NoteRecord(
                id: note.id, guid: note.guid, mid: note.notetypeID,
                mod: Int64(note.mtimeSecs), usn: note.usn,
                tags: note.tags.joined(separator: " "),
                flds: note.fields.joined(separator: "\u{1f}"),
                sfld: note.fields.first ?? "", csum: 0,
                flags: 0
            )
        }

        @Sendable func backendSearchNoteIds(_ query: String) throws -> [Int64] {
            var req = Anki_Search_SearchRequest()
            req.search = query.isEmpty ? "deck:*" : query
            let response: Anki_Search_SearchResponse = try backend.invoke(
                service: AnkiBackend.Service.search,
                method: AnkiBackend.SearchMethod.searchNotes,
                request: req
            )
            return response.ids
        }

        @Sendable func backendFetchBatch(_ ids: [Int64]) -> [NoteRecord] {
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
                let ids = try backendSearchNoteIds(query)
                return backendFetchBatch(Array(ids.prefix(limit ?? 5000)))
            },
            searchIds: { query in
                try backendSearchNoteIds(query)
            },
            fetchBatch: { ids in
                backendFetchBatch(ids)
            },
            save: { note in
                var protoNote = Anki_Notes_Note()
                protoNote.id = note.id
                protoNote.notetypeID = note.mid
                protoNote.fields = note.flds
                    .split(separator: "\u{1f}", omittingEmptySubsequences: false)
                    .map(String.init)
                protoNote.tags = note.tags
                    .split(separator: " ")
                    .map(String.init)

                var req = Anki_Notes_UpdateNotesRequest()
                req.notes = [protoNote]
                try backend.callVoid(
                    service: AnkiBackend.Service.notes,
                    method: AnkiBackend.NotesMethod.updateNotes,
                    request: req
                )
            },
            delete: { noteId in
                var req = Anki_Notes_RemoveNotesRequest()
                req.noteIds = [noteId]
                try backend.callVoid(
                    service: AnkiBackend.Service.notes,
                    method: AnkiBackend.NotesMethod.removeNotes,
                    request: req
                )
            }
        )
    }()
}
