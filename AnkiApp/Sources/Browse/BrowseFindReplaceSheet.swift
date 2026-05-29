import SwiftUI
import AnkiBackend
import AnkiProto
import AmgiTheme
import Dependencies

/// Sheet for batch find-and-replace in note fields or tags.
/// Mirrors the upstream `FindAndReplaceDialog` in Qt.
@MainActor
struct BrowseFindReplaceSheet: View {
    /// Selected note IDs; empty means operate on all notes.
    let noteIDs: [Int64]
    let onComplete: () -> Void

    @Dependency(\.ankiBackend) var backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var selectedFieldIndex = 0   // 0 = All Fields, 1 = Tags, 2+ = specific fields
    @State private var matchCase = false
    @State private var useRegex = false
    @State private var fieldNames: [String] = []
    @State private var isLoadingFields = true
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var successMessage: String?
    @State private var showSuccess = false

    private var allFieldOptions: [String] {
        [L("browse_find_replace_all_fields"), L("browse_find_replace_tags")] + fieldNames
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("browse_find_replace_search")) {
                    TextField(L("browse_find_replace_search"), text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section(L("browse_find_replace_replace_with")) {
                    TextField(L("browse_find_replace_replace_with"), text: $replaceText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section(L("browse_find_replace_field")) {
                    if isLoadingFields {
                        HStack {
                            ProgressView()
                            Text(L("common_loading"))
                                .foregroundStyle(palette.textSecondary)
                        }
                    } else {
                        Picker(L("browse_find_replace_field"), selection: $selectedFieldIndex) {
                            ForEach(allFieldOptions.indices, id: \.self) { idx in
                                Text(allFieldOptions[idx]).tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Toggle(L("browse_find_replace_match_case"), isOn: $matchCase)
                    Toggle(L("browse_find_replace_regex"), isOn: $useRegex)
                }

                if !noteIDs.isEmpty {
                    Section {
                        Label(
                            String(format: L("browse_batch_processed"), noteIDs.count, noteIDs.count),
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle(L("browse_find_replace_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("browse_find_replace_action")) {
                        Task { await applyFindReplace() }
                    }
                    .fontWeight(.semibold)
                    .disabled(searchText.isEmpty || isApplying || isLoadingFields)
                }
            }
            .task { await loadFieldNames() }
            .alert(L("common_error"), isPresented: $showError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .alert(L("browse_find_replace_title"), isPresented: $showSuccess) {
                Button(L("common_ok")) {
                    onComplete()
                    dismiss()
                }
            } message: {
                Text(successMessage ?? "")
            }
        }
    }

    private func loadFieldNames() async {
        isLoadingFields = true
        defer { isLoadingFields = false }
        guard !noteIDs.isEmpty else {
            // No note filter: we can't fetch field names; just leave empty (All Fields + Tags only)
            return
        }
        do {
            var req = Anki_Notes_FieldNamesForNotesRequest()
            req.nids = noteIDs
            let resp: Anki_Notes_FieldNamesForNotesResponse = try backend.invoke(
                service: AnkiBackend.Service.notes,
                method: AnkiBackend.NotesMethod.fieldNamesForNotes,
                request: req
            )
            fieldNames = resp.fields
        } catch {
            fieldNames = []
        }
    }

    private func applyFindReplace() async {
        isApplying = true
        defer { isApplying = false }

        do {
            let count: UInt32
            if selectedFieldIndex == 1 {
                // Tags mode
                var req = Anki_Tags_FindAndReplaceTagRequest()
                req.noteIds = noteIDs
                req.search = searchText
                req.replacement = replaceText
                req.regex = useRegex
                req.matchCase = matchCase
                let resp: Anki_Collection_OpChangesWithCount = try backend.invoke(
                    service: AnkiBackend.Service.tags,
                    method: AnkiBackend.TagsMethod.findAndReplaceTag,
                    request: req
                )
                count = resp.count
            } else {
                // Field mode
                var req = Anki_Search_FindAndReplaceRequest()
                req.nids = noteIDs
                req.search = searchText
                req.replacement = replaceText
                req.regex = useRegex
                req.matchCase = matchCase
                if selectedFieldIndex >= 2 {
                    req.fieldName = fieldNames[selectedFieldIndex - 2]
                }
                // empty fieldName means all fields
                let resp: Anki_Collection_OpChangesWithCount = try backend.invoke(
                    service: AnkiBackend.Service.search,
                    method: AnkiBackend.SearchMethod.findAndReplace,
                    request: req
                )
                count = resp.count
            }
            successMessage = String(format: L("browse_find_replace_success"), count)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
