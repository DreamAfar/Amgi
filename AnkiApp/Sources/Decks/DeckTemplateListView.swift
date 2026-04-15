import SwiftUI
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
            .navigationTitle(L("deck_template_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L("deck_template_search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
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
            ContentUnavailableView(
                L("deck_template_error_title"),
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
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
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.body)
                        Text("ID: \(entry.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
                .tint(.blue)
            }
        }
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let notetypeId: Int64
    let initialTemplateIndex: Int
    let mode: TemplateEditorMode
    var onSaved: (@Sendable () async -> Void)? = nil

    @AppStorage("codeEditor_fontSize") private var codeEditorFontSize: Double = 14.0

    @State private var notetype: Anki_Notetypes_Notetype = .init()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSaveError = false
    @State private var selectedTemplateIndex = 0
    @State private var previewSide: TemplatePreviewSide = .front
    @State private var editorTab: TemplateEditorTab = .front
    @State private var showFieldManager = false
    @State private var showPreviewSheet = false
    @State private var editorSearchText = ""

    private var separatorBorderColor: Color {
        // 浅色主题需要更高的不透明度以获得足够的对比度
        colorScheme == .light
            ? Color(.separator).opacity(0.6)
            : Color(.separator).opacity(0.35)
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
                    ContentUnavailableView(
                        L("deck_template_error_title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    editorContent
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(mode.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("card_template_fields_short")) {
                        showFieldManager = true
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L("btn_save")) {
                            Task { await saveTemplate() }
                        }
                        .disabled(!notetype.templates.indices.contains(selectedTemplateIndex))
                    }
                }
            }
            .alert(L("deck_template_save_failed"), isPresented: $showSaveError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
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
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            
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
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    } else {
                        Text(currentTemplateName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
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
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(separatorBorderColor, lineWidth: 1)
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
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(separatorBorderColor, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("card_template_search_title"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(L("card_template_search_placeholder"), text: $editorSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(separatorBorderColor, lineWidth: 1)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var previewSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L("deck_template_preview_side"), selection: $previewSide) {
                    ForEach(TemplatePreviewSide.allCases, id: \.self) { side in
                        Text(side.label).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .padding()

                CardWebView(
                    html: renderedTemplateHTML(side: previewSide),
                    autoplayEnabled: false,
                    isAnswerSide: previewSide == .back,
                    cardOrdinal: UInt32(selectedTemplateIndex),
                    openLinksExternally: false,
                    contentAlignment: .top
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .stroke(separatorBorderColor, lineWidth: 1)
                }
            }
            .background(Color(.secondarySystemBackground))
            .navigationTitle(L("deck_template_preview_rendered"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { showPreviewSheet = false }
                }
            }
        }
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
            normalizeTemplateIndex(preferred: initialTemplateIndex)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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

    private func renderedTemplateHTML(side: TemplatePreviewSide) -> String {
        guard notetype.templates.indices.contains(selectedTemplateIndex) else {
            return "<p>\(L("deck_template_preview_no_template"))</p>"
        }

        let template = notetype.templates[selectedTemplateIndex]
        let front = renderTemplate(template.config.qFormat)

        let body: String
        switch side {
        case .front:
            body = front
        case .back:
            let merged = template.config.aFormat.replacingOccurrences(of: "{{FrontSide}}", with: front)
            body = renderTemplate(merged)
        }

        return "<style>\(notetype.config.css)</style>\(body)"
    }

    private func renderTemplate(_ source: String) -> String {
        var rendered = source

        for field in notetype.fields {
            let name = field.name
            let value = name
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            if let regex = try? NSRegularExpression(pattern: "\\{\\{[^{}]*\(escapedName)[^{}]*\\}\\}") {
                let range = NSRange(rendered.startIndex..., in: rendered)
                rendered = regex.stringByReplacingMatches(in: rendered, range: range, withTemplate: value)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\{\\{[^{}]+\\}\\}") {
            let range = NSRange(rendered.startIndex..., in: rendered)
            rendered = regex.stringByReplacingMatches(in: rendered, range: range, withTemplate: "")
        }

        return rendered
    }
}

private enum TemplatePreviewSide: CaseIterable {
    case front
    case back

    var label: String {
        switch self {
        case .front: return L("deck_template_preview_front")
        case .back: return L("deck_template_preview_back")
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
