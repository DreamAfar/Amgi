import AnkiBackend
import AnkiProto
public import Dependencies
import Foundation
import SwiftProtobuf

extension ImageOcclusionClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            addNote: { imageURL, occlusions, header, backExtra, tags, deckID, notetypeID in
                // 1. Ensure the notetype exists
                _ = try backend.call(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.addImageOcclusionNotetype
                )

                // 2. IO note creation saves into the backend's current deck.
                var deckReq = Anki_Decks_DeckId()
                deckReq.did = deckID
                try backend.callVoid(
                    service: AnkiBackend.Service.decks,
                    method: AnkiBackend.DecksMethod.setCurrentDeck,
                    request: deckReq
                )

                // 3. Let the backend import the selected source file into media.
                var req = Anki_ImageOcclusion_AddImageOcclusionNoteRequest()
                req.imagePath = imageURL.path
                req.occlusions = occlusions
                req.header = header
                req.backExtra = backExtra
                req.tags = tags
                req.notetypeID = notetypeID
                try backend.callVoid(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.addImageOcclusionNote,
                    request: req
                )
            },

            ensureNotetype: {
                _ = try backend.call(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.addImageOcclusionNotetype
                )
            },

            getNote: { noteId in
                var req = Anki_ImageOcclusion_GetImageOcclusionNoteRequest()
                req.noteID = noteId
                let resp: Anki_ImageOcclusion_GetImageOcclusionNoteResponse = try backend.invoke(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.getImageOcclusionNote,
                    request: req
                )
                guard case .note(let note) = resp.value else {
                    throw ImageOcclusionError.noteNotFound
                }
                // Reconstruct occlusions string from structured shapes
                let occlusions = note.occlusions.flatMap { occ in
                    occ.shapes.map { shape -> String in
                        let propertyTokens = shape.properties.map { "\($0.name)=\($0.value)" }.joined(separator: ":")
                        let suffix = propertyTokens.isEmpty ? "" : ":\(propertyTokens)"
                        return "{{c\(occ.ordinal)::image-occlusion:\(shape.shape)\(suffix)}}"
                    }
                }.joined(separator: "\n")

                return ImageOcclusionNoteData(
                    imageData: note.imageData,
                    imageName: note.imageFileName,
                    occlusions: occlusions,
                    header: note.header,
                    backExtra: note.backExtra,
                    tags: note.tags
                )
            },

            updateNote: { noteId, occlusions, header, backExtra, tags in
                var req = Anki_ImageOcclusion_UpdateImageOcclusionNoteRequest()
                req.noteID = noteId
                req.occlusions = occlusions
                req.header = header
                req.backExtra = backExtra
                req.tags = tags
                try backend.callVoid(
                    service: AnkiBackend.Service.imageOcclusion,
                    method: AnkiBackend.ImageOcclusionMethod.updateImageOcclusionNote,
                    request: req
                )
            }
        )
    }()
}

// MARK: - Error

enum ImageOcclusionError: Error {
    case noteNotFound
}
