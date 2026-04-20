import SwiftUI
import AnkiKit
import AnkiClients
import AnkiBackend
import AnkiProto
import Dependencies
import SwiftProtobuf

struct NoteEditorView: View {
    let note: NoteRecord
    let onSave: () -> Void

    @Dependency(\.noteClient) var noteClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.ankiBackend) var backend

    @State private var fieldValues: [String] = []
    @State private var fieldNames: [String] = []
    @State private var tags: String = ""
    @State private var availableTags: [String] = []
    @State private var hasLoadedAvailableTags = false
    @State private var isLoadingAvailableTags = false
    @State private var hasLoadedOriginalState = false
    @State private var isSaving = false
    @State private var originalFieldValues: [String] = []
    @State private var originalTags: String = ""
    @State private var showDiscardChangesConfirmation = false
    @State private var showTagPicker = false
    @State private var showPreviewSheet = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var notetype: Anki_Notetypes_Notetype?
    @Environment(\.dismiss) private var dismiss

    private var trimmedTags: String {
        tags.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedChanges: Bool {
        hasLoadedOriginalState
            && (fieldValues != originalFieldValues || trimmedTags != originalTags)
    }

    var body: some View {
        Form {
            Section(L("add_note_section_fields")) {
                VStack(spacing: 0) {
                    ForEach(Array(fieldNames.enumerated()), id: \.offset) { index, name in
                        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                            HStack(spacing: AmgiSpacing.sm) {
                                Text(name)
                                    .amgiFont(.caption)
                                    .foregroundStyle(Color.amgiTextSecondary)
                                Spacer()
                                if shouldShowAudioButton(fieldName: name, index: index) {
                                    Button {
                                        previewAudio(at: index)
                                    } label: {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(AmgiFont.caption.font)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.amgiAccent)
                                    .disabled(MediaAudioPreview.firstAudioFileName(in: fieldValue(at: index)) == nil)
                                }
                            }
                            RichNoteFieldEditor(htmlText: fieldBinding(for: index))
                                .frame(minHeight: 32)
                        }
                        .padding(.vertical, AmgiSpacing.sm)

                        if index < fieldNames.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, AmgiSpacing.md)
                .padding(.vertical, AmgiSpacing.xs)
                .background(Color.amgiSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section(L("add_note_section_tags")) {
                TextField(L("add_note_tags_placeholder"), text: $tags)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button(action: { showTagPicker = true }) {
                    Label(L("note_editor_select_tags"), systemImage: "ellipsis")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Color.amgiAccent)
                .disabled(isLoadingAvailableTags)
                
                if !tags.isEmpty {
                    HStack {
                        Text(L("note_editor_current_tags"))
                            .amgiFont(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                        Spacer()
                        ForEach(tags.split(separator: " ").map(String.init), id: \.self) { tag in
                            Text(tag)
                                .amgiFont(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.amgiAccent.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.amgiAccent)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("note_editor_title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L("common_cancel")) {
                    attemptDismiss()
                }
                .amgiToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("card_template_preview_btn")) {
                    showPreviewSheet = true
                }
                .amgiToolbarTextButton(tone: .neutral)
                .disabled((notetype?.templates.isEmpty ?? true) || isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("note_editor_save")) {
                    Task { await save() }
                }
                .amgiToolbarTextButton()
                .disabled(isSaving)
            }
        }
        .sheet(isPresented: $showTagPicker) {
            tagPickerSheet
        }
        .sheet(isPresented: $showPreviewSheet) {
            if let notetype {
                UncommittedCardPreviewSheet(
                    title: L("note_editor_preview_title"),
                    emptyMessage: L("note_editor_preview_empty_card"),
                    notetype: notetype,
                    allowsTemplateSelection: true,
                    loadPreviewNote: {
                        buildCardPreviewNote(
                            from: note,
                            fieldValues: fieldValues,
                            tags: tags
                        )
                    }
                )
            }
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok")) { }
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
        .task {
            await loadNote()
        }
    }

    private var tagPickerSheet: some View {
        NavigationStack {
            Group {
                if isLoadingAvailableTags && availableTags.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(availableTags.sorted(), id: \.self) { tag in
                            Button(action: { addTag(tag) }) {
                                HStack {
                                    Text(tag)
                                    if tags.contains(tag) {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.amgiAccent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("note_editor_available_tags"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await ensureAvailableTagsLoaded()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { showTagPicker = false }
                        .amgiToolbarTextButton()
                }
            }
        }
    }

    private func fieldBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < fieldValues.count ? fieldValues[index] : "" },
            set: { newValue in
                if index < fieldValues.count { fieldValues[index] = newValue }
            }
        )
    }

    private func fieldValue(at index: Int) -> String {
        guard index < fieldValues.count else { return "" }
        return fieldValues[index]
    }

    private func shouldShowAudioButton(fieldName: String, index: Int) -> Bool {
        MediaAudioPreview.isLikelyAudioFieldName(fieldName)
            || MediaAudioPreview.firstAudioFileName(in: fieldValue(at: index)) != nil
    }

    @MainActor
    private func previewAudio(at index: Int) {
        do {
            try MediaAudioPreview.playFirstAudioTag(in: fieldValue(at: index))
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func loadNote() async {
        let backend = self.backend
        let mid = note.mid
        let noteData = note

        // Fetch notetype field names off the main thread
        let fetchedNotetype: Anki_Notetypes_Notetype? = await Task.detached(priority: .userInitiated) {
            var ntReq = Anki_Notetypes_NotetypeId()
            ntReq.ntid = mid
            return try? backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: ntReq
            ) as Anki_Notetypes_Notetype
        }.value

        if let fetchedNotetype {
            notetype = fetchedNotetype
            fieldNames = fetchedNotetype.fields.map(\.name)
        } else {
            errorMessage = L("common_failed_load_notetype")
            showError = true
        }

        fieldValues = noteData.flds
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)
        while fieldValues.count < fieldNames.count { fieldValues.append("") }
        tags = noteData.tags.trimmingCharacters(in: .whitespaces)
        originalFieldValues = fieldValues
        originalTags = trimmedTags
        hasLoadedOriginalState = true
    }
    
    private func ensureAvailableTagsLoaded() async {
        guard !hasLoadedAvailableTags, !isLoadingAvailableTags else { return }
        isLoadingAvailableTags = true
        defer { isLoadingAvailableTags = false }

        do {
            availableTags = try tagClient.getAllTags()
            hasLoadedAvailableTags = true
        } catch {
            print("[NoteEditorView] Failed to load tags: \(error)")
        }
    }
    
    private func addTag(_ tag: String) {
        let tagSet = Set(tags.split(separator: " ").map(String.init))
        if !tagSet.contains(tag) {
            if tags.isEmpty {
                tags = tag
            } else {
                tags += " \(tag)"
            }
        }
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            showDiscardChangesConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save() async {
        isSaving = true
        let newFlds = fieldValues.joined(separator: "\u{1f}")
        let newSfld = fieldValues.first ?? ""
        let newCsum = Int64(newSfld.hashValue & 0xFFFFFFFF)

        var updatedNote = note
        updatedNote.flds = newFlds
        updatedNote.sfld = newSfld
        updatedNote.csum = newCsum
        updatedNote.tags = " \(tags.trimmingCharacters(in: .whitespaces)) "

        do {
            try noteClient.save(updatedNote)
            onSave()
            dismiss()
        } catch {
            errorMessage = L("note_editor_error_save", error.localizedDescription)
            showError = true
        }
        isSaving = false
    }
}
