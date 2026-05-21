import Foundation
import SwiftUI
import AnkiBackend
import AnkiProto
import Dependencies
import UniformTypeIdentifiers

struct NotetypeFieldManagerListView: View {
    @Dependency(\.ankiBackend) var backend

    @State private var entries: [Anki_Notetypes_NotetypeNameId] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filteredEntries: [Anki_Notetypes_NotetypeNameId] {
        filterDeckTemplateEntries(entries, searchText: searchText)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                AmgiStatusMessageView(
                    title: L("notetype_field_error_title"),
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            } else if entries.isEmpty {
                ContentUnavailableView(
                    L("notetype_field_empty_title"),
                    systemImage: "text.badge.plus",
                    description: Text(L("notetype_field_empty_desc"))
                )
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filteredEntries, id: \.id) { entry in
                    NavigationLink {
                        NotetypeFieldManagerView(notetypeId: entry.id, preferredName: entry.name)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "text.badge.plus")
                                .foregroundStyle(Color.amgiAccent)
                            VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                                Text(entry.name)
                                    .amgiFont(.body)
                                    .foregroundStyle(Color.amgiTextPrimary)
                                Text("ID: \(entry.id)")
                                    .amgiFont(.caption)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.amgiBackground)
            }
        }
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_row_field_manager"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: L("notetype_field_search"))
        .task {
            await loadNotetypes()
        }
    }

    @MainActor
    private func loadNotetypes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )
            entries = sortDeckTemplateEntries(response.entries)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }
}

struct NotetypeFieldManagerView: View {
    @Dependency(\.ankiBackend) var backend

    let notetypeId: Int64
    var preferredName: String? = nil
    var onSaved: (@Sendable () async -> Void)? = nil

    @State private var notetype: Anki_Notetypes_Notetype = .init()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showAddPrompt = false
    @State private var addFieldName = ""

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                List {
                    fieldsList
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.amgiBackground)
            }
        }
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_row_field_manager"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_add")) {
                    addFieldName = ""
                    showAddPrompt = true
                }
                .amgiToolbarTextButton()
                .disabled(isLoading || isSaving)
            }
        }
        .alert(L("notetype_field_add_title"), isPresented: $showAddPrompt) {
            TextField(L("notetype_field_name_placeholder"), text: $addFieldName)
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_add")) {
                Task { await addField() }
            }
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
        .task {
            await loadNotetype()
        }
    }

    private var fieldsList: some View {
        ForEach(Array(notetype.fields.enumerated()), id: \.offset) { index, field in
            fieldRow(field, at: index)
        }
    }

    private func fieldRow(_ field: Anki_Notetypes_Notetype.Field, at index: Int) -> some View {
        NavigationLink {
            NotetypeFieldEditorView(
                notetypeId: notetypeId,
                preferredName: preferredName,
                initiallySelectedFieldIndex: index,
                onSaved: {
                    await loadNotetype()
                    if let onSaved {
                        await onSaved()
                    }
                }
            )
        } label: {
            HStack {
                Text(field.name)
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextPrimary)
                Spacer()
            }
        }
    }

    @MainActor
    private func loadNotetype() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var req = Anki_Notetypes_NotetypeId()
            req.ntid = notetypeId
            notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: req
            )
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func addField() async {
        let newName = normalizedFieldName(addFieldName)
        guard validateFieldName(newName) else { return }

        var updated = notetype
        var field = Anki_Notetypes_Notetype.Field()
        var ord = Anki_Generic_UInt32()
        ord.val = UInt32(updated.fields.count)
        field.ord = ord
        field.name = newName
        updated.fields.append(field)
        await persist(updated)
    }

    private func normalizedFieldName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateFieldName(_ name: String) -> Bool {
        guard !name.isEmpty else {
            errorMessage = L("notetype_field_name_empty")
            showError = true
            return false
        }

        let lowercased = name.lowercased()
        let duplicateExists = notetype.fields.contains { field in
            field.name.lowercased() == lowercased
        }

        guard !duplicateExists else {
            errorMessage = L("notetype_field_name_duplicate")
            showError = true
            return false
        }
        return true
    }

    @MainActor
    private func persist(_ updated: Anki_Notetypes_Notetype) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try backend.callVoid(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.updateNotetype,
                request: updated
            )
            notetype = updated
            if let onSaved {
                await onSaved()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

}

struct NotetypeFieldEditorView: View {
    @Dependency(\.ankiBackend) var backend

    let notetypeId: Int64
    var preferredName: String? = nil
    var initiallySelectedFieldIndex: Int? = nil
    var onSaved: (@Sendable () async -> Void)? = nil

    @State private var notetype: Anki_Notetypes_Notetype = .init()
    @State private var fieldNameDrafts: [String] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showAddPrompt = false
    @State private var addFieldName = ""
    @State private var deleteFieldIndex: Int?
    @State private var showDeleteConfirm = false
    @State private var draggedFieldIndex: Int?
    @State private var pendingFocusIndex: Int?
    @FocusState private var focusedFieldIndex: Int?

    private var titleText: String {
        L("notetype_field_editor_title")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                List {
                    Section {
                        ForEach(Array(notetype.fields.enumerated()), id: \.offset) { index, field in
                            editableFieldRow(field, at: index)
                        }
                    } header: {
                        Text(L("notetype_field_section_fields"))
                    } footer: {
                        Text(L("notetype_field_editor_footer"))
                            .amgiFont(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.amgiBackground)
            }
        }
        .background(Color.amgiBackground)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addFieldName = ""
                    showAddPrompt = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isLoading || isSaving)
            }
        }
        .alert(L("notetype_field_add_title"), isPresented: $showAddPrompt) {
            TextField(L("notetype_field_name_placeholder"), text: $addFieldName)
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_add")) {
                Task { await addField() }
            }
        }
        .alert(L("notetype_field_delete_title"), isPresented: $showDeleteConfirm) {
            Button(L("common_delete"), role: .destructive) {
                Task { await deleteField() }
            }
            Button(L("common_cancel"), role: .cancel) {}
        } message: {
            if let deleteFieldIndex, notetype.fields.indices.contains(deleteFieldIndex) {
                Text(L("notetype_field_delete_message", notetype.fields[deleteFieldIndex].name))
            } else {
                Text("")
            }
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
        .task {
            pendingFocusIndex = initiallySelectedFieldIndex
            await loadNotetype()
        }
        .onChange(of: focusedFieldIndex) { oldValue, newValue in
            guard let oldValue, oldValue != newValue else { return }
            Task { await commitRenameIfNeeded(at: oldValue) }
        }
        .onDisappear {
            if let focusedFieldIndex {
                Task { await commitRenameIfNeeded(at: focusedFieldIndex) }
            }
        }
    }

    private func editableFieldRow(_ field: Anki_Notetypes_Notetype.Field, at index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.amgiTextTertiary)
            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    L("notetype_field_name_placeholder"),
                    text: bindingForFieldName(at: index)
                )
                .focused($focusedFieldIndex, equals: index)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    Task { await commitRenameIfNeeded(at: index) }
                }

                HStack(spacing: 8) {
                    Text(L("notetype_field_position", index + 1))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                    if Int(notetype.config.sortFieldIdx) == index {
                        Text(L("notetype_field_sort_badge"))
                            .amgiFont(.captionBold)
                            .foregroundStyle(Color.amgiAccent)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedFieldIndex = index
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if Int(notetype.config.sortFieldIdx) != index {
                Button {
                    Task { await setSortField(to: index) }
                } label: {
                    Label(L("notetype_field_sort_action"), systemImage: "arrow.up.arrow.down.circle")
                }
                .tint(.orange)
            }

            if !field.config.preventDeletion && notetype.fields.count > 1 {
                Button(role: .destructive) {
                    deleteFieldIndex = index
                    showDeleteConfirm = true
                } label: {
                    Label(L("common_delete"), systemImage: "trash")
                }
            }
        }
        .onDrag {
            draggedFieldIndex = index
            return NSItemProvider(object: NSString(string: field.name))
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: NotetypeFieldDropDelegate(
                targetIndex: index,
                draggedFieldIndex: $draggedFieldIndex,
                notetype: $notetype,
                fieldNameDrafts: $fieldNameDrafts,
                onPersist: { updated in
                    Task { await persist(updated, resetDrafts: false) }
                }
            )
        )
    }

    private func bindingForFieldName(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard fieldNameDrafts.indices.contains(index) else { return "" }
                return fieldNameDrafts[index]
            },
            set: { newValue in
                guard fieldNameDrafts.indices.contains(index) else { return }
                fieldNameDrafts[index] = newValue
            }
        )
    }

    @MainActor
    private func loadNotetype() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var req = Anki_Notetypes_NotetypeId()
            req.ntid = notetypeId
            notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: req
            )
            syncDraftsFromNotetype()
            if let pendingFocusIndex, fieldNameDrafts.indices.contains(pendingFocusIndex) {
                let focusIndex = pendingFocusIndex
                DispatchQueue.main.async {
                    focusedFieldIndex = focusIndex
                }
            }
            self.pendingFocusIndex = nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    @MainActor
    private func addField() async {
        let newName = normalizedFieldName(addFieldName)
        guard validateFieldName(newName, excluding: nil) else { return }

        var updated = notetype
        var field = Anki_Notetypes_Notetype.Field()
        var ord = Anki_Generic_UInt32()
        ord.val = UInt32(updated.fields.count)
        field.ord = ord
        field.name = newName
        updated.fields.append(field)
        pendingFocusIndex = updated.fields.count - 1
        await persist(updated)
    }

    @MainActor
    private func commitRenameIfNeeded(at index: Int) async {
        guard notetype.fields.indices.contains(index), fieldNameDrafts.indices.contains(index) else { return }

        let newName = normalizedFieldName(fieldNameDrafts[index])
        let oldName = notetype.fields[index].name
        guard newName != oldName else { return }
        guard validateFieldName(newName, excluding: index) else {
            fieldNameDrafts[index] = oldName
            return
        }

        var updated = notetype
        updated.fields[index].name = newName
        await persist(updated, resetDrafts: false)
    }

    @MainActor
    private func deleteField() async {
        guard let deleteFieldIndex, notetype.fields.indices.contains(deleteFieldIndex) else { return }
        guard notetype.fields.count > 1 else {
            errorMessage = L("notetype_field_delete_last_error")
            showError = true
            return
        }

        var updated = notetype
        updated.fields.remove(at: deleteFieldIndex)
        reindexFields(&updated)
        normalizeSortField(&updated)
        adjustCardRequirements(&updated, removingFieldAt: deleteFieldIndex)
        syncDraftsAfterDeletion(at: deleteFieldIndex)
        await persist(updated)
    }

    @MainActor
    private func setSortField(to index: Int) async {
        guard notetype.fields.indices.contains(index) else { return }
        var updated = notetype
        updated.config.sortFieldIdx = UInt32(index)
        await persist(updated, resetDrafts: false)
    }

    private func normalizedFieldName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateFieldName(_ name: String, excluding index: Int?) -> Bool {
        guard !name.isEmpty else {
            errorMessage = L("notetype_field_name_empty")
            showError = true
            return false
        }

        let lowercased = name.lowercased()
        let duplicateExists = notetype.fields.enumerated().contains { currentIndex, field in
            if let index, currentIndex == index {
                return false
            }
            return field.name.lowercased() == lowercased
        }

        guard !duplicateExists else {
            errorMessage = L("notetype_field_name_duplicate")
            showError = true
            return false
        }
        return true
    }

    private func syncDraftsFromNotetype() {
        fieldNameDrafts = notetype.fields.map(\.name)
    }

    private func syncDraftsAfterDeletion(at index: Int) {
        guard fieldNameDrafts.indices.contains(index) else { return }
        fieldNameDrafts.remove(at: index)
    }

    private func reindexFields(_ updated: inout Anki_Notetypes_Notetype) {
        for index in updated.fields.indices {
            var ord = updated.fields[index].ord
            ord.val = UInt32(index)
            updated.fields[index].ord = ord
        }
    }

    private func normalizeSortField(_ updated: inout Anki_Notetypes_Notetype) {
        guard !updated.fields.isEmpty else {
            updated.config.sortFieldIdx = 0
            return
        }
        updated.config.sortFieldIdx = min(updated.config.sortFieldIdx, UInt32(updated.fields.count - 1))
    }

    private func adjustCardRequirements(_ updated: inout Anki_Notetypes_Notetype, removingFieldAt index: Int) {
        let removed = UInt32(index)
        for reqIndex in updated.config.reqs.indices {
            updated.config.reqs[reqIndex].fieldOrds = updated.config.reqs[reqIndex].fieldOrds.compactMap { ord in
                if ord == removed { return nil }
                return ord > removed ? ord - 1 : ord
            }
        }
    }

    @MainActor
    private func persist(_ updated: Anki_Notetypes_Notetype, resetDrafts: Bool = true) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try backend.callVoid(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.updateNotetype,
                request: updated
            )
            notetype = updated
            if resetDrafts || fieldNameDrafts.count != updated.fields.count {
                syncDraftsFromNotetype()
            }
            if let onSaved {
                await onSaved()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            syncDraftsFromNotetype()
        }
    }
}

private struct NotetypeFieldDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggedFieldIndex: Int?
    @Binding var notetype: Anki_Notetypes_Notetype
    @Binding var fieldNameDrafts: [String]
    let onPersist: (Anki_Notetypes_Notetype) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedFieldIndex,
              draggedFieldIndex != targetIndex,
              notetype.fields.indices.contains(draggedFieldIndex),
              notetype.fields.indices.contains(targetIndex)
        else {
            return
        }

        let destination = draggedFieldIndex < targetIndex ? targetIndex + 1 : targetIndex
        var reorderedNotetype = notetype
        var reorderedDrafts = fieldNameDrafts
        reorderFields(
            in: &reorderedNotetype,
            fieldNameDrafts: &reorderedDrafts,
            source: draggedFieldIndex,
            destination: destination
        )
        notetype = reorderedNotetype
        fieldNameDrafts = reorderedDrafts
        self.draggedFieldIndex = min(targetIndex, reorderedNotetype.fields.count - 1)
    }

    func performDrop(info: DropInfo) -> Bool {
        let updated = notetype
        draggedFieldIndex = nil
        onPersist(updated)
        return true
    }
}

private func reorderFields(
    in updated: inout Anki_Notetypes_Notetype,
    fieldNameDrafts: inout [String],
    source: Int,
    destination: Int
) {
    guard updated.fields.indices.contains(source), source != destination else { return }

    let originalSortField = Int(updated.config.sortFieldIdx)
    let originalFieldOrds = updated.config.reqs.map(\.fieldOrds)

    updated.fields.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
    fieldNameDrafts.move(fromOffsets: IndexSet(integer: source), toOffset: destination)

    var newIndexForOld: [Int: Int] = [:]
    for (newIndex, field) in updated.fields.enumerated() {
        newIndexForOld[Int(field.ord.val)] = newIndex
    }

    for index in updated.fields.indices {
        var ord = updated.fields[index].ord
        ord.val = UInt32(index)
        updated.fields[index].ord = ord
    }

    if let newSortIndex = newIndexForOld[originalSortField] {
        updated.config.sortFieldIdx = UInt32(newSortIndex)
    }

    for reqIndex in updated.config.reqs.indices {
        updated.config.reqs[reqIndex].fieldOrds = originalFieldOrds[reqIndex].compactMap { oldOrd in
            newIndexForOld[Int(oldOrd)].map(UInt32.init)
        }
    }
}
