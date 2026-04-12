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
    @State private var selectedTemplate: Anki_Notetypes_Notetype = .init()
    @State private var hasSelectedTemplate = false
    @State private var selectedTemplateIndex = 0
    @State private var previewSide: TemplatePreviewSide = .front
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var isSaving = false
    @State private var showPreview = false

    private var filteredEntries: [Anki_Notetypes_NotetypeNameId] {
        filterDeckTemplateEntries(entries, searchText: searchText)
    }

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle(L("deck_template_nav_title"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: L("deck_template_search"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("common_done")) { dismiss() }
                    }
                }
                .sheet(isPresented: $showPreview) {
                    previewSheet
                }
                .alert(L("deck_template_save_failed"), isPresented: $showSaveError) {
                    Button(L("common_ok")) {}
                } message: {
                    Text(saveError ?? L("common_unknown_error"))
                }
                .task {
                    await loadTemplates()
                }
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
                Task { await openPreview(for: entry.id) }
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
        }
        .listStyle(.plain)
    }

    private var previewSheet: some View {
        NavigationStack {
            previewContent
                .navigationTitle(L("deck_template_preview_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if isSaving {
                            ProgressView()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("btn_save")) {
                            Task { await saveTemplate() }
                        }
                        .disabled(!hasSelectedTemplate || isLoadingPreview || isSaving)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("common_done")) { showPreview = false }
                    }
                }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if isLoadingPreview {
            ProgressView()
        } else if let previewError {
            ContentUnavailableView(
                L("deck_template_error_title"),
                systemImage: "exclamationmark.triangle",
                description: Text(previewError)
            )
        } else if hasSelectedTemplate {
            previewList(for: selectedTemplate)
        }
    }

    private func previewList(for notetype: Anki_Notetypes_Notetype) -> some View {
        Form {
            Section(L("deck_template_preview_basic")) {
                row(L("card_info_template"), notetype.name)
                row("ID", "\(notetype.id)")
            }
            Section(L("deck_template_preview_counts")) {
                row(L("deck_template_preview_fields"), "\(notetype.fields.count)")
                row(L("deck_template_preview_cards"), "\(notetype.templates.count)")
            }

            if !notetype.templates.isEmpty {
                Section(L("deck_template_preview_template_names")) {
                    Picker(L("deck_template_select_template"), selection: $selectedTemplateIndex) {
                        ForEach(Array(notetype.templates.enumerated()), id: \.offset) { idx, template in
                            Text(template.name).tag(idx)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            if !notetype.fields.isEmpty {
                Section(L("deck_template_preview_field_names")) {
                    ForEach(Array(notetype.fields.enumerated()), id: \.offset) { _, field in
                        row(field.name, sampleValue(for: field.name))
                    }
                }
            }

            Section(L("deck_template_edit_template")) {
                TextField(
                    L("deck_template_edit_template_name"),
                    text: templateNameBinding
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("deck_template_edit_qformat"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: qFormatBinding)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("deck_template_edit_aformat"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: aFormatBinding)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                }
            }

            Section(L("deck_template_edit_css")) {
                TextEditor(text: cssBinding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
            }

            Section(L("deck_template_preview_rendered")) {
                Picker(L("deck_template_preview_side"), selection: $previewSide) {
                    ForEach(TemplatePreviewSide.allCases, id: \.self) { side in
                        Text(side.label).tag(side)
                    }
                }
                .pickerStyle(.segmented)

                CardWebView(
                    html: renderedTemplateHTML(side: previewSide),
                    autoplayEnabled: false,
                    isAnswerSide: previewSide == .back,
                    cardOrdinal: UInt32(selectedTemplateIndex),
                    openLinksExternally: false,
                    contentAlignment: .top
                )
                .frame(height: 320)
            }
        }
        .onChange(of: selectedTemplate.templates.count) {
            normalizeTemplateIndex()
        }
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

    private func openPreview(for notetypeId: Int64) async {
        isLoadingPreview = true
        hasSelectedTemplate = false
        selectedTemplate = .init()
        selectedTemplateIndex = 0
        previewError = nil
        showPreview = true

        defer { isLoadingPreview = false }

        do {
            var req = Anki_Notetypes_NotetypeId()
            req.ntid = notetypeId
            let notetype: Anki_Notetypes_Notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: req
            )
            selectedTemplate = notetype
            hasSelectedTemplate = true
            normalizeTemplateIndex()
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func saveTemplate() async {
        guard hasSelectedTemplate else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try backend.callVoid(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.updateNotetype,
                request: selectedTemplate
            )

            // Keep list entry names in sync after renaming a notetype.
            await loadTemplates()
            previewError = nil
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }

    private var templateNameBinding: Binding<String> {
        Binding(
            get: {
                guard selectedTemplate.templates.indices.contains(selectedTemplateIndex) else { return "" }
                return selectedTemplate.templates[selectedTemplateIndex].name
            },
            set: { newValue in
                guard selectedTemplate.templates.indices.contains(selectedTemplateIndex) else { return }
                selectedTemplate.templates[selectedTemplateIndex].name = newValue
            }
        )
    }

    private var qFormatBinding: Binding<String> {
        Binding(
            get: {
                guard selectedTemplate.templates.indices.contains(selectedTemplateIndex) else { return "" }
                return selectedTemplate.templates[selectedTemplateIndex].config.qFormat
            },
            set: { newValue in
                guard selectedTemplate.templates.indices.contains(selectedTemplateIndex) else { return }
                var cfg = selectedTemplate.templates[selectedTemplateIndex].config
                cfg.qFormat = newValue
                selectedTemplate.templates[selectedTemplateIndex].config = cfg
            }
        )
    }

    private var aFormatBinding: Binding<String> {
        Binding(
            get: {
                guard selectedTemplate.templates.indices.contains(selectedTemplateIndex) else { return "" }
                return selectedTemplate.templates[selectedTemplateIndex].config.aFormat
            },
            set: { newValue in
                guard selectedTemplate.templates.indices.contains(selectedTemplateIndex) else { return }
                var cfg = selectedTemplate.templates[selectedTemplateIndex].config
                cfg.aFormat = newValue
                selectedTemplate.templates[selectedTemplateIndex].config = cfg
            }
        )
    }

    private var cssBinding: Binding<String> {
        Binding(
            get: { selectedTemplate.config.css },
            set: { newValue in
                var cfg = selectedTemplate.config
                cfg.css = newValue
                selectedTemplate.config = cfg
            }
        )
    }

    private func normalizeTemplateIndex() {
        if selectedTemplate.templates.isEmpty {
            selectedTemplateIndex = 0
            return
        }
        if selectedTemplateIndex >= selectedTemplate.templates.count {
            selectedTemplateIndex = selectedTemplate.templates.count - 1
        }
    }

    private func renderedTemplateHTML(side: TemplatePreviewSide) -> String {
        guard selectedTemplate.templates.indices.contains(selectedTemplateIndex) else {
            let message = L("deck_template_preview_no_template")
            return "<p>\(message)</p>"
        }

        let template = selectedTemplate.templates[selectedTemplateIndex]
        let frontRaw = template.config.qFormat
        let front = renderTemplate(frontRaw)

        let body: String
        switch side {
        case .front:
            body = front
        case .back:
            let merged = template.config.aFormat.replacingOccurrences(of: "{{FrontSide}}", with: front)
            body = renderTemplate(merged)
        }

        let css = selectedTemplate.config.css
        return "<style>\(css)</style>\(body)"
    }

    private func renderTemplate(_ source: String) -> String {
        var rendered = source

        for field in selectedTemplate.fields {
            let name = field.name
            let value = sampleValue(for: name)
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            if let regex = try? NSRegularExpression(pattern: "\\\\{\\\\{[^{}]*\(escapedName)[^{}]*\\\\}\\\\}") {
                let range = NSRange(rendered.startIndex..., in: rendered)
                rendered = regex.stringByReplacingMatches(in: rendered, range: range, withTemplate: value)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\\\{\\\\{[^{}]+\\\\}\\\\}") {
            let range = NSRange(rendered.startIndex..., in: rendered)
            rendered = regex.stringByReplacingMatches(in: rendered, range: range, withTemplate: "")
        }

        return rendered
    }

    private func sampleValue(for fieldName: String) -> String {
        L("deck_template_sample_value", fieldName)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
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
