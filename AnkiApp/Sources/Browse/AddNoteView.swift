import SwiftUI
import AnkiKit
import AnkiClients
import AnkiBackend
import AnkiProto
import Dependencies
import SwiftProtobuf

struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.deckClient) var deckClient

    @State private var decks: [DeckInfo] = []
    @State private var notetypeNames: [(Int64, String)] = []
    @State private var selectedDeckId: Int64
    @State private var selectedNotetypeId: Int64 = 0
    @State private var fieldNames: [String] = []
    @State private var fieldValues: [String] = []
    @State private var tags: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var previewErrorMessage: String?
    @State private var showPreviewError = false
    @State private var showPreviewSheet = false
    @State private var previewNotetype: Anki_Notetypes_Notetype?
    @State private var shouldApplyDraftOnNextFieldLoad = false

    let onSave: () -> Void
    let preselectedDeckId: Int64?
    let draft: AddNoteDraft?

    init(
        onSave: @escaping () -> Void,
        preselectedDeckId: Int64? = nil,
        draft: AddNoteDraft? = nil
    ) {
        self.onSave = onSave
        self.preselectedDeckId = preselectedDeckId
        self.draft = draft
        _selectedDeckId = State(initialValue: draft?.deckID ?? preselectedDeckId ?? 1)
        _tags = State(initialValue: draft?.tags.joined(separator: " ") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("add_note_section_deck")) {
                    Picker(L("add_note_section_deck"), selection: $selectedDeckId) {
                        ForEach(decks) { deck in
                            Text(deck.name).tag(deck.id)
                        }
                    }
                }

                Section(L("add_note_section_type")) {
                    Picker(L("add_note_type_label"), selection: $selectedNotetypeId) {
                        ForEach(notetypeNames, id: \.0) { id, name in
                            Text(name).tag(id)
                        }
                    }
                    .onChange(of: selectedNotetypeId) {
                        loadFields(applyingDraft: consumePendingDraftApplication())
                    }
                }

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
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .amgiStatusText(.danger, font: .caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(L("add_note_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_cancel")) { dismiss() }
                        .amgiToolbarTextButton(tone: .neutral)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("card_template_preview_btn")) {
                        showPreview()
                    }
                    .amgiToolbarTextButton(tone: .neutral)
                    .disabled(selectedNotetypeId == 0 || fieldNames.isEmpty || isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common_add")) {
                        Task { await save() }
                    }
                    .amgiToolbarTextButton()
                    .disabled(isSaving || fieldValues.allSatisfy(\.isEmpty))
                }
            }
            .task {
                await loadData()
            }
            .alert(L("common_error"), isPresented: $showPreviewError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(previewErrorMessage ?? L("common_unknown_error"))
            }
            .sheet(isPresented: $showPreviewSheet) {
                if let previewNotetype {
                    UncommittedCardPreviewSheet(
                        title: L("note_editor_preview_title"),
                        emptyMessage: L("note_editor_preview_empty_card"),
                        notetype: previewNotetype,
                        allowsTemplateSelection: true,
                        loadPreviewNote: {
                            buildPreviewNote()
                        }
                    )
                }
            }
        }
    }

    private func fieldBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < fieldValues.count ? fieldValues[index] : "" },
            set: { newValue in
                if index < fieldValues.count {
                    fieldValues[index] = RichNoteFieldEditor.normalizedStoredHTML(newValue)
                }
            }
        )
    }

    private func loadData() async {
        decks = (try? deckClient.fetchAll()) ?? []

        let preferredDeckID = draft?.deckID ?? preselectedDeckId
        if let preferredDeckID, decks.contains(where: { $0.id == preferredDeckID }) {
            selectedDeckId = preferredDeckID
        } else if let first = decks.first {
            selectedDeckId = first.id
        }

        do {
            notetypeNames = try loadStandardNotetypeEntries(backend: backend)
            if let preferredNotetypeID = resolvedPreferredNotetypeID() {
                scheduleFieldLoad(for: preferredNotetypeID, applyingDraft: draft != nil)
            } else if let first = notetypeNames.first {
                scheduleFieldLoad(for: first.0, applyingDraft: draft != nil)
            } else {
                selectedNotetypeId = 0
                fieldNames = []
                fieldValues = []
            }
        } catch {
            print("[AddNote] Error loading notetypes: \(error)")
        }
    }

    private func loadFields(applyingDraft: Bool) {
        guard selectedNotetypeId != 0 else { return }
        do {
            let notetype = try fetchNotetype(backend: backend, id: selectedNotetypeId)
            fieldNames = notetype.fields.map(\.name)
            if applyingDraft, let draft {
                fieldValues = fieldNames.map { fieldName in
                    RichNoteFieldEditor.normalizedStoredHTML(draft.fieldValues[fieldName] ?? "")
                }
            } else {
                fieldValues = Array(repeating: "", count: fieldNames.count)
            }
        } catch {
            print("[AddNote] Error loading fields: \(error)")
        }
    }

    private func resolvedPreferredNotetypeID() -> Int64? {
        if let draftNotetypeID = draft?.notetypeID,
           notetypeNames.contains(where: { $0.0 == draftNotetypeID }) {
            return draftNotetypeID
        }
        return nil
    }

    private func scheduleFieldLoad(for notetypeID: Int64, applyingDraft: Bool) {
        shouldApplyDraftOnNextFieldLoad = applyingDraft
        if selectedNotetypeId == notetypeID {
            loadFields(applyingDraft: consumePendingDraftApplication())
        } else {
            selectedNotetypeId = notetypeID
        }
    }

    private func consumePendingDraftApplication() -> Bool {
        let shouldApplyDraft = shouldApplyDraftOnNextFieldLoad
        shouldApplyDraftOnNextFieldLoad = false
        return shouldApplyDraft
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
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    @MainActor
    private func showPreview() {
        guard selectedNotetypeId != 0 else { return }
        do {
            previewNotetype = try fetchNotetype(backend: backend, id: selectedNotetypeId)
            showPreviewSheet = true
        } catch {
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    private func buildPreviewNote() -> Anki_Notes_Note {
        var preview = makeEmptyCardPreviewNote(notetypeId: selectedNotetypeId, fieldCount: fieldNames.count)
        preview.fields = fieldValues.map(RichNoteFieldEditor.normalizedStoredHTML)
        preview.tags = tags.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return preview
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        do {
            // 1. Create blank note for the notetype
            var ntReq = Anki_Notetypes_NotetypeId()
            ntReq.ntid = selectedNotetypeId
            var note: Anki_Notes_Note = try backend.invoke(
                service: AnkiBackend.Service.notes,
                method: AnkiBackend.NotesMethod.newNote,
                request: ntReq
            )

            // 2. Fill in fields and tags
            note.fields = fieldValues.map(RichNoteFieldEditor.normalizedStoredHTML)
            note.tags = tags.split(separator: " ").map(String.init)

            // 3. Add the note to the deck
            var addReq = Anki_Notes_AddNoteRequest()
            addReq.note = note
            addReq.deckID = selectedDeckId

            let _: Anki_Collection_OpChangesWithId = try backend.invoke(
                service: AnkiBackend.Service.notes,
                method: AnkiBackend.NotesMethod.addNote,
                request: addReq
            )

            onSave()
            dismiss()
        } catch {
            errorMessage = L("add_note_error_save", error.localizedDescription)
        }

        isSaving = false
    }
}
