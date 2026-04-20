import Foundation
import SwiftUI
import AnkiClients
import AnkiBackend
import AnkiProto
import Dependencies

struct DeckTemplateListView: View {
    @Dependency(\.ankiBackend) var backend
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [Anki_Notetypes_NotetypeNameId] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var editorTarget: TemplateEditorTarget?
    @State private var renameTarget: Anki_Notetypes_NotetypeNameId?
    @State private var renameText = ""
    @State private var showRenamePrompt = false
    @State private var deleteTarget: Anki_Notetypes_NotetypeNameId?
    @State private var showDeleteConfirm = false
    @State private var actionError: String?
    @State private var showActionError = false

    private var filteredEntries: [Anki_Notetypes_NotetypeNameId] {
        filterDeckTemplateEntries(entries, searchText: searchText)
    }

    var body: some View {
        mainContent
            .background(Color.amgiBackground)
            .navigationTitle(L("deck_template_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L("deck_template_search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                        .amgiToolbarTextButton()
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
                    Task { await deleteNotetype() }
                }
                Button(L("common_cancel"), role: .cancel) {}
            } message: {
                Text(L("deck_template_delete_message", deleteTarget?.name ?? ""))
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
        List(filteredEntries, id: \.id) { entry in
            Button {
                editorTarget = TemplateEditorTarget(id: entry.id, initialTemplateIndex: 0)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(Color.amgiAccent)
                    VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                        Text(entry.name)
                            .amgiFont(.body)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Text("ID: \(entry.id)")
                            .amgiFont(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AmgiFont.caption.font)
                        .foregroundStyle(Color.amgiTextTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
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
                .tint(Color.amgiAccent)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .listStyle(.plain)
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let resp: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )
            entries = sortDeckTemplateEntries(resp.entries)
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
            var req = Anki_Notetypes_NotetypeId()
            req.ntid = renameTarget.id
            var notetype: Anki_Notetypes_Notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: req
            )
            notetype.name = newName
            try backend.callVoid(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.updateNotetype,
                request: notetype
            )
            await loadTemplates()
        } catch {
            actionError = L("deck_template_rename_failed", error.localizedDescription)
            showActionError = true
        }
    }

    private func deleteNotetype() async {
        guard let deleteTarget else { return }

        do {
            var req = Anki_Notetypes_NotetypeId()
            req.ntid = deleteTarget.id
            try backend.callVoid(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.removeNotetype,
                request: req
            )
            await loadTemplates()
        } catch {
            actionError = L("deck_template_delete_failed", error.localizedDescription)
            showActionError = true
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
    @Dependency(\.noteClient) var noteClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let notetypeId: Int64
    let previewNoteId: Int64? = nil
    let initialTemplateIndex: Int
    let mode: TemplateEditorMode
    var onSaved: (@Sendable () async -> Void)? = nil

    @AppStorage("codeEditor_fontSize") private var codeEditorFontSize: Double = 14.0

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

    private var separatorBorderColor: Color {
        colorScheme == .light
            ? Color.amgiBorder.opacity(0.8)
            : Color.amgiBorder.opacity(0.5)
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
            .background(Color.amgiBackground)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(hasUnsavedChanges)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { attemptDismiss() }
                        .amgiToolbarTextButton(tone: .neutral)
                }
                ToolbarItem(placement: .principal) {
                    Text(mode.title)
                        .amgiFont(.bodyEmphasis)
                        .foregroundStyle(Color.amgiTextPrimary)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("card_template_fields_short")) {
                        showFieldManager = true
                    }
                    .amgiToolbarTextButton(tone: .neutral)
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
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
                    NotetypeFieldManagerView(
                        notetypeId: notetypeId,
                        preferredName: notetype.name,
                        onSaved: {
                            await loadNotetype()
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
                await loadNotetype()
            }
        }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    if mode.allowsTemplateSelection, notetype.templates.count > 1 {
                        HStack(spacing: 12) {
                            Text(currentTemplateName)
                                .amgiFont(.bodyEmphasis)
                                .foregroundStyle(Color.amgiTextSecondary)
                            
                            Spacer()
                            
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
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(AmgiFont.caption.font)
                                        .foregroundStyle(Color.amgiTextSecondary)
                                }
                                .amgiCapsuleControl(horizontalPadding: 12, verticalPadding: 8)
                            }
                        }
                    } else {
                        Text(currentTemplateName)
                            .amgiFont(.bodyEmphasis)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }

                    Picker("Template Editor", selection: $editorTab) {
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
                .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                    fontSize: codeEditorFontSize
                )
                .padding(16)
                .frame(minHeight: 420)
                .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(separatorBorderColor, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("card_template_search_title"))
                        .amgiFont(.captionBold)
                        .foregroundStyle(Color.amgiTextSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.amgiTextSecondary)
                        TextField(L("card_template_search_placeholder"), text: $editorSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(separatorBorderColor, lineWidth: 1)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.amgiBackground)
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
                        return buildCardPreviewNote(from: currentNote)
                    }
                    if let sampleNote = try noteClient.search("mid:\(notetypeId)", 1).first {
                        return buildCardPreviewNote(from: sampleNote)
                    }
                    return makeEmptyCardPreviewNote(
                        notetypeId: notetypeId,
                        fieldCount: notetype.fields.count
                    )
                }.value
            }
        )
    }

    private var currentFieldNames: [String] {
        editorTab == .css ? [] : notetype.fields.map(\.name)
    }

    private var currentInsertableTokens: [String] {
        switch editorTab {
        case .front, .back, .preview:
            return ["(", ")", ".", "=", "#", "<br>", "{{FrontSide}}"]
        case .css:
            return ["{", "}", ":", ";", ".", "#"]
        }
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
            originalNotetype = notetype
            normalizeTemplateIndex(preferred: initialTemplateIndex)
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
            try backend.callVoid(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.updateNotetype,
                request: notetype
            )
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
