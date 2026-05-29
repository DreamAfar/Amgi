import Foundation
import SwiftUI
import AnkiClients
import AnkiBackend
import AnkiProto
import Dependencies

struct DeckTemplateListView: View {
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.notetypesClient) var notetypesClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    let showsDoneButton: Bool

    @State private var entries: [Anki_Notetypes_NotetypeNameId] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var editorTarget: TemplateEditorTarget?
    @State private var renameTarget: Anki_Notetypes_NotetypeNameId?
    @State private var renameText = ""
    @State private var showRenamePrompt = false
    @State private var pendingNotetypeCreationSource: NotetypeCreationSource?
    @State private var selectedNotetypeCreationSource: NotetypeCreationSource?
    @State private var showAddNotetypeSourcePicker = false
    @State private var addNotetypeText = ""
    @State private var showAddNotetypePrompt = false
    @State private var deleteTarget: Anki_Notetypes_NotetypeNameId?
    @State private var showDeleteConfirm = false
    @State private var pendingSchemaDeleteTarget: Anki_Notetypes_NotetypeNameId?
    @State private var showSchemaChangeConfirm = false
    @State private var actionError: String?
    @State private var showActionError = false

    private var filteredEntries: [Anki_Notetypes_NotetypeNameId] {
        filterDeckTemplateEntries(entries, searchText: searchText)
    }

    init(showsDoneButton: Bool = false) {
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        mainContent
            .background(palette.background)
            .navigationTitle(L("deck_template_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L("deck_template_search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedNotetypeCreationSource = nil
                        showAddNotetypeSourcePicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L("deck_template_add_notetype_title"))
                }
                if showsDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("common_done")) { dismiss() }
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                TemplateEditorView(
                    notetypeId: target.id,
                    initialTemplateIndex: target.initialTemplateIndex,
                    mode: .manager,
                    onSaved: { await loadTemplates() }
                )
            }
            .sheet(isPresented: $showAddNotetypeSourcePicker) {
                NavigationStack {
                    NotetypeCreationSourcePickerView(
                        entries: entries,
                        selection: $selectedNotetypeCreationSource,
                        onCancel: {
                            showAddNotetypeSourcePicker = false
                        },
                        onConfirm: {
                            guard let selectedNotetypeCreationSource else { return }
                            showAddNotetypeSourcePicker = false
                            beginNotetypeCreation(from: selectedNotetypeCreationSource)
                        }
                    )
                }
            }
            .alert(L("deck_template_add_notetype_title"), isPresented: $showAddNotetypePrompt) {
                TextField(L("deck_template_add_notetype_placeholder"), text: $addNotetypeText)
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_add")) {
                    Task { await createNotetype() }
                }
            }
            .alert(L("deck_template_rename_title"), isPresented: $showRenamePrompt) {
                TextField(L("deck_template_rename_placeholder"), text: $renameText)
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_save")) {
                    Task { await renameNotetype() }
                }
            } message: {
                Text(renameTarget?.name ?? "")
            }
            .alert(L("deck_template_delete_title"), isPresented: $showDeleteConfirm) {
                Button(L("common_delete"), role: .destructive) {
                    Task { await requestDeleteNotetype() }
                }
                Button(L("common_cancel"), role: .cancel) {}
            } message: {
                Text(L("deck_template_delete_message", deleteTarget?.name ?? ""))
            }
            .alert(L("sync_full_required_title"), isPresented: $showSchemaChangeConfirm) {
                Button(L("common_cancel"), role: .cancel) {
                    pendingSchemaDeleteTarget = nil
                }
                Button(L("schema_change_confirm_continue")) {
                    Task { await confirmPendingSchemaDelete() }
                }
            } message: {
                Text(L("schema_change_confirm_message"))
            }
            .alert(L("common_error"), isPresented: $showActionError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(actionError ?? L("common_unknown_error"))
            }
            .task {
                await loadTemplates()
            }
    }

    // MARK: - Extracted Sub-views

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            ProgressView()
        } else if let errorMessage {
            AmgiStatusMessageView(
                title: L("deck_template_error_title"),
                message: errorMessage,
                systemImage: "exclamationmark.triangle",
                tone: .warning
            )
        } else if entries.isEmpty {
            ContentUnavailableView(
                L("deck_template_empty_title"),
                systemImage: "square.stack.3d.up.slash",
                description: Text(L("deck_template_empty_desc"))
            )
        } else if filteredEntries.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            templateList
        }
    }

    private var templateList: some View {
        List {
            Section {
                ForEach(filteredEntries, id: \.id) { entry in
                    Button {
                        editorTarget = TemplateEditorTarget(id: entry.id, initialTemplateIndex: 0)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                                Text(entry.name)
                                    .amgiFont(.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text("ID: \(entry.id)")
                                    .amgiFont(.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AmgiFont.caption.font)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .listRowBackground(palette.surfaceElevated)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTarget = entry
                            showDeleteConfirm = true
                        } label: {
                            Label(L("common_delete"), systemImage: "trash")
                        }

                        Button {
                            renameTarget = entry
                            renameText = entry.name
                            showRenamePrompt = true
                        } label: {
                            Label(L("user_mgmt_rename"), systemImage: "pencil")
                        }
                        .tint(palette.accent)

                        Button {
                            beginNotetypeCreation(from: .existing(id: entry.id, name: entry.name))
                        } label: {
                            Label(L("deck_template_copy_action"), systemImage: "doc.on.doc")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .listStyle(.insetGrouped)
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            entries = sortDeckTemplateEntries(try notetypesClient.listAll())
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    private func renameNotetype() async {
        guard let renameTarget else { return }

        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != renameTarget.name else { return }

        do {
            var notetype = try notetypesClient.getRaw(renameTarget.id)
            notetype.name = newName
            try notetypesClient.update(notetype)
            await loadTemplates()
        } catch {
            actionError = L("deck_template_rename_failed", error.localizedDescription)
            showActionError = true
        }
    }

    @MainActor
    private func requestDeleteNotetype() async {
        guard let deleteTarget else { return }

        guard let shouldConfirm = await shouldConfirmSchemaChange() else {
            return
        }

        guard shouldConfirm else {
            await deleteNotetype(deleteTarget)
            return
        }

        pendingSchemaDeleteTarget = deleteTarget
        showSchemaChangeConfirm = true
    }

    @MainActor
    private func confirmPendingSchemaDelete() async {
        guard let pendingSchemaDeleteTarget else { return }
        self.pendingSchemaDeleteTarget = nil
        await deleteNotetype(pendingSchemaDeleteTarget)
    }

    private func deleteNotetype(_ deleteTarget: Anki_Notetypes_NotetypeNameId) async {

        do {
            try notetypesClient.remove(deleteTarget.id)
            SchemaChangeFullSyncGuard.markPendingFullUpload()
            await loadTemplates()
        } catch {
            actionError = L("deck_template_delete_failed", error.localizedDescription)
            showActionError = true
        }
    }

    @MainActor
    private func shouldConfirmSchemaChange() async -> Bool? {
        !SchemaChangeFullSyncGuard.needsFullUpload()
    }

    @MainActor
    private func createNotetype() async {
        guard let pendingNotetypeCreationSource else {
            actionError = L("deck_template_add_notetype_missing_source")
            showActionError = true
            return
        }
        let newName = addNotetypeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            actionError = L("deck_template_add_name_empty")
            showActionError = true
            return
        }
        guard !entries.contains(where: { $0.name.caseInsensitiveCompare(newName) == .orderedSame }) else {
            actionError = L("deck_template_add_notetype_duplicate")
            showActionError = true
            return
        }

        do {
            var jsonObject = try await loadNotetypeCreationPayload(for: pendingNotetypeCreationSource)
            jsonObject["name"] = newName
            if case .existing = pendingNotetypeCreationSource {
                jsonObject["id"] = 0
                jsonObject["originalId"] = NSNull()
            }

            guard JSONSerialization.isValidJSONObject(jsonObject) else {
                throw NSError(domain: "DeckTemplateListView", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid notetype payload."
                ])
            }

            let responseID = try notetypesClient.addLegacyNotetype(
                JSONSerialization.data(withJSONObject: jsonObject)
            )

            await loadTemplates()
            addNotetypeText = ""
            self.pendingNotetypeCreationSource = nil
            editorTarget = TemplateEditorTarget(id: responseID, initialTemplateIndex: 0)
        } catch {
            actionError = L("deck_template_add_notetype_failed", error.localizedDescription)
            showActionError = true
        }
    }

    private func beginNotetypeCreation(from source: NotetypeCreationSource) {
        pendingNotetypeCreationSource = source
        addNotetypeText = defaultNotetypeName(for: source)
        showAddNotetypePrompt = true
    }

    private func defaultNotetypeName(for source: NotetypeCreationSource) -> String {
        switch source {
        case .stock(_, let name):
            return name
        case .existing(_, let name):
            return "\(name) \(L("deck_template_copy_suffix"))"
        }
    }

    private func loadNotetypeCreationPayload(for source: NotetypeCreationSource) async throws -> [String: Any] {
        let payload: Data

        switch source {
        case .stock(let kind, _):
            payload = try notetypesClient.getStockNotetypePayload(kind)
        case .existing(let id, _):
            payload = try notetypesClient.getLegacyNotetypePayload(id)
        }

        guard let jsonObject = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw NSError(domain: "DeckTemplateListView", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid notetype payload."
            ])
        }
        return jsonObject
    }
}

private enum NotetypeCreationSource: Hashable {
    case stock(Anki_Notetypes_StockNotetype.Kind, name: String)
    case existing(id: Int64, name: String)
}

private struct NotetypeCreationSourcePickerView: View {
    let entries: [Anki_Notetypes_NotetypeNameId]
    @Binding var selection: NotetypeCreationSource?
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.palette) private var palette

    private var stockSources: [NotetypeCreationSource] {
        [
            .stock(.basic, name: L("deck_template_stock_basic")),
            .stock(.basicAndReversed, name: L("deck_template_stock_basic_reversed")),
            .stock(.basicOptionalReversed, name: L("deck_template_stock_basic_optional_reversed")),
            .stock(.basicTyping, name: L("deck_template_stock_basic_typing")),
            .stock(.cloze, name: L("deck_template_stock_cloze")),
            .stock(.imageOcclusion, name: L("deck_template_stock_image_occlusion")),
        ]
    }

    var body: some View {
        List {
            Section {
                Text(L("deck_template_add_notetype_source_message"))
                    .amgiFont(.body)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.vertical, 4)
            }

            Section(L("deck_template_add_notetype_source_presets")) {
                ForEach(stockSources, id: \.self) { source in
                    sourceRow(source, title: source.displayTitle, subtitle: L("deck_template_add_notetype_source_add"))
                }
            }

            Section(L("deck_template_add_notetype_source_existing")) {
                ForEach(entries, id: \.id) { entry in
                    let source = NotetypeCreationSource.existing(id: entry.id, name: entry.name)
                    sourceRow(source, title: entry.name, subtitle: L("deck_template_add_notetype_source_copy"))
                }
            }
        }
        .navigationTitle(L("deck_template_add_notetype_source_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L("common_cancel")) {
                    onCancel()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_add")) {
                    onConfirm()
                }
                .amgiToolbarTextButton()
                .disabled(selection == nil)
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: NotetypeCreationSource, title: String, subtitle: String) -> some View {
        Button {
            selection = source
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .amgiFont(.body)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if selection == source {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private extension NotetypeCreationSource {
    var displayTitle: String {
        switch self {
        case .stock(_, let name), .existing(_, let name):
            return name
        }
    }
}

private struct TemplateEditorTarget: Identifiable {
    let id: Int64
    let initialTemplateIndex: Int
}

enum TemplateEditorMode {
    case manager
    case currentCard

    var title: String {
        switch self {
        case .manager:
            return L("card_template_editor_title")
        case .currentCard:
            return L("card_template_editor_title")
        }
    }

    var allowsTemplateSelection: Bool {
        switch self {
        case .manager:
            return true
        case .currentCard:
            return false
        }
    }
}

private enum TemplateEditorTab: CaseIterable {
    case front
    case back
    case css
    case preview

    var label: String {
        switch self {
        case .front:
            return L("deck_template_edit_qformat")
        case .back:
            return L("deck_template_edit_aformat")
        case .css:
            return "CSS"
        case .preview:
            return L("card_template_preview_btn")
        }
    }
}

struct TemplateEditorView: View {
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.notetypesClient) var notetypesClient
    @Dependency(\.noteClient) var noteClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette

    let notetypeId: Int64
    let previewNoteId: Int64?
    let initialTemplateIndex: Int
    let mode: TemplateEditorMode
    var onSaved: (@Sendable () async -> Void)? = nil

    @AppStorage(CodeEditorPreferences.fontSizeKey) private var codeEditorFontSize: Double = 14.0
    @AppStorage(CodeEditorPreferences.templateInsertTokensKey) private var customTemplateInsertTokensRaw = ""

    @State private var notetype: Anki_Notetypes_Notetype = .init()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var originalNotetype: Anki_Notetypes_Notetype?
    @State private var showDiscardChangesConfirmation = false
    @State private var showSaveError = false
    @State private var selectedTemplateIndex = 0
    @State private var editorTab: TemplateEditorTab = .front
    @State private var showFieldManager = false
    @State private var showPreviewSheet = false
    @State private var editorSearchText = ""
    @State private var editorSearchNavigationToken = 0
    @State private var editorSearchNavigationDirection: TemplateSourceEditor.SearchNavigationDirection = .next
    @State private var editorSearchCurrentMatch = 0
    @State private var editorSearchTotalMatches = 0
    @State private var addTemplateText = ""
    @State private var showAddTemplatePrompt = false
    @State private var copyTemplateText = ""
    @State private var showCopyTemplatePrompt = false
    @State private var renameTemplateText = ""
    @State private var showRenameTemplatePrompt = false
    @State private var reorderTemplateText = ""
    @State private var showReorderTemplatePrompt = false
    @State private var showDeleteTemplateConfirm = false
    @State private var pendingSchemaTemplateAction: TemplateSchemaAction?
    @State private var showSchemaChangeConfirm = false
    @State private var hasConfirmedSchemaChangeInSession = false
    @State private var hasPendingSchemaMutation = false
    @State private var templateActionError: String?
    @State private var showTemplateActionError = false

    init(
        notetypeId: Int64,
        previewNoteId: Int64? = nil,
        initialTemplateIndex: Int,
        mode: TemplateEditorMode,
        onSaved: (@Sendable () async -> Void)? = nil
    ) {
        self.notetypeId = notetypeId
        self.previewNoteId = previewNoteId
        self.initialTemplateIndex = initialTemplateIndex
        self.mode = mode
        self.onSaved = onSaved
    }

    private var hasUnsavedChanges: Bool {
        guard let originalNotetype else { return false }
        return originalNotetype != notetype
    }

    private var currentTemplateValidationMessage: String? {
        templateValidationMessage(for: notetype)
    }

    private var canSaveTemplate: Bool {
        notetype.templates.indices.contains(selectedTemplateIndex)
            && currentTemplateValidationMessage == nil
            && !isSaving
    }

    private var canAddTemplate: Bool {
        mode == .manager && notetype.config.kind != .cloze && !notetype.fields.isEmpty && !isLoading
    }

    private var showsTemplateActionMenu: Bool {
        mode == .manager
    }

    private var canMutateTemplateStructure: Bool {
        mode == .manager && notetype.config.kind != .cloze
    }

    private var canDeleteOrReorderTemplate: Bool {
        canMutateTemplateStructure
            && notetype.templates.count > 1
            && notetype.templates.indices.contains(selectedTemplateIndex)
    }

    private var separatorBorderColor: Color {
        colorScheme == .light
            ? palette.border.opacity(0.8)
            : palette.border.opacity(0.5)
    }

    private var currentTemplateName: String {
        guard notetype.templates.indices.contains(selectedTemplateIndex) else {
            return L("deck_template_preview_no_template")
        }
        return notetype.templates[selectedTemplateIndex].name
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    AmgiStatusMessageView(
                        title: L("deck_template_error_title"),
                        message: errorMessage,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                } else {
                    editorContent
                }
            }
            .background(palette.background)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasUnsavedChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_cancel")) { attemptDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("card_template_fields_short")) {
                        showFieldManager = true
                    }
                    .amgiToolbarTextButton(tone: .neutral)
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L("btn_save")) {
                            Task { await saveTemplate() }
                        }
                        .amgiToolbarTextButton()
                        .disabled(!canSaveTemplate)
                    }
                }
            }
            .alert(L("deck_template_save_failed"), isPresented: $showSaveError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .alert(L("deck_template_add_template_title"), isPresented: $showAddTemplatePrompt) {
                TextField(L("deck_template_add_template_placeholder"), text: $addTemplateText)
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_add")) {
                    Task { await requestAddTemplate() }
                }
            }
            .alert(L("deck_template_copy_template_title"), isPresented: $showCopyTemplatePrompt) {
                TextField(L("deck_template_copy_template_placeholder"), text: $copyTemplateText)
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_add")) {
                    Task { await requestCopyTemplate() }
                }
            }
            .alert(L("deck_template_rename_template_title"), isPresented: $showRenameTemplatePrompt) {
                TextField(L("deck_template_rename_template_placeholder"), text: $renameTemplateText)
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_save")) {
                    renameCurrentTemplate()
                }
            }
            .alert(L("deck_template_reorder_template_title"), isPresented: $showReorderTemplatePrompt) {
                TextField(L("deck_template_reorder_template_placeholder"), text: $reorderTemplateText)
                    .keyboardType(.numberPad)
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_save")) {
                    Task { await requestReorderTemplate() }
                }
            } message: {
                Text(L("deck_template_reorder_template_message", currentTemplateName, notetype.templates.count))
            }
            .alert(L("deck_template_delete_template_title"), isPresented: $showDeleteTemplateConfirm) {
                Button(L("common_delete"), role: .destructive) {
                    Task { await requestDeleteTemplate() }
                }
                Button(L("common_cancel"), role: .cancel) {}
            } message: {
                Text(L("deck_template_delete_template_message", currentTemplateName))
            }
            .alert(L("sync_full_required_title"), isPresented: $showSchemaChangeConfirm) {
                Button(L("common_cancel"), role: .cancel) {
                    pendingSchemaTemplateAction = nil
                }
                Button(L("schema_change_confirm_continue")) {
                    Task { await confirmPendingSchemaTemplateAction() }
                }
            } message: {
                Text(L("schema_change_confirm_message"))
            }
            .alert(L("common_error"), isPresented: $showTemplateActionError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(templateActionError ?? L("common_unknown_error"))
            }
            .confirmationDialog(
                L("common_unsaved_changes_title"),
                isPresented: $showDiscardChangesConfirmation,
                titleVisibility: .visible
            ) {
                Button(L("common_discard_changes"), role: .destructive) {
                    dismiss()
                }
                Button(L("common_cancel"), role: .cancel) {}
            } message: {
                Text(L("common_unsaved_changes_message"))
            }
            .sheet(isPresented: $showFieldManager) {
                NavigationStack {
                    NotetypeFieldEditorView(
                        notetypeId: notetypeId,
                        preferredName: notetype.name,
                        onSaved: {
                            await loadNotetype(
                                preserveEditorDrafts: true,
                                preferredTemplateIndex: selectedTemplateIndex
                            )
                            if let onSaved {
                                await onSaved()
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showPreviewSheet) {
                previewSheet
            }
            .task {
                await loadNotetype(preferredTemplateIndex: initialTemplateIndex)
            }
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        currentTemplateSelectionView
                        Spacer(minLength: 0)
                        if showsTemplateActionMenu {
                            templateActionMenu
                        }
                    }

                    Picker(L("deck_template_edit_template"), selection: $editorTab) {
                        ForEach(TemplateEditorTab.allCases, id: \.self) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .onChange(of: editorTab) { old, new in
                        if new == .preview {
                            showPreviewSheet = true
                            editorTab = old
                        }
                    }
                }
                .padding(16)
                .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(separatorBorderColor, lineWidth: 1)
                }

                if let currentTemplateValidationMessage {
                    AmgiStatusMessageView(
                        title: L("deck_template_validation_title"),
                        message: currentTemplateValidationMessage,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }

                TemplateSourceEditor(
                    text: currentEditorBinding,
                    fieldNames: currentFieldNames,
                    insertableTokens: currentInsertableTokens,
                    fieldButtonTitle: L("card_template_fields_short"),
                    doneButtonTitle: L("common_done"),
                    searchQuery: editorSearchText,
                    searchNavigationToken: editorSearchNavigationToken,
                    searchNavigationDirection: editorSearchNavigationDirection,
                    onSearchResultChanged: { current, total in
                        editorSearchCurrentMatch = current
                        editorSearchTotalMatches = total
                    },
                    fontSize: codeEditorFontSize
                )
                .padding(16)
                .frame(minHeight: 420)
                .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(separatorBorderColor, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("card_template_search_title"))
                        .amgiFont(.captionBold)
                        .foregroundStyle(palette.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(palette.textSecondary)
                        TextField(L("card_template_search_placeholder"), text: $editorSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if !editorSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(spacing: 4) {
                                Text("\(editorSearchCurrentMatch)/\(editorSearchTotalMatches)")
                                    .amgiFont(.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .monospacedDigit()
                                    .frame(minWidth: 40, alignment: .trailing)

                                Button {
                                    editorSearchNavigationDirection = .previous
                                    editorSearchNavigationToken += 1
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .disabled(editorSearchTotalMatches == 0)
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 28, height: 28)

                                Button {
                                    editorSearchNavigationDirection = .next
                                    editorSearchNavigationToken += 1
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .disabled(editorSearchTotalMatches == 0)
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 28, height: 28)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(separatorBorderColor, lineWidth: 1)
                    }
                }
            }
            .padding(20)
        }
        .background(palette.background)
    }

    private var previewSheet: some View {
        UncommittedCardPreviewSheet(
            title: L("deck_template_preview_rendered"),
            emptyMessage: L("deck_template_preview_empty_card"),
            notetype: notetype,
            initialTemplateIndex: selectedTemplateIndex,
            allowsTemplateSelection: false,
            loadPreviewNote: {
                let noteClient = self.noteClient
                let notetypeId = self.notetypeId
                let previewNoteId = self.previewNoteId
                let notetype = self.notetype
                return try await Task.detached(priority: .userInitiated) {
                    if let previewNoteId,
                       let currentNote = try noteClient.fetch(previewNoteId) {
                        return NoteProtoFactory.makeNote(from: currentNote)
                    }
                    if let sampleNote = try noteClient.search("mid:\(notetypeId)", 1).first {
                        return NoteProtoFactory.makeNote(from: sampleNote)
                    }
                    return NoteProtoFactory.makeEmptyUncommittedNote(
                        notetypeId: notetypeId,
                        fieldCount: notetype.fields.count
                    )
                }.value
            }
        )
    }

    @ViewBuilder
    private var currentTemplateSelectionView: some View {
        if mode.allowsTemplateSelection, notetype.templates.count > 1 {
            Menu {
                ForEach(Array(notetype.templates.enumerated()), id: \.offset) { index, template in
                    Button {
                        selectedTemplateIndex = index
                    } label: {
                        if selectedTemplateIndex == index {
                            Label(template.name, systemImage: "checkmark")
                        } else {
                            Text(template.name)
                        }
                    }
                }
            } label: {
                templateSwitcherChip(showsIndicator: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            templateSwitcherChip(showsIndicator: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func templateSwitcherChip(showsIndicator: Bool) -> some View {
        HStack(spacing: 6) {
            Text(currentTemplateName)
                .amgiFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)

            if showsIndicator {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.surfaceElevated, in: Capsule())
    }

    private var templateActionMenu: some View {
        Menu {
            if canMutateTemplateStructure {
                Button {
                    addTemplateText = ""
                    showAddTemplatePrompt = true
                } label: {
                    Label(L("deck_template_menu_add_template"), systemImage: "plus")
                }
                .disabled(!canAddTemplate)

                Button {
                    copyTemplateText = defaultCopiedTemplateName(for: currentTemplateName)
                    showCopyTemplatePrompt = true
                } label: {
                    Label(L("deck_template_menu_copy_template"), systemImage: "doc.on.doc")
                }
                .disabled(!notetype.templates.indices.contains(selectedTemplateIndex))
            }

            Button {
                renameTemplateText = currentTemplateName
                showRenameTemplatePrompt = true
            } label: {
                Label(L("deck_template_menu_rename_template"), systemImage: "pencil")
            }
            .disabled(!notetype.templates.indices.contains(selectedTemplateIndex))

            if canDeleteOrReorderTemplate {
                Button {
                    reorderTemplateText = "\(selectedTemplateIndex + 1)"
                    showReorderTemplatePrompt = true
                } label: {
                    Label(L("deck_template_menu_reorder_template"), systemImage: "arrow.up.arrow.down")
                }

                Button(role: .destructive) {
                    showDeleteTemplateConfirm = true
                } label: {
                    Label(L("deck_template_menu_delete_template"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.medium))
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityLabel(L("deck_template_menu_more"))
    }

    private var currentFieldNames: [String] {
        editorTab == .css ? [] : notetype.fields.map(\.name)
    }

    private var currentInsertableTokens: [String] {
        let fallbackTokens: [String]
        switch editorTab {
        case .front, .back, .preview:
            fallbackTokens = ["(", ")", ".", "=", "#", "<br>", "{{FrontSide}}"]
        case .css:
            fallbackTokens = ["{", "}", ":", ";", ".", "#"]
        }
        return CodeEditorPreferences.resolvedTemplateInsertTokens(
            from: customTemplateInsertTokensRaw,
            fallback: fallbackTokens
        )
    }

    private var currentEditorBinding: Binding<String> {
        switch editorTab {
        case .front:
            return qFormatBinding
        case .back:
            return aFormatBinding
        case .css:
            return cssBinding
        case .preview:
            return qFormatBinding
        }
    }

    private var qFormatBinding: Binding<String> {
        Binding(
            get: {
                guard notetype.templates.indices.contains(selectedTemplateIndex) else { return "" }
                return notetype.templates[selectedTemplateIndex].config.qFormat
            },
            set: { newValue in
                guard notetype.templates.indices.contains(selectedTemplateIndex) else { return }
                var config = notetype.templates[selectedTemplateIndex].config
                config.qFormat = newValue
                notetype.templates[selectedTemplateIndex].config = config
            }
        )
    }

    private var aFormatBinding: Binding<String> {
        Binding(
            get: {
                guard notetype.templates.indices.contains(selectedTemplateIndex) else { return "" }
                return notetype.templates[selectedTemplateIndex].config.aFormat
            },
            set: { newValue in
                guard notetype.templates.indices.contains(selectedTemplateIndex) else { return }
                var config = notetype.templates[selectedTemplateIndex].config
                config.aFormat = newValue
                notetype.templates[selectedTemplateIndex].config = config
            }
        )
    }

    private var cssBinding: Binding<String> {
        Binding(
            get: { notetype.config.css },
            set: { newValue in
                var config = notetype.config
                config.css = newValue
                notetype.config = config
            }
        )
    }

    @MainActor
    private func loadNotetype(
        preserveEditorDrafts: Bool = false,
        preferredTemplateIndex: Int? = nil
    ) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try notetypesClient.getRaw(notetypeId)
            var refreshed = fetched
            if preserveEditorDrafts {
                refreshed.templates = notetype.templates
                var config = refreshed.config
                config.css = notetype.config.css
                refreshed.config = config
            }
            notetype = refreshed
            originalNotetype = fetched
            normalizeTemplateIndex(
                preferred: preferredTemplateIndex ?? (preserveEditorDrafts ? selectedTemplateIndex : initialTemplateIndex)
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            showDiscardChangesConfirmation = true
        } else {
            dismiss()
        }
    }

    @MainActor
    private func saveTemplate() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try notetypesClient.update(notetype)
            if hasPendingSchemaMutation {
                SchemaChangeFullSyncGuard.markPendingFullUpload()
            }
            hasPendingSchemaMutation = false
            hasConfirmedSchemaChangeInSession = false
            if let onSaved {
                await onSaved()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    private func normalizeTemplateIndex(preferred: Int? = nil) {
        guard !notetype.templates.isEmpty else {
            selectedTemplateIndex = 0
            return
        }
        if let preferred, notetype.templates.indices.contains(preferred) {
            selectedTemplateIndex = preferred
            return
        }
        if !notetype.templates.indices.contains(selectedTemplateIndex) {
            selectedTemplateIndex = 0
        }
    }

    @MainActor
    private func requestAddTemplate() async {
        guard validateTemplateStructureMutationAllowed(),
              let newName = validatedTemplateName(addTemplateText) else { return }
        await requestTemplateSchemaAction(.add(name: newName))
    }

    @MainActor
    private func requestCopyTemplate() async {
        guard validateTemplateStructureMutationAllowed(),
              let newName = validatedTemplateName(copyTemplateText) else { return }
        guard notetype.templates.indices.contains(selectedTemplateIndex) else { return }
        await requestTemplateSchemaAction(.copy(sourceIndex: selectedTemplateIndex, name: newName))
    }

    @MainActor
    private func requestDeleteTemplate() async {
        guard canDeleteOrReorderTemplate else { return }
        await requestTemplateSchemaAction(.delete(index: selectedTemplateIndex))
    }

    @MainActor
    private func requestReorderTemplate() async {
        guard canDeleteOrReorderTemplate else { return }
        let trimmed = reorderTemplateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newPosition = Int(trimmed),
              (1...notetype.templates.count).contains(newPosition) else {
            templateActionError = L("deck_template_reorder_template_invalid")
            showTemplateActionError = true
            return
        }
        let newIndex = newPosition - 1
        guard newIndex != selectedTemplateIndex else { return }
        await requestTemplateSchemaAction(.reorder(sourceIndex: selectedTemplateIndex, targetIndex: newIndex))
    }

    @MainActor
    private func confirmPendingSchemaTemplateAction() async {
        guard let action = pendingSchemaTemplateAction else { return }
        hasConfirmedSchemaChangeInSession = true
        pendingSchemaTemplateAction = nil
        applyTemplateSchemaAction(action)
    }

    private func validatedTemplateName(_ rawName: String, excluding index: Int? = nil) -> String? {
        let newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            templateActionError = L("deck_template_add_name_empty")
            showTemplateActionError = true
            return nil
        }
        guard !notetype.templates.enumerated().contains(where: { currentIndex, template in
            if let index, currentIndex == index {
                return false
            }
            return template.name.caseInsensitiveCompare(newName) == .orderedSame
        }) else {
            templateActionError = L("deck_template_add_template_duplicate")
            showTemplateActionError = true
            return nil
        }
        return newName
    }

    private func validateTemplateStructureMutationAllowed() -> Bool {
        guard !notetype.fields.isEmpty else {
            templateActionError = L("deck_template_add_template_requires_field")
            showTemplateActionError = true
            return false
        }
        return true
    }

    private func addTemplate(named newName: String) {
        var template = notetype.templates.first ?? Anki_Notetypes_Notetype.Template()
        template.name = newName
        template.mtimeSecs = 0
        template.usn = 0
        template.clearOrd()

        var config = template.config
        config.qFormat = ""
        config.aFormat = ""
        config.qFormatBrowser = ""
        config.aFormatBrowser = ""
        config.targetDeckID = 0
        config.clearID()
        template.config = config

        notetype.templates.append(template)
        reindexTemplates()
        addTemplateText = ""
        normalizeTemplateIndex(preferred: notetype.templates.count - 1)
        editorTab = .front
    }

    private func copyTemplate(from sourceIndex: Int, named newName: String) {
        guard notetype.templates.indices.contains(sourceIndex) else { return }
        var template = notetype.templates[sourceIndex]
        template.name = newName
        template.mtimeSecs = 0
        template.usn = 0
        template.clearOrd()
        var config = template.config
        config.clearID()
        template.config = config
        notetype.templates.append(template)
        reindexTemplates()
        copyTemplateText = ""
        normalizeTemplateIndex(preferred: notetype.templates.count - 1)
        editorTab = .front
    }

    private func renameCurrentTemplate() {
        guard notetype.templates.indices.contains(selectedTemplateIndex) else { return }
        guard let newName = validatedTemplateName(renameTemplateText, excluding: selectedTemplateIndex) else { return }
        guard newName != notetype.templates[selectedTemplateIndex].name else { return }
        notetype.templates[selectedTemplateIndex].name = newName
        renameTemplateText = ""
    }

    private func deleteTemplate(at index: Int) {
        guard notetype.templates.indices.contains(index), notetype.templates.count > 1 else { return }
        notetype.templates.remove(at: index)
        reindexTemplates()
        normalizeTemplateIndex(preferred: min(index, notetype.templates.count - 1))
    }

    private func reorderTemplate(from sourceIndex: Int, to targetIndex: Int) {
        guard notetype.templates.indices.contains(sourceIndex),
              notetype.templates.indices.contains(targetIndex),
              sourceIndex != targetIndex else { return }
        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        notetype.templates.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        reindexTemplates()
        normalizeTemplateIndex(preferred: targetIndex)
    }

    private func reindexTemplates() {
        for index in notetype.templates.indices {
            var ord = notetype.templates[index].ord
            ord.val = UInt32(index)
            notetype.templates[index].ord = ord
        }
    }

    private func defaultCopiedTemplateName(for name: String) -> String {
        "\(name) \(L("deck_template_copy_suffix"))"
    }

    @MainActor
    private func requestTemplateSchemaAction(_ action: TemplateSchemaAction) async {
        if hasConfirmedSchemaChangeInSession {
            applyTemplateSchemaAction(action)
            return
        }

        guard let shouldConfirm = await shouldConfirmSchemaChange() else {
            return
        }

        guard shouldConfirm else {
            applyTemplateSchemaAction(action)
            return
        }

        pendingSchemaTemplateAction = action
        showSchemaChangeConfirm = true
    }

    @MainActor
    private func applyTemplateSchemaAction(_ action: TemplateSchemaAction) {
        hasPendingSchemaMutation = true
        switch action {
        case .add(let name):
            addTemplate(named: name)
        case .copy(let sourceIndex, let name):
            copyTemplate(from: sourceIndex, named: name)
        case .delete(let index):
            deleteTemplate(at: index)
        case .reorder(let sourceIndex, let targetIndex):
            reorderTemplate(from: sourceIndex, to: targetIndex)
        }
    }

    @MainActor
    private func shouldConfirmSchemaChange() async -> Bool? {
        !SchemaChangeFullSyncGuard.needsFullUpload()
    }
}

private enum TemplateSchemaAction {
    case add(name: String)
    case copy(sourceIndex: Int, name: String)
    case delete(index: Int)
    case reorder(sourceIndex: Int, targetIndex: Int)
}

func sortDeckTemplateEntries(
    _ entries: [Anki_Notetypes_NotetypeNameId]
) -> [Anki_Notetypes_NotetypeNameId] {
    entries.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
}

func filterDeckTemplateEntries(
    _ entries: [Anki_Notetypes_NotetypeNameId],
    searchText: String
) -> [Anki_Notetypes_NotetypeNameId] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return entries }
    return entries.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
}

private enum TemplateValidationIssue {
    case noFrontField(templateName: String)
    case noSuchField(templateName: String, fieldName: String)
    case missingCloze
}

private struct TemplateReference {
    let fieldName: String
    let filters: [String]
}

private let templateReferenceRegex = try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
private let specialTemplateFieldNames: Set<String> = [
    "FrontSide",
    "Card",
    "CardFlag",
    "Deck",
    "Subdeck",
    "Tags",
    "Type",
    "CardID",
]

private func templateValidationMessage(for notetype: Anki_Notetypes_Notetype) -> String? {
    switch templateValidationIssue(for: notetype) {
    case .noFrontField(let templateName):
        return L("deck_template_validation_no_front_field", templateName)
    case .noSuchField(let templateName, let fieldName):
        return L("deck_template_validation_no_such_field", templateName, fieldName)
    case .missingCloze:
        return L("deck_template_validation_missing_cloze")
    case .none:
        return nil
    }
}

private func templateValidationIssue(for notetype: Anki_Notetypes_Notetype) -> TemplateValidationIssue? {
    let availableFieldNames = Set(notetype.fields.map(\.name))

    for template in notetype.templates {
        let frontReferences = extractTemplateReferences(from: template.config.qFormat)
        let backReferences = extractTemplateReferences(from: template.config.aFormat)

        if frontReferences.isEmpty {
            return .noFrontField(templateName: template.name)
        }

        if let unknownField = (frontReferences + backReferences)
            .map(\.fieldName)
            .first(where: { fieldName in
                !fieldName.isEmpty
                    && !specialTemplateFieldNames.contains(fieldName)
                    && !availableFieldNames.contains(fieldName)
            }) {
            return .noSuchField(templateName: template.name, fieldName: unknownField)
        }
    }

    if notetype.config.kind == .cloze {
        guard let firstTemplate = notetype.templates.first else {
            return .missingCloze
        }

        let frontHasCloze = extractTemplateReferences(from: firstTemplate.config.qFormat)
            .contains(where: containsClozeFilter)
        let backHasCloze = extractTemplateReferences(from: firstTemplate.config.aFormat)
            .contains(where: containsClozeFilter)

        if !frontHasCloze || !backHasCloze {
            return .missingCloze
        }
    }

    return nil
}

private func extractTemplateReferences(from source: String) -> [TemplateReference] {
    let range = NSRange(source.startIndex..., in: source)
    return templateReferenceRegex.matches(in: source, range: range).compactMap { match in
        guard match.numberOfRanges > 1,
              let contentRange = Range(match.range(at: 1), in: source) else {
            return nil
        }

        var content = source[contentRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return TemplateReference(fieldName: "", filters: [])
        }

        if let first = content.first, ["#", "^", "/"].contains(first) {
            content.removeFirst()
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let components = content
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let fieldName = components.last else {
            return nil
        }

        return TemplateReference(
            fieldName: fieldName,
            filters: Array(components.dropLast())
        )
    }
}

private func containsClozeFilter(_ reference: TemplateReference) -> Bool {
    reference.filters.contains { $0.caseInsensitiveCompare("cloze") == .orderedSame }
}
