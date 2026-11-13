//
//  NotetypeFieldManagerModel.swift
//  TemplatesFeature
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation

/// Stages edits to a notetype's field list — add, rename, remove, reorder,
/// per-field options and the sort field — and writes them back in one
/// `notetypesClient.update`, the way Anki's Fields dialog does.
///
/// Existing fields keep their `ord`; new ones go up with `ord == nil`. That
/// is how the backend tells a rename or a move from a remove-and-add: it
/// maps note content by ord, drops the content of removed ords, and rewrites
/// `{{Field}}` references in the card templates for renamed fields.
@Observable
@MainActor
final class NotetypeFieldManagerModel {
    struct EditableField: Identifiable, Equatable {
        let id: UUID
        var field: Notetype.Field

        init(id: UUID = UUID(), field: Notetype.Field) {
            self.id = id
            self.field = field
        }

        var name: String { field.name }
        /// Added in this session; the backend hasn't seen it yet.
        var isNew: Bool { field.ord == nil }
        /// Image Occlusion's required fields; the notetype breaks without them.
        var isProtected: Bool { field.config.preventDeletion }
    }

    enum NameError: Error, Equatable {
        case empty
        case invalidStart
        case invalidCharacter
        case duplicate

        var message: String {
            switch self {
            case .empty:
                String(localized: "Enter a field name.", bundle: .module)
            case .invalidStart:
                String(localized: "A field name can't start with #, / or ^.", bundle: .module)
            case .invalidCharacter:
                String(localized: "A field name can't contain : \" { or }.", bundle: .module)
            case .duplicate:
                String(localized: "This notetype already has a field with that name.", bundle: .module)
            }
        }
    }

    private(set) var isLoading = true
    private(set) var loadError: String?
    private(set) var isSaving = false
    var saveError: String?

    var fields: [EditableField] = []
    /// The field Browse lists and sorts notes by.
    var sortFieldID: EditableField.ID?

    private var original: Notetype?
    private var originalFields: [EditableField] = []
    private var originalSortFieldID: EditableField.ID?

    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient

    var notetypeName: String { original?.name ?? "" }

    var hasChanges: Bool {
        fields != originalFields || sortFieldID != originalSortFieldID
    }

    /// Adding, removing or reordering fields, or moving the sort field,
    /// marks the collection schema modified (rslib's
    /// `update_notes_for_changed_fields`), so the next sync has to be a
    /// one-way full sync. Renames and per-field options don't.
    var requiresFullSync: Bool {
        let originalOrds = originalFields.map(\.field.ord)
        let currentOrds = fields.compactMap(\.field.ord)
        let originalSortIndex = originalFields.firstIndex { $0.id == originalSortFieldID }
        let sortIndex = fields.firstIndex { $0.id == sortFieldID }
        return fields.contains(where: \.isNew) || currentOrds != originalOrds || sortIndex != originalSortIndex
    }

    func load(notetypeId: NotetypeID) async {
        isLoading = true
        loadError = nil
        do {
            let notetype = try await notetypesClient.get(notetypeId)
            original = notetype
            let editable = notetype.fields.map { EditableField(field: $0) }
            fields = editable
            originalFields = editable
            let sortIndex = notetype.config.sortFieldIdx
            sortFieldID = editable.indices.contains(sortIndex) ? editable[sortIndex].id : editable.first?.id
            originalSortFieldID = sortFieldID
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Editing

    /// Mirrors the backend's field-name rules, so the user hears about a bad
    /// name at the prompt instead of as a failed save.
    func validate(_ rawName: String, excluding id: EditableField.ID? = nil) -> NameError? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if let first = name.first, "#/^".contains(first) { return .invalidStart }
        if name.contains(where: { ":\"{}".contains($0) }) { return .invalidCharacter }
        let taken = fields.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return taken ? .duplicate : nil
    }

    @discardableResult
    func addField(named rawName: String) -> NameError? {
        if let error = validate(rawName) { return error }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        fields.append(EditableField(field: Notetype.Field(ord: nil, name: name)))
        return nil
    }

    @discardableResult
    func rename(_ id: EditableField.ID, to rawName: String) -> NameError? {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return nil }
        if let error = validate(rawName, excluding: id) { return error }
        fields[index].field.name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return nil
    }

    func canRemove(_ field: EditableField) -> Bool {
        fields.count > 1 && !field.isProtected
    }

    func remove(_ id: EditableField.ID) {
        guard let field = fields.first(where: { $0.id == id }), canRemove(field) else { return }
        fields.removeAll { $0.id == id }
        if sortFieldID == id { sortFieldID = fields.first?.id }
    }

    /// `List.onMove` semantics: `destination` is an index into the list as
    /// it was before the move.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { fields[$0] }
        var remaining = fields
        for index in source.reversed() { remaining.remove(at: index) }
        let insertAt = destination - source.count(in: 0..<destination)
        remaining.insert(contentsOf: moving, at: insertAt)
        fields = remaining
    }

    func updateConfig(_ id: EditableField.ID, _ change: (inout Notetype.Field.Config) -> Void) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        change(&fields[index].field.config)
    }

    // MARK: - Saving

    /// The notetype as it will be sent: the staged field list in its new
    /// order, and the sort field as an index into that order.
    func updatedNotetype() -> Notetype? {
        guard var notetype = original else { return nil }
        notetype.fields = fields.map(\.field)
        notetype.config.sortFieldIdx = fields.firstIndex { $0.id == sortFieldID } ?? 0
        return notetype
    }

    /// Returns whether the save went through.
    func save() async -> Bool {
        guard hasChanges else { return true }
        guard let notetype = updatedNotetype() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await notetypesClient.update(notetype)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}
