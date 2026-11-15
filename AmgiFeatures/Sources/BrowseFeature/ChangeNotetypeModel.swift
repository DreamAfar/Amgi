//
//  ChangeNotetypeModel.swift
//  BrowseFeature
//

import AnkiClients
import AnkiKit
import AppShared
import Dependencies
import Foundation

/// Browse › Change Note Type, as in Anki: the selected notes (all of one
/// notetype) move to another notetype; each new field takes its content from
/// an old field or starts empty, and each new card template inherits an old
/// template's cards — and their review history — or starts fresh. Old cards
/// no template claims are deleted.
@Observable
@MainActor
final class ChangeNotetypeModel {
    enum Phase: Equatable {
        case loading
        /// The selection spans several notetypes; Anki only changes one at a time.
        case mixed([String])
        case ready
        case failed(String)
    }

    let noteIDs: [NoteID]
    private(set) var phase: Phase = .loading
    private(set) var oldNotetype: NotetypeNameId?
    private(set) var targets: [NotetypeNameId] = []
    private(set) var target: NotetypeNameId?
    private(set) var info: ChangeNotetypeInfo?
    private(set) var isLoadingInfo = false
    private(set) var isSaving = false
    var errorMessage: String?

    /// `newFields[i]`: index of the old field feeding new field `i`.
    var newFields: [Int?] = []
    /// `newTemplates[i]`: index of the old template whose cards become new template `i`'s.
    var newTemplates: [Int?] = []

    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient
    @ObservationIgnored @Dependency(\.noteClient) private var noteClient
    @ObservationIgnored @Dependency(\.collectionStore) private var store

    init(noteIDs: [NoteID]) {
        self.noteIDs = noteIDs
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            let all = try await notetypesClient.listAll()
            var mids = Set<NotetypeID>()
            for id in noteIDs {
                if let note = try await noteClient.fetch(id) { mids.insert(note.mid) }
            }
            if mids.count > 1 {
                let names = all.filter { mids.contains($0.id) }.map(\.name).sorted()
                phase = .mixed(names)
                return
            }
            guard let mid = mids.first, let old = all.first(where: { $0.id == mid }) else {
                phase = .failed(String(localized: "The selected notes couldn't be read.", bundle: .module))
                return
            }
            oldNotetype = old
            targets = all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            phase = .ready
            // Anki opens on the current notetype, which shows the mapping
            // with nothing changed; picking another fills it in.
            await selectTarget(old)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func selectTarget(_ notetype: NotetypeNameId) async {
        guard let old = oldNotetype else { return }
        target = notetype
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        do {
            let loaded = try await notetypesClient.changeNotetypeInfo(old.id, notetype.id)
            guard target == notetype else { return }
            info = loaded
            newFields = loaded.input.newFields
            newTemplates = loaded.input.newTemplates
        } catch {
            info = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mapping

    var isCloze: Bool { info?.input.isCloze ?? false }

    /// A field may feed several new fields, as in Anki.
    func setField(_ newIndex: Int, from oldIndex: Int?) {
        guard newFields.indices.contains(newIndex) else { return }
        newFields[newIndex] = oldIndex
    }

    /// Each old template's cards can go to one place only, so choosing one
    /// that another new template already uses takes it from there.
    func setTemplate(_ newIndex: Int, from oldIndex: Int?) {
        guard newTemplates.indices.contains(newIndex) else { return }
        if let oldIndex {
            for index in newTemplates.indices where index != newIndex && newTemplates[index] == oldIndex {
                newTemplates[index] = nil
            }
        }
        newTemplates[newIndex] = oldIndex
    }

    /// Old fields whose content no new field takes.
    var discardedFields: [String] {
        guard let info else { return [] }
        let used = Set(newFields.compactMap { $0 })
        return info.oldFieldNames.indices.filter { !used.contains($0) }.map { info.oldFieldNames[$0] }
    }

    /// Old templates whose cards no new template takes; those cards are deleted.
    var discardedTemplates: [String] {
        guard let info, !isCloze else { return [] }
        let used = Set(newTemplates.compactMap { $0 })
        return info.oldTemplateNames.indices.filter { !used.contains($0) }.map { info.oldTemplateNames[$0] }
    }

    /// Changing to the same notetype with nothing remapped does nothing.
    var hasChanges: Bool {
        guard let info else { return false }
        if target?.id != oldNotetype?.id { return true }
        return newFields != info.input.newFields || newTemplates != info.input.newTemplates
    }

    var canSave: Bool { phase == .ready && info != nil && hasChanges && !isSaving && !isLoadingInfo }

    // MARK: - Saving

    func save() async -> Bool {
        guard let info, canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        var input = info.input
        input.noteIDs = noteIDs
        input.newFields = newFields
        input.newTemplates = isCloze ? [] : newTemplates
        do {
            try await notetypesClient.changeNotetype(input)
            store.apply(CollectionChanges(card: true, note: true, deck: true, notetype: true, studyQueues: true))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
