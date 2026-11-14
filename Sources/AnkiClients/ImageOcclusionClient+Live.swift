//
//  ImageOcclusionClient+Live.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 28.04.2026.
//

import AnkiBackend
import AnkiKit
import AnkiProtoBridge
public import Dependencies
import Foundation

extension ImageOcclusionClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            addNote: { imageURL, occlusions, header, backExtra, tags, deckID, notetypeID in
                try await backendOffload {
                    // 1. Ensure the notetype exists.
                    try backend.invoke(.addImageOcclusionNotetype)

                    // 2. IO note creation saves into the backend's current deck,
                    //    so point it at the target deck for the add and put the
                    //    user's current deck back afterwards. Leaving it moved
                    //    changed which deck the rest of the app (and a synced
                    //    desktop) treated as current.
                    let previousDeckID = try? backend.invoke(.getCurrentDeck).id
                    try backend.invoke(.setCurrentDeck(deckId: deckID))
                    defer {
                        if let previousDeckID, previousDeckID != deckID {
                            try? backend.invoke(.setCurrentDeck(deckId: previousDeckID))
                        }
                    }

                    // 3. Let the backend import the selected source file into media.
                    try backend.invoke(.addImageOcclusionNote(
                        imagePath: imageURL.path,
                        occlusions: occlusions,
                        header: header,
                        backExtra: backExtra,
                        tags: tags,
                        notetypeId: notetypeID
                    ))
                }
            },

            getNote: { noteId in
                try await backend.invoke(.getImageOcclusionNote(noteId: noteId))
            },

            updateNote: { noteId, occlusions, header, backExtra, tags in
                try await backend.invoke(.updateImageOcclusionNote(
                    noteId: noteId,
                    occlusions: occlusions,
                    header: header,
                    backExtra: backExtra,
                    tags: tags
                ))
            }
        )
    }()
}
