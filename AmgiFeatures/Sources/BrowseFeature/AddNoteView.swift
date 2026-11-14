//
//  AddNoteView.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 30.03.2026.
//

package import SwiftUI
package import AnkiKit
import Theme
#if canImport(UIKit)
import UIKit
#endif

/// Add Note container: owns the modal chrome (navigation, toolbar, dismissal)
/// and drives an `AddNoteModel` for deck/notetype loading and the note write.
/// The form itself is `AddNoteContent`, bound to the model.
package struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddNoteModel
    @State private var showDiscardConfirm = false
    @State private var showPreview = false
    @Environment(\.scenePhase) private var scenePhase
    #if canImport(UIKit)
    @State private var recorder = VoiceRecorder()
    #endif
    let onSave: () -> Void

    package init(
        preselectedDeckId: DeckID? = nil,
        initialDraft: AddNoteDraft? = nil,
        onSave: @escaping () -> Void
    ) {
        let resolved = preselectedDeckId ?? initialDraft?.deckID.map { DeckID($0) }
        _model = State(initialValue: AddNoteModel(preselectedDeckId: resolved, initialDraft: initialDraft))
        self.onSave = onSave
    }

    package var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Add Note", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(model.hasUnsavedChanges || recordingActive || model.isSaving)
                .confirmationDialog(
                    String(localized: "Discard this note?", bundle: .module),
                    isPresented: $showDiscardConfirm,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Discard", bundle: .module), role: .destructive) {
                        #if canImport(UIKit)
                        recorder.cancel()
                        #endif
                        model.discardAudio()
                        dismiss()
                    }
                    Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
                } message: {
                    Text("The note hasn't been added yet. Discarding loses your text and recordings.", bundle: .module)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", bundle: .module)) {
                            if model.hasUnsavedChanges || recordingActive {
                                showDiscardConfirm = true
                            } else {
                                dismiss()
                            }
                        }
                        .disabled(model.isSaving)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "Preview", bundle: .module), systemImage: "eye") {
                            showPreview = true
                        }
                        .disabled(model.fieldNames.isEmpty || model.selectedNotetypeId.rawValue == 0)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Add", bundle: .module)) {
                            finishRecording()
                            Task {
                                if await model.save() {
                                    onSave()
                                    dismiss()
                                }
                            }
                        }
                        .disabled(model.isSaving || (!model.canAdd && !recordingActive) || recordingStarting)
                    }
                }
                .sheet(isPresented: $showPreview) {
                    NoteCardPreviewSheet(notetypeID: model.selectedNotetypeId, fields: model.fieldValues)
                }
                .task { await model.loadData() }
                .onChange(of: scenePhase) {
                    if scenePhase != .active { finishRecording() }
                    #if canImport(UIKit)
                    if scenePhase == .background { recorder.cancel() }
                    #endif
                }
                .onDisappear {
                    #if canImport(UIKit)
                    recorder.cancel()
                    #endif
                    model.discardAudio()
                }
        }
    }
}

extension AddNoteView {
    @ViewBuilder
    private var content: some View {
        #if canImport(UIKit)
        AddNoteContent(model: model, recorder: recorder)
            .modifier(VoiceRecorderAlerts(recorder: recorder))
            .onAppear {
                recorder.onEndedEarly = { model.attachAudio($0.url, toField: $0.fieldIndex) }
            }
        #else
        AddNoteContent(model: model)
        #endif
    }

    private var recordingActive: Bool {
        #if canImport(UIKit)
        recorder.isRecording
        #else
        false
        #endif
    }

    private var recordingStarting: Bool {
        #if canImport(UIKit)
        recorder.isStarting
        #else
        false
        #endif
    }

    private func finishRecording() {
        #if canImport(UIKit)
        if let clip = recorder.stop() {
            model.attachAudio(clip.url, toField: clip.fieldIndex)
        }
        recorder.stopPlayback()
        #endif
    }
}

// MARK: - AddNoteContent

/// The Add Note form: deck + note-type pickers, the note-type's fields, and a
/// tags field. Bound to an `AddNoteModel`; owns no I/O of its own, so it
/// renders in a `#Preview` from a seeded model.
struct AddNoteContent: View {
    @Environment(\.palette) private var palette
    @Bindable var model: AddNoteModel
    #if canImport(UIKit)
    var recorder: VoiceRecorder? = nil
    #endif

    var body: some View {
        Form {
            Section(String(localized: "Deck", bundle: .module)) {
                Picker(String(localized: "Deck", bundle: .module), selection: $model.selectedDeckId) {
                    ForEach(model.decks) { deck in
                        Text(deck.name).tag(deck.id)
                    }
                }
            }

            Section(String(localized: "Note Type", bundle: .module)) {
                Picker(String(localized: "Type", bundle: .module), selection: $model.selectedNotetypeId) {
                    ForEach(model.notetypeNames, id: \.id) { entry in
                        Text(entry.name).tag(entry.id)
                    }
                }
                .disabled(model.isSaving || (recorder?.isRecording ?? false) || (recorder?.isStarting ?? false))
                .onChange(of: model.selectedNotetypeId) {
                    Task { await model.loadFields() }
                }
            }

            Section(String(localized: "Fields", bundle: .module)) {
                ForEach(Array(model.fieldNames.enumerated()), id: \.element) { index, name in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(name)
                                .amgiFont(.caption)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            #if canImport(UIKit)
                            if let recorder {
                                NoteVoiceRecordButton(recorder: recorder, fieldIndex: index) { url in
                                    model.attachAudio(url, toField: index)
                                }
                                .disabled(model.isSaving)
                            }
                            #endif
                        }
                        RichNoteFieldEditor(htmlText: $model[fieldAt: index])
                        #if canImport(UIKit)
                        if let recorder, model.fieldAudio.indices.contains(index) {
                            NoteFieldAudioBar(
                                soundFiles: NoteSoundTags.filenames(in: model[fieldAt: index]),
                                pendingClips: model.fieldAudio[index],
                                playingURL: recorder.playingURL,
                                resolve: { model.mediaURL(for: $0) },
                                onTogglePlayback: { recorder.togglePlayback($0) },
                                onDeletePending: { url in
                                    if recorder.playingURL == url { recorder.stopPlayback() }
                                    model.removeAudio(url, fromField: index)
                                }
                            )
                            .disabled(model.isSaving || recorder.isRecording || recorder.isStarting)
                        }
                        #endif
                    }
                }
            }

            Section(String(localized: "Tags", bundle: .module)) {
                TextField(String(localized: "Tags (space-separated)", bundle: .module), text: $model.tags)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(palette.danger)
                        .amgiFont(.caption)
                }
            }
        }
        .disabled(model.isSaving || model.isLoadingFields)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    // Seed the model directly: AddNoteContent has no `.task`, so the sample
    // fields aren't overwritten by a load and no live backend is touched.
    let model = AddNoteModel()
    model.decks = [.sample, .filtered]
    model.selectedDeckId = DeckInfo.sample.id
    model.notetypeNames = [(NotetypeID(1), "Basic"), (NotetypeID(2), "Cloze")]
    model.selectedNotetypeId = NotetypeID(1)
    model.fieldNames = ["Front", "Back"]
    model.fieldValues = ["안녕하세요", "Hello"]
    model.tags = "vocab korean"
    return NavigationStack {
        AddNoteContent(model: model)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
