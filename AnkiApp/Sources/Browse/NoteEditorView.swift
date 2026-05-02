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

struct NoteEditorView: View {
    let note: NoteRecord
    let onSave: () -> Void

    @Dependency(\.noteClient) var noteClient
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.mediaClient) var mediaClient

    @State private var fieldValues: [String] = []
    @State private var fieldNames: [String] = []
    @State private var fieldSourceModes: [Bool] = []
    @State private var tags: String = ""
    @State private var hasLoadedOriginalState = false
    @State private var isSaving = false
    @State private var originalFieldValues: [String] = []
    @State private var originalTags: String = ""
    @State private var showDiscardChangesConfirmation = false
    @State private var showPreviewSheet = false
    @State private var pendingMediaFieldIndex: Int?
    @State private var pendingTagRemoval: String?
    @State private var showPhotoPicker = false
    @State private var showCameraPicker = false
    @State private var showMediaFileImporter = false
    @State private var showAudioRecorder = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageOptimizationRequest: NoteImageOptimizationRequest?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var notetype: Anki_Notetypes_Notetype?
    @FocusState private var isTagEditorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedTags: String {
        tagList.joined(separator: " ")
    }

    private var tagList: [String] {
        var seen = Set<String>()
        return tags
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private var hasUnsavedChanges: Bool {
        hasLoadedOriginalState
            && (fieldValues != originalFieldValues || trimmedTags != originalTags)
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
                showsSourcePreview: containsEmbeddedMedia(value),
                sourcePreviewHeight: sourcePreviewHeight(for: value)
            )
        }
    }

    private var tagRemovalAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingTagRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTagRemoval = nil
                }
            }
        )
    }

    var body: some View {
        Form {
            Section(L("add_note_section_fields")) {
                VStack(spacing: AmgiSpacing.sm) {
                    NoteFieldsPageEditor(
                        fieldNames: fieldNames,
                        fieldValues: $fieldValues,
                        fieldSourceModes: $fieldSourceModes,
                        actionStates: fieldEditorActionStates,
                        onInsertPhoto: { beginMediaImport(for: $0, action: .photoLibrary) },
                        onInsertCameraPhoto: { beginMediaImport(for: $0, action: .camera) },
                        onInsertFile: { beginMediaImport(for: $0, action: .file) },
                        onRecordAudio: { beginMediaImport(for: $0, action: .audioRecording) },
                        onPreviewAudio: { previewAudio(at: $0) },
                        onEditImage: { beginExistingImageEdit(at: $0) }
                    )

                    tagEditorCard
                }
                .padding(.horizontal, AmgiSpacing.md)
                .padding(.vertical, AmgiSpacing.xs)
                .background(Color.amgiSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        // The embedded fields editor is one tall WKWebView row; letting Form apply
        // keyboard avoidance makes it overshoot based on the row height instead of
        // the active caret position.
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
                    tags = trimmedTags
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
        .sheet(isPresented: $showPreviewSheet) {
            if let notetype {
                UncommittedCardPreviewSheet(
                    title: L("note_editor_preview_title"),
                    emptyMessage: L("note_editor_preview_empty_card"),
                    notetype: notetype,
                    allowsTemplateSelection: true,
                    loadPreviewNote: {
                        NoteProtoFactory.makeNote(
                            from: note,
                            fieldValues: fieldValues,
                            tags: tags
                        )
                    }
                )
            }
        }
        .sheet(item: $imageOptimizationRequest) { request in
            NoteImageOptimizationSheet(request: request)
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok")) { }
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
        .alert(L("common_delete"), isPresented: tagRemovalAlertPresented) {
            Button(L("common_delete"), role: .destructive) {
                if let pendingTagRemoval {
                    removeTag(pendingTagRemoval)
                }
                pendingTagRemoval = nil
            }
            Button(L("common_cancel"), role: .cancel) {
                pendingTagRemoval = nil
            }
        } message: {
            Text(pendingTagRemoval ?? "")
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

    private var tagEditorCard: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("add_note_section_tags"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)

            ZStack(alignment: .topLeading) {
                // TextField is always in the hierarchy so @FocusState binding is always active.
                TextField(L("tags_add_placeholder"), text: $tags, axis: .vertical)
                    .focused($isTagEditorFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
                    .onChange(of: isTagEditorFocused) {
                        if !isTagEditorFocused {
                            tags = trimmedTags
                        }
                    }
                    // Hide the raw text field visually when showing pills,
                    // but keep it in the layout so focus works.
                    .opacity(isTagEditorFocused ? 1 : 0)

                // Display mode: pill capsules — shown only when not editing.
                if !isTagEditorFocused {
                    Group {
                        if tagList.isEmpty {
                            Text(L("tags_add_placeholder"))
                                .amgiFont(.body)
                                .foregroundStyle(Color.amgiTextSecondary)
                        } else {
                            TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                                ForEach(tagList, id: \.self) { tag in
                                    tagCapsule(tag)
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.amgiAccent.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                tags = trimmedTags
                isTagEditorFocused = true
            }
        }
    }

    private func tagCapsule(_ tag: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(tag)
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiAccent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.amgiAccent.opacity(0.14), in: Capsule())

            Button {
                pendingTagRemoval = tag
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white, Color.red)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .padding(.top, 4)
        .padding(.trailing, 4)
    }

    private func fieldValue(at index: Int) -> String {
        guard index < fieldValues.count else { return "" }
        return fieldValues[index]
    }

    private func beginMediaImport(for index: Int, action: NoteEditorMediaAction) {
        pendingMediaFieldIndex = index
        switch action {
        case .photoLibrary:
            showPhotoPicker = true
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                errorMessage = L("note_editor_media_import_camera_unavailable")
                showError = true
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
                    errorMessage = L("rich_text_audio_permission_denied")
                    showError = true
                    pendingMediaFieldIndex = nil
                    return
                }
                showAudioRecorder = true
            }
        }
    }

    private func sourcePreviewHeight(for value: String) -> CGFloat {
        let value = value.lowercased()
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

    @MainActor
    private func previewAudio(at index: Int) {
        do {
            try MediaAudioPreview.playFirstAudioTag(in: fieldValue(at: index))
        } catch {
            errorMessage = error.localizedDescription
            showError = true
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
            errorMessage = error.localizedDescription
            showError = true
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
            errorMessage = error.localizedDescription
            showError = true
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
                errorMessage = error.localizedDescription
                showError = true
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
            errorMessage = error.localizedDescription
            showError = true
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
                    errorMessage = error.localizedDescription
                    showError = true
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
            errorMessage = L("image_optimizer_existing_load_failed")
            showError = true
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
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } catch {
            errorMessage = L("image_optimizer_existing_load_failed")
            showError = true
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
            .map(RichNoteFieldEditor.normalizedStoredHTML)
        while fieldValues.count < fieldNames.count { fieldValues.append("") }
        fieldSourceModes = Array(repeating: false, count: fieldNames.count)
        tags = noteData.tags.trimmingCharacters(in: .whitespaces)
        originalFieldValues = fieldValues
        originalTags = trimmedTags
        hasLoadedOriginalState = true
    }

    private func removeTag(_ tag: String) {
        tags = tagList.filter { $0 != tag }.joined(separator: " ")
    }

    private func attemptDismiss() {
        tags = trimmedTags
        if hasUnsavedChanges {
            showDiscardChangesConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save() async {
        tags = trimmedTags
        isSaving = true
        let storedFieldValues = fieldValues.map(RichNoteFieldEditor.normalizedStoredHTML)
        let newFlds = storedFieldValues.joined(separator: "\u{1f}")
        let newSfld = storedFieldValues.first ?? ""
        let newCsum = Int64(newSfld.hashValue & 0xFFFFFFFF)

        var updatedNote = note
        updatedNote.flds = newFlds
        updatedNote.sfld = newSfld
        updatedNote.csum = newCsum
        updatedNote.tags = trimmedTags.isEmpty ? "" : " \(trimmedTags) "

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

/// A simple wrapping flow layout for tag capsules.
/// Lays out children left-to-right, wrapping to the next row when the
/// container width is exhausted.
private struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
