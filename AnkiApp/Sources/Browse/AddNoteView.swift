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

    let onSave: () -> Void
    let preselectedDeckId: Int64?

    init(onSave: @escaping () -> Void, preselectedDeckId: Int64? = nil) {
        self.onSave = onSave
        self.preselectedDeckId = preselectedDeckId
        _selectedDeckId = State(initialValue: preselectedDeckId ?? 1)
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
                        loadFields()
                    }
                }

                Section(L("add_note_section_fields")) {
                    VStack(spacing: 0) {
                        ForEach(Array(fieldNames.enumerated()), id: \.offset) { index, name in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if shouldShowAudioButton(fieldName: name, index: index) {
                                        Button {
                                            previewAudio(at: index)
                                        } label: {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.blue)
                                        .disabled(MediaAudioPreview.firstAudioFileName(in: fieldValue(at: index)) == nil)
                                    }
                                }
                                RichNoteFieldEditor(htmlText: fieldBinding(for: index))
                                    .frame(minHeight: 32)
                            }
                            .padding(.vertical, 8)

                            if index < fieldNames.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(L("add_note_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("add_note_button")) {
                        Task { await save() }
                    }
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
        }
    }

    private func fieldBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < fieldValues.count ? fieldValues[index] : "" },
            set: { newValue in
                if index < fieldValues.count {
                    fieldValues[index] = newValue
                }
            }
        )
    }

    private func loadData() async {
        decks = (try? deckClient.fetchAll()) ?? []
        
        // 如果没有预设置的牌组，选择第一个牌组
        if preselectedDeckId == nil, let first = decks.first {
            selectedDeckId = first.id
        } else if let preselectedDeckId, !decks.contains(where: { $0.id == preselectedDeckId }) {
            // 如果预设置的牌组不在列表中，选择第一个牌组
            if let first = decks.first {
                selectedDeckId = first.id
            }
        }

        do {
            let resp: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )
            notetypeNames = resp.entries.map { ($0.id, $0.name) }
            if let first = notetypeNames.first {
                selectedNotetypeId = first.0
                loadFields()
            }
        } catch {
            print("[AddNote] Error loading notetypes: \(error)")
        }
    }

    private func loadFields() {
        guard selectedNotetypeId != 0 else { return }
        do {
            var req = Anki_Notetypes_NotetypeId()
            req.ntid = selectedNotetypeId
            let notetype: Anki_Notetypes_Notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: req
            )
            fieldNames = notetype.fields.map(\.name)
            fieldValues = Array(repeating: "", count: fieldNames.count)
        } catch {
            print("[AddNote] Error loading fields: \(error)")
        }
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
            note.fields = fieldValues
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
