//
//  NoteEditorModel.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 22.06.2026.
//

import OSLog
import AppCore
import AppShared
import AnkiBackend
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies
import SwiftUI

/// Field/tag state + load/save logic for editing an existing note. The View
/// owns the toolbar and the "Saved" toast; the model owns notetype lookup,
/// field unpacking, and the note write so the form stays testable.
@Observable
@MainActor
final class NoteEditorModel {
    var fieldNames: [String] = []
    var fieldValues: [String] = []
    var tags: String = ""
    var isSaving = false
    /// New recordings per field, still in the temporary directory. They are
    /// copied into the media folder and referenced as `[sound:…]` only when
    /// the note is saved, the same as on Add Note.
    var fieldAudio: [[URL]] = []

    @ObservationIgnored @Dependency(\.noteClient) private var noteClient
    @ObservationIgnored @Dependency(\.mediaClient) private var mediaClient
    @ObservationIgnored @Dependency(\.notetypesService) private var notetypesService
    @ObservationIgnored private let note: NoteRecord

    init(note: NoteRecord) {
        self.note = note
    }

    /// For the card preview, which renders the fields as they stand now.
    var notetypeID: NotetypeID { note.mid }

    /// Positional projection into `fieldValues`, read through `@Bindable` as
    /// `$model[fieldAt: index]`. A subscript rather than a
    /// `Binding(get:set:)`-returning method so the field editors get a stable
    /// binding instead of a freshly-allocated closure pair on every body pass.
    subscript(fieldAt index: Int) -> String {
        get { index < fieldValues.count ? fieldValues[index] : "" }
        set { if index < fieldValues.count { fieldValues[index] = newValue } }
    }

    func loadNote() async {
        do {
            let service = notetypesService
            let mid = note.mid
            let notetype = try await backendOffload { try service.getNotetype(mid) }
            fieldNames = notetype.fieldNames
        } catch {
            Log.browse.error("Error loading notetype: \(error)")
        }

        fieldValues = note.flds
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)
        while fieldValues.count < fieldNames.count { fieldValues.append("") }
        fieldAudio = fieldValues.map { _ in [] }
        tags = note.tags.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Audio

    func attachAudio(_ url: URL, toField index: Int) {
        guard !isSaving, fieldAudio.indices.contains(index) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        fieldAudio[index].append(url)
    }

    func removeAudio(_ url: URL, fromField index: Int) {
        guard !isSaving, fieldAudio.indices.contains(index) else { return }
        fieldAudio[index].removeAll { $0 == url }
        try? FileManager.default.removeItem(at: url)
    }

    /// Drops recordings that were never saved.
    func discardAudio() {
        for url in fieldAudio.flatMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        fieldAudio = fieldAudio.map { _ in [] }
    }

    /// Where a `[sound:…]` file the field references lives, for preview.
    func mediaURL(for filename: String) -> URL? {
        guard let url = mediaClient.localURL(filename),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Copies pending recordings into the media folder and returns the fields
    /// with a `[sound:…]` reference appended for each. On failure the files
    /// already written are removed again.
    private func fieldsWithAudio() async throws -> [String] {
        var fields = fieldValues
        var written: [String] = []
        do {
            for (index, clips) in fieldAudio.enumerated() where fields.indices.contains(index) {
                for url in clips {
                    let data = try await backendOffload { try Data(contentsOf: url) }
                    try await mediaClient.save(data, url.lastPathComponent)
                    written.append(url.lastPathComponent)
                    fields[index] = NoteSoundTags.appending(url.lastPathComponent, to: fields[index])
                }
            }
        } catch {
            for name in written { try? await mediaClient.delete(name) }
            throw error
        }
        return fields
    }

    /// Persist the edited fields/tags. Returns whether the write succeeded.
    func save() async -> Bool {
        isSaving = true
        defer { isSaving = false }

        let fieldValues: [String]
        do {
            fieldValues = try await fieldsWithAudio()
        } catch {
            Log.browse.error("Error saving recordings: \(error)")
            return false
        }

        let newFlds = fieldValues.joined(separator: "\u{1f}")
        let newSfld = fieldValues.first ?? ""
        let newCsum = Int64(newSfld.hashValue & 0xFFFFFFFF)

        var updatedNote = note
        updatedNote.flds = newFlds
        updatedNote.sfld = newSfld
        updatedNote.csum = newCsum
        updatedNote.tags = " \(tags) "

        do {
            try await noteClient.save(updatedNote)
            // The recordings are now referenced in the field text; show them
            // there and let go of the temporary copies.
            self.fieldValues = fieldValues
            discardAudio()
            Task { await WordSpotlightController.shared.refresh() }
            return true
        } catch {
            for name in fieldAudio.flatMap({ $0 }).map(\.lastPathComponent) {
                try? await mediaClient.delete(name)
            }
            return false
        }
    }
}
