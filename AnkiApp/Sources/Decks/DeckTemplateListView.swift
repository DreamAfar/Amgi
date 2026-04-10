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
    @State private var selectedTemplate: Anki_Notetypes_Notetype?
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var showPreview = false

    private var filteredEntries: [Anki_Notetypes_NotetypeNameId] {
        filterDeckTemplateEntries(entries, searchText: searchText)
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
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        L("deck_template_empty_title"),
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(L("deck_template_empty_desc"))
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredEntries, id: \.id) { entry in
                        Button {
                            Task { await openPreview(for: entry.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up")
                                    .foregroundStyle(.accent)
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
            }
            .navigationTitle(L("deck_template_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L("deck_template_search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showPreview) {
                NavigationStack {
                    Group {
                        if isLoadingPreview {
                            ProgressView()
                        } else if let previewError {
                            ContentUnavailableView(
                                L("deck_template_error_title"),
                                systemImage: "exclamationmark.triangle",
                                description: Text(previewError)
                            )
                        } else if let selectedTemplate {
                            List {
                                Section(L("deck_template_preview_basic")) {
                                    row(L("card_info_template"), selectedTemplate.name)
                                    row("ID", "\(selectedTemplate.id)")
                                }
                                Section(L("deck_template_preview_counts")) {
                                    row(L("deck_template_preview_fields"), "\(selectedTemplate.fields.count)")
                                    row(L("deck_template_preview_cards"), "\(selectedTemplate.templates.count)")
                                }

                                if !selectedTemplate.fields.isEmpty {
                                    Section(L("deck_template_preview_field_names")) {
                                        ForEach(Array(selectedTemplate.fields.enumerated()), id: \.offset) { _, field in
                                            Text(field.name)
                                        }
                                    }
                                }

                                if !selectedTemplate.templates.isEmpty {
                                    Section(L("deck_template_preview_template_names")) {
                                        ForEach(Array(selectedTemplate.templates.enumerated()), id: \.offset) { _, template in
                                            Text(template.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(L("deck_template_preview_title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L("common_done")) { showPreview = false }
                        }
                    }
                }
            }
            .task {
                await loadTemplates()
            }
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
        selectedTemplate = nil
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
        } catch {
            previewError = error.localizedDescription
        }
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
