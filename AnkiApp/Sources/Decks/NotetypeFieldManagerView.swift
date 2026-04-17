import SwiftUI
import AnkiBackend
import AnkiProto
import Dependencies

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
                ContentUnavailableView(
                    L("notetype_field_error_title"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
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
    @State private var renameFieldIndex: Int?
    @State private var renameFieldName = ""
    @State private var showRenamePrompt = false
    @State private var deleteFieldIndex: Int?
    @State private var showDeleteConfirm = false

    private var titleText: String {
        if !notetype.name.isEmpty {
            return notetype.name
        }
        return preferredName ?? L("settings_row_field_manager")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                List {
                    summarySection
                    fieldsSection
                }
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
                        .amgiToolbarIconButton()
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
        .alert(L("notetype_field_rename_title"), isPresented: $showRenamePrompt) {
            TextField(L("notetype_field_name_placeholder"), text: $renameFieldName)
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_save")) {
                Task { await renameField() }
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
            await loadNotetype()
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent(L("notetype_field_count"), value: "\(notetype.fields.count)")
        }
    }

    private var fieldsSection: some View {
        Section {
            ForEach(Array(notetype.fields.enumerated()), id: \.offset) { index, field in
                fieldRow(field, at: index)
            }
        } header: {
            Text(L("notetype_field_section_fields"))
        } footer: {
            Text(L("notetype_field_footer"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
        }
    }

    private func fieldRow(_ field: Anki_Notetypes_Notetype.Field, at index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .foregroundStyle(Color.amgiAccent)
            VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                Text(field.name)
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextPrimary)
                Text(L("notetype_field_position", index + 1))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !field.config.preventDeletion && notetype.fields.count > 1 {
                Button(role: .destructive) {
                    deleteFieldIndex = index
                    showDeleteConfirm = true
                } label: {
                    Label(L("common_delete"), systemImage: "trash")
                }
            }

            Button {
                renameFieldIndex = index
                renameFieldName = field.name
                showRenamePrompt = true
            } label: {
                Label(L("user_mgmt_rename"), systemImage: "pencil")
            }
            .tint(Color.amgiAccent)
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
        guard validateFieldName(newName, excluding: nil) else { return }

        var updated = notetype
        var field = Anki_Notetypes_Notetype.Field()
        var ord = Anki_Generic_UInt32()
        ord.val = UInt32(updated.fields.count)
        field.ord = ord
        field.name = newName
        updated.fields.append(field)
        await persist(updated)
    }

    @MainActor
    private func renameField() async {
        guard let renameFieldIndex, notetype.fields.indices.contains(renameFieldIndex) else { return }
        let newName = normalizedFieldName(renameFieldName)
        guard validateFieldName(newName, excluding: renameFieldIndex) else { return }

        var updated = notetype
        updated.fields[renameFieldIndex].name = newName
        await persist(updated)
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
        await persist(updated)
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