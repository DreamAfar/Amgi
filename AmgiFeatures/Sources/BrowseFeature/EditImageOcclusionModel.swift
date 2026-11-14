//
//  EditImageOcclusionModel.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 29.04.2026.
//

#if canImport(UIKit)
import AnkiKit
import AppShared
import AnkiClients
import Dependencies
import Foundation
import UIKit

/// Load/save state for editing an existing image-occlusion note. The View
/// owns the modal chrome and the occlusion-editor cover; the model owns the
/// note fetch, occlusion-string parsing, and the update write.
@Observable
@MainActor
final class EditImageOcclusionModel {
    var isLoading = true
    var loadError: String?
    var uiImage: UIImage?
    var shapes: [IOShape] = []
    var occludeInactive = false
    var header: String = ""
    var backExtra: String = ""
    var tagsText: String = ""
    var isSaving = false
    var saveError: String?

    @ObservationIgnored @Dependency(\.imageOcclusionClient) private var client
    @ObservationIgnored @Dependency(\.collectionStore) private var store
    @ObservationIgnored private let noteId: NoteID

    init(noteId: NoteID) {
        self.noteId = noteId
    }

    var canSave: Bool {
        !isLoading && IOCloze.cardCount(shapes) > 0 && !isSaving
    }

    func loadNote() async {
        isLoading = true
        loadError = nil
        do {
            let data = try await client.getNote(noteId)

            if let img = UIImage(data: data.imageData) {
                uiImage = img
            }

            header = data.header
            backExtra = data.backExtra
            tagsText = data.tags.joined(separator: " ")
            shapes = IOCloze.shapes(from: data.occlusions)
            occludeInactive = data.occludeInactive
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Persist the edited occlusions/fields/tags. Returns whether the write
    /// succeeded; on failure `saveError` carries the reason.
    func save() async -> Bool {
        guard IOCloze.cardCount(shapes) > 0 else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let occlusions = IOCloze.occlusions(shapes, occludeInactive: occludeInactive)
        let tags = tagsText.split(separator: " ").map(String.init).filter { !$0.isEmpty }

        do {
            try await client.updateNote(noteId, occlusions, header, backExtra, tags)
            // Adding or removing masks adds or empties cards.
            store.apply(CollectionChanges(card: true, note: true, studyQueues: true))
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}
#endif
