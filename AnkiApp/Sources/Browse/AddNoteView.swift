import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import AnkiKit
import AnkiClients
import AnkiBackend
import AnkiProto
import Dependencies
import SwiftProtobuf

struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.mediaClient) var mediaClient
    @AppStorage("amgi.add_note.session") private var persistedSessionData = ""

    @State private var decks: [DeckInfo] = []
    @State private var notetypeNames: [(Int64, String)] = []
    @State private var selectedDeckId: Int64
    @State private var selectedNotetypeId: Int64 = 0
    @State private var fieldNames: [String] = []
    @State private var fieldValues: [String] = []
    @State private var fieldSourceModes: [Bool] = []
    @State private var tags: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var previewErrorMessage: String?
    @State private var showPreviewError = false
    @State private var previewContext: AddNotePreviewContext?
    @State private var hasLoadedInitialData = false
    @State private var isRestoringPersistedSession = false
    @State private var restoredSession: PersistedAddNoteSession?
    @State private var shouldApplyDraftOnNextFieldLoad = false
    @State private var shouldSkipNextNotetypeFieldReload = false
    @State private var pendingMediaFieldIndex: Int?
    @State private var showPhotoPicker = false
    @State private var showCameraPicker = false
    @State private var showMediaFileImporter = false
    @State private var showAudioRecorder = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageOptimizationRequest: NoteImageOptimizationRequest?

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

    private var fieldEditorActionStates: [NoteFieldsPageEditorActionState] {
        fieldNames.indices.map { index in
            let fieldName = fieldNames[index]
            let value = fieldValue(at: index)
            return NoteFieldsPageEditorActionState(
                showsAudioButton: MediaAudioPreview.isLikelyAudioFieldName(fieldName)
                    || MediaAudioPreview.firstAudioFileName(in: value) != nil,
                hasAudio: MediaAudioPreview.firstAudioFileName(in: value) != nil,
                hasEditableImage: NoteFieldMediaSupport.firstImageFilename(in: value) != nil,
                sourcePreviewHeight: sourcePreviewHeight(for: value)
            )
        }
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
                        if shouldSkipNextNotetypeFieldReload {
                            shouldSkipNextNotetypeFieldReload = false
                            persistSession()
                            return
                        }
                        loadFields(applyingDraft: consumePendingDraftApplication())
                    }
                }

                Section(L("add_note_section_fields")) {
                    VStack(spacing: 0) {
                        NoteFieldsPageEditor(
                            fieldNames: fieldNames,
                            fieldValues: $fieldValues,
                            fieldSourceModes: $fieldSourceModes,
                            actionStates: fieldEditorActionStates,
                            onDraftExport: { persistSession() },
                            onInsertPhoto: { beginMediaImport(for: $0, action: .photoLibrary) },
                            onInsertCameraPhoto: { beginMediaImport(for: $0, action: .camera) },
                            onInsertFile: { beginMediaImport(for: $0, action: .file) },
                            onRecordAudio: { beginMediaImport(for: $0, action: .audioRecording) },
                            onPreviewAudio: { previewAudio(at: $0) },
                            onEditImage: { beginExistingImageEdit(at: $0) }
                        )
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
            // The embedded fields editor is one tall WKWebView row; letting Form apply
            // keyboard avoidance makes it overshoot based on the row height instead of
            // the active caret position.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle(L("add_note_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_cancel")) {
                        clearPersistedSession()
                        dismiss()
                    }
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
                await loadDataIfNeeded()
            }
            .onChange(of: selectedDeckId) { persistSession() }
            .onChange(of: selectedNotetypeId) { persistSession() }
            .onChange(of: fieldNames) { persistSession() }
            .onChange(of: fieldValues) { persistSession() }
            .onChange(of: fieldSourceModes) { persistSession() }
            .onChange(of: tags) { persistSession() }
            .onChange(of: scenePhase) {
                guard scenePhase == .inactive || scenePhase == .background else { return }
                persistSession()
            }
            .alert(L("common_error"), isPresented: $showPreviewError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(previewErrorMessage ?? L("common_unknown_error"))
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
            .sheet(isPresented: $showCameraPicker) {
                CameraImagePicker(
                    onImageData: { data in
                        handleCameraImageData(data)
                    },
                    onCancel: {
                        showCameraPicker = false
                        pendingMediaFieldIndex = nil
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showAudioRecorder, onDismiss: { pendingMediaFieldIndex = nil }) {
                AudioRecordingSheet(
                    onCancel: {
                        showAudioRecorder = false
                    },
                    onFinishRecording: { url in
                        handleRecordedAudio(url)
                    }
                )
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
            .sheet(item: $imageOptimizationRequest) { request in
                NoteImageOptimizationSheet(request: request)
            }
        }
    }

    @MainActor
    private func loadDataIfNeeded() async {
        guard hasLoadedInitialData == false else { return }
        isRestoringPersistedSession = true
        restorePersistedSessionIfNeeded()
        await loadData()
        isRestoringPersistedSession = false
        hasLoadedInitialData = true
        persistSession()
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
            if let restoredSession {
                if let restoredDeckID = restoredSession.selectedDeckId,
                   decks.contains(where: { $0.id == restoredDeckID }) {
                    selectedDeckId = restoredDeckID
                }
                if let restoredNotetypeID = restoredSession.selectedNotetypeId,
                   notetypeNames.contains(where: { $0.0 == restoredNotetypeID }) {
                    shouldSkipNextNotetypeFieldReload = selectedNotetypeId != restoredNotetypeID
                    selectedNotetypeId = restoredNotetypeID
                }
                fieldNames = restoredSession.fieldNames
                fieldValues = restoredSession.fieldValues
                fieldSourceModes = normalizedFieldSourceModes(
                    restoredSession.fieldSourceModes,
                    fieldCount: fieldNames.count
                )
                tags = restoredSession.tags
                return
            }
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
            fieldSourceModes = Array(repeating: false, count: fieldNames.count)
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

    private func restorePersistedSessionIfNeeded() {
        guard restoredSession == nil else { return }
        guard draft == nil, persistedSessionData.isEmpty == false else { return }
        guard let data = persistedSessionData.data(using: .utf8),
              let session = try? JSONDecoder().decode(PersistedAddNoteSession.self, from: data)
        else {
            persistedSessionData = ""
            return
        }
        restoredSession = session
    }

    private func persistSession() {
        guard draft == nil, hasLoadedInitialData, isRestoringPersistedSession == false else { return }
        let session = PersistedAddNoteSession(
            selectedDeckId: selectedDeckId,
            selectedNotetypeId: selectedNotetypeId == 0 ? nil : selectedNotetypeId,
            fieldNames: fieldNames,
            fieldValues: fieldValues,
            fieldSourceModes: fieldSourceModes,
            tags: tags
        )
        guard let data = try? JSONEncoder().encode(session),
              let string = String(data: data, encoding: .utf8)
        else { return }
        persistedSessionData = string
    }

    private func clearPersistedSession() {
        restoredSession = nil
        persistedSessionData = ""
    }

    private func normalizedFieldSourceModes(_ modes: [Bool], fieldCount: Int) -> [Bool] {
        if modes.count == fieldCount {
            return modes
        }
        if modes.count > fieldCount {
            return Array(modes.prefix(fieldCount))
        }
        return modes + Array(repeating: false, count: max(0, fieldCount - modes.count))
    }

    private func fieldValue(at index: Int) -> String {
        guard index < fieldValues.count else { return "" }
        return fieldValues[index]
    }

    private func sourcePreviewHeight(for value: String) -> CGFloat {
        let value = value.lowercased()
        if value.contains("<img") || value.contains("<svg") {
            return 220
        }
        return 96
    }

    private func beginMediaImport(for index: Int, action: NoteEditorMediaAction) {
        pendingMediaFieldIndex = index
        switch action {
        case .photoLibrary:
            showPhotoPicker = true
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                previewErrorMessage = L("note_editor_media_import_camera_unavailable")
                showPreviewError = true
                pendingMediaFieldIndex = nil
                return
            }
            showCameraPicker = true
        case .file:
            showMediaFileImporter = true
        case .audioRecording:
            Task { @MainActor in
                let allowed = await NoteEditorMediaPermissions.requestMicrophoneAccess()
                guard allowed else {
                    previewErrorMessage = L("rich_text_audio_permission_denied")
                    showPreviewError = true
                    pendingMediaFieldIndex = nil
                    return
                }
                showAudioRecorder = true
            }
        }
    }

    @MainActor
    private func previewAudio(at index: Int) {
        do {
            try MediaAudioPreview.playAudioTags(in: fieldValue(at: index))
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
            try handleImportedMediaPayload(
                data: data,
                filename: filename,
                contentType: contentType
            )
        } catch {
            pendingMediaFieldIndex = nil
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    private func handleImportedFile(_ result: Result<URL, Error>) {
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
            try handleImportedMediaPayload(
                data: data,
                filename: filename,
                contentType: contentType
            )
        } catch {
            pendingMediaFieldIndex = nil
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    private func handleCameraImageData(_ data: Data) {
        showCameraPicker = false
        Task { @MainActor in
            await Task.yield()
            do {
                try handleImportedMediaPayload(
                    data: data,
                    filename: NoteFieldMediaSupport.suggestedFilename(
                        contentType: .jpeg,
                        fallbackPrefix: "camera"
                    ),
                    contentType: .jpeg
                )
            } catch {
                pendingMediaFieldIndex = nil
                previewErrorMessage = error.localizedDescription
                showPreviewError = true
            }
        }
    }

    private func handleRecordedAudio(_ url: URL) {
        defer {
            showAudioRecorder = false
            pendingMediaFieldIndex = nil
        }

        do {
            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension) ?? .mpeg4Audio
            let filename = NoteFieldMediaSupport.suggestedFilename(
                sourceURL: url,
                contentType: contentType,
                fallbackPrefix: "recording"
            )
            try insertImportedMedia(data: data, filename: filename, contentType: contentType)
        } catch {
            previewErrorMessage = error.localizedDescription
            showPreviewError = true
        }
    }

    private func handleImportedMediaPayload(
        data: Data,
        filename: String,
        contentType: UTType?
    ) throws {
        if NoteFieldMediaSupport.shouldOptimizeImage(contentType: contentType, filename: filename),
           let image = NoteFieldMediaSupport.optimizationPreviewImage(from: data) {
            presentImageOptimization(
                image: image,
                originalByteCount: data.count,
                suggestedFilename: filename,
                confirmTitle: L("image_optimizer_confirm_insert")
            ) { result in
                do {
                    try insertImportedMedia(
                        data: result.data,
                        filename: result.filename,
                        contentType: result.contentType
                    )
                    pendingMediaFieldIndex = nil
                } catch {
                    previewErrorMessage = error.localizedDescription
                    showPreviewError = true
                }
            }
            return
        }

        try insertImportedMedia(data: data, filename: filename, contentType: contentType)
        pendingMediaFieldIndex = nil
    }

    private func beginExistingImageEdit(at index: Int) {
        guard let imageFilename = NoteFieldMediaSupport.firstImageFilename(in: fieldValue(at: index)) else {
            return
        }
        guard let imageURL = mediaClient.localURL(imageFilename) else {
            previewErrorMessage = L("image_optimizer_existing_load_failed")
            showPreviewError = true
            return
        }

        do {
            let data = try Data(contentsOf: imageURL)
            guard let image = NoteFieldMediaSupport.optimizationPreviewImage(from: data) else {
                throw MediaImportError.loadFailed
            }

            presentImageOptimization(
                image: image,
                originalByteCount: data.count,
                suggestedFilename: imageFilename,
                confirmTitle: L("image_optimizer_confirm_save")
            ) { result in
                do {
                    let storedFilename = try mediaClient.save(result.data, result.filename)
                    fieldValues[index] = NoteFieldMediaSupport.replacingFirstImageFilename(
                        in: fieldValues[index],
                        oldFilename: imageFilename,
                        newFilename: storedFilename
                    )
                } catch {
                    previewErrorMessage = error.localizedDescription
                    showPreviewError = true
                }
            }
        } catch {
            previewErrorMessage = L("image_optimizer_existing_load_failed")
            showPreviewError = true
        }
    }

    private func presentImageOptimization(
        image: UIImage,
        originalByteCount: Int,
        suggestedFilename: String,
        confirmTitle: String,
        onConfirm: @escaping (NoteOptimizedImageResult) -> Void
    ) {
        imageOptimizationRequest = NoteImageOptimizationRequest(
            image: image,
            originalByteCount: originalByteCount,
            suggestedFilename: suggestedFilename,
            confirmTitle: confirmTitle,
            onConfirm: { result in
                imageOptimizationRequest = nil
                onConfirm(result)
            },
            onCancel: {
                imageOptimizationRequest = nil
                pendingMediaFieldIndex = nil
            }
        )
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

            clearPersistedSession()
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

private struct PersistedAddNoteSession: Codable {
    let selectedDeckId: Int64?
    let selectedNotetypeId: Int64?
    let fieldNames: [String]
    let fieldValues: [String]
    let fieldSourceModes: [Bool]
    let tags: String
}
