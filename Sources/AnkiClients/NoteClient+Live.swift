import AnkiKit
import AnkiBackend
import AnkiProto
import AnkiServices
import SwiftProtobuf
public import Dependencies
import DependenciesMacros

extension NoteClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        @Dependency(\.noteService) var notes

        return Self(
            // MARK: Delegated to NoteService (read-only)
            fetch:           { try notes.fetch($0) },
            search:          { try notes.search($0, $1) },
            searchIds:       { try notes.searchIds($0) },
            searchIdsSorted: { try notes.searchIdsSorted($0, $1, $2) },
            fetchBatch:      { try notes.fetchBatch($0) },

            // MARK: Write operations (stay in Client)
            save: { note in
                let protoNote = NoteProtoFactory.makeNote(from: note)
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
