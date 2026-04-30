import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
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
    @Dependency(\.mediaClient) var mediaClient

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
    @State private var previewContext: AddNotePreviewContext?
    @State private var shouldApplyDraftOnNextFieldLoad = false
    @State private var pendingMediaFieldIndex: Int?
    @State private var showMediaImportOptions = false
    @State private var showPhotoPicker = false
    @State private var showMediaFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?

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
                                    Button {
                                        beginMediaImport(for: index)
                                    } label: {
                                        Image(systemName: "paperclip")
                                            .font(AmgiFont.caption.font)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.amgiAccent)
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

                                if shouldShowFieldPreview(at: index) {
                                    NoteFieldHTMLPreview(html: fieldValue(at: index))
                                        .frame(height: fieldPreviewHeight(at: index))
                                        .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.amgiBorder.opacity(0.24), lineWidth: 1)
                                        }
                                }

                                RichNoteFieldEditor(
                                    htmlText: fieldBinding(for: index),
                                    preservesSourceHTML: shouldPreserveSourceHTML(at: index)
                                )
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
            .confirmationDialog(
                L("note_editor_media_import_title"),
                isPresented: $showMediaImportOptions,
                titleVisibility: .visible
            ) {
                Button(L("note_editor_media_import_photo")) {
                    showPhotoPicker = true
                }
                Button(L("note_editor_media_import_file")) {
                    showMediaFileImporter = true
                }
                Button(L("common_cancel"), role: .cancel) {
                    pendingMediaFieldIndex = nil
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images,
                preferredItemEncoding: .automatic,
                photoLibrary: .shared()
            )
            .fileImporter(
                isPresented: $showMediaFileImporter,
                allowedContentTypes: NoteFieldMediaSupport.importableTypes
            ) { result in
                handleImportedFile(result)
            }
            .onChange(of: selectedPhotoItem) {
                Task { await importSelectedPhoto() }
            }
            .sheet(item: $previewContext) { context in
                UncommittedCardPreviewSheet(
                    title: L("note_editor_preview_title"),
                    emptyMessage: L("note_editor_preview_empty_card"),
                    notetype: context.notetype,
                    allowsTemplateSelection: true,
                    loadPreviewNote: {
                        context.note
                    }
                )
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

    private func shouldShowFieldPreview(at index: Int) -> Bool {
        containsEmbeddedMedia(fieldValue(at: index))
    }

    private func shouldPreserveSourceHTML(at index: Int) -> Bool {
        containsEmbeddedMedia(fieldValue(at: index))
    }

    private func fieldPreviewHeight(at index: Int) -> CGFloat {
        let value = fieldValue(at: index).lowercased()
        if value.contains("<img") || value.contains("<svg") {
            return 220
        }
        return 96
    }

    private func containsEmbeddedMedia(_ value: String) -> Bool {
        let lowercasedValue = value.lowercased()
        return lowercasedValue.contains("<img")
            || lowercasedValue.contains("<svg")
            || lowercasedValue.contains("<video")
            || lowercasedValue.contains("<audio")
    }

    private func shouldShowAudioButton(fieldName: String, index: Int) -> Bool {
        MediaAudioPreview.isLikelyAudioFieldName(fieldName)
            || MediaAudioPreview.firstAudioFileName(in: fieldValue(at: index)) != nil
    }

    private func beginMediaImport(for index: Int) {
        pendingMediaFieldIndex = index
        showMediaImportOptions = true
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
    private func importSelectedPhoto() async {
        guard let selectedPhotoItem else { return }
        defer {
            self.selectedPhotoItem = nil
            pendingMediaFieldIndex = nil
        }

        do {
            guard let data = try await selectedPhotoItem.loadTransferable(type: Data.self) else {
                throw MediaImportError.loadFailed
            }
            let contentType = selectedPhotoItem.supportedContentTypes.first
            let filename = NoteFieldMediaSupport.suggestedFilename(
                contentType: contentType,
                fallbackPrefix: "image"
            )
            try insertImportedMedia(
                data: data,
                filename: filename,
                contentType: contentType
            )
        } catch {
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    private func handleImportedFile(_ result: Result<URL, Error>) {
        defer { pendingMediaFieldIndex = nil }

        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)
            let filename = NoteFieldMediaSupport.suggestedFilename(
                sourceURL: url,
                contentType: contentType,
                fallbackPrefix: "media"
            )
            try insertImportedMedia(
                data: data,
                filename: filename,
                contentType: contentType
            )
        } catch {
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    private func insertImportedMedia(
        data: Data,
        filename: String,
        contentType: UTType?
    ) throws {
        guard let index = pendingMediaFieldIndex, fieldValues.indices.contains(index) else {
            throw MediaImportError.noTargetField
        }

        let storedFilename = try mediaClient.save(data, filename)
        let markup = NoteFieldMediaSupport.markup(for: storedFilename, contentType: contentType)
        let separator = NoteFieldMediaSupport.separator(for: fieldValues[index], markup: markup)
        fieldValues[index].append(separator + markup)
    }

    @MainActor
    private func showPreview() {
        guard selectedNotetypeId != 0 else { return }
        do {
            let notetype = try fetchNotetype(backend: backend, id: selectedNotetypeId)
            previewContext = AddNotePreviewContext(
                notetype: notetype,
                note: buildPreviewNote(notetype: notetype)
            )
        } catch {
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    private func buildPreviewNote(notetype: Anki_Notetypes_Notetype) -> Anki_Notes_Note {
        NoteProtoFactory.makeUncommittedNote(
            notetypeId: selectedNotetypeId,
            fieldValues: fieldValues.map(RichNoteFieldEditor.normalizedStoredHTML),
            tags: tags,
            fieldCount: notetype.fields.count
        )
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        do {
            // 1. Create blank note for the notetype
            var ntReq = Anki_Notetypes_NotetypeId()
            ntReq.ntid = selectedNotetypeId
            let blankNote: Anki_Notes_Note = try backend.invoke(
                service: AnkiBackend.Service.notes,
                method: AnkiBackend.NotesMethod.newNote,
                request: ntReq
            )
            let note = NoteProtoFactory.makeUncommittedNote(
                baseNote: blankNote,
                notetypeId: selectedNotetypeId,
                fieldValues: fieldValues.map(RichNoteFieldEditor.normalizedStoredHTML),
                tags: tags,
                fieldCount: fieldNames.count
            )

            // 2. Add the note to the deck
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

private struct AddNotePreviewContext: Identifiable {
    let id = UUID()
    let notetype: Anki_Notetypes_Notetype
    let note: Anki_Notes_Note
}
