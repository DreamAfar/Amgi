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
    @State private var isSaving = false
    @State private var showSavedConfirmation = false
    @State private var showTagPicker = false
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(L("add_note_section_fields")) {
                ForEach(Array(fieldNames.enumerated()), id: \.offset) { index, name in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(name, text: fieldBinding(for: index), axis: .vertical)
                            .lineLimit(1...10)
                            .textInputAutocapitalization(.sentences)
                    }
                }
            }

            Section(L("add_note_section_tags")) {
                TextField(L("add_note_tags_placeholder"), text: $tags)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !availableTags.isEmpty {
                    Button(action: { showTagPicker = true }) {
                        Label(L("note_editor_select_tags"), systemImage: "ellipsis")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(.blue)
                }
                
                if !tags.isEmpty {
                    HStack {
                        Text(L("note_editor_current_tags"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        ForEach(tags.split(separator: " ").map(String.init), id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.2), in: Capsule())
                        }
                    }
                }
            }
        }
        .navigationTitle(L("note_editor_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("note_editor_save")) {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .overlay {
            if showSavedConfirmation {
                VStack {
                    Spacer()
                    Text(L("note_editor_saved"))
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showTagPicker) {
            NavigationStack {
                List {
                    ForEach(availableTags.sorted(), id: \.self) { tag in
                        Button(action: { addTag(tag) }) {
                            HStack {
                                Text(tag)
                                if tags.contains(tag) {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(L("note_editor_available_tags"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("common_done")) { showTagPicker = false }
                    }
                }
            }
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok")) { }
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
        .task { 
            loadNote()
            await loadAvailableTags()
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

    private func loadNote() {
        // Get field names from the Rust backend's notetype
        do {
            var ntReq = Anki_Notetypes_NotetypeId()
            ntReq.ntid = note.mid
            let notetype: Anki_Notetypes_Notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: ntReq
            )
            fieldNames = notetype.fields.map(\.name)
        } catch {
            print("[NoteEditorView] Error loading notetype: \(error)")
            errorMessage = L("common_failed_load_notetype")
            showError = true
        }

        fieldValues = note.flds
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)
        while fieldValues.count < fieldNames.count { fieldValues.append("") }
        tags = note.tags.trimmingCharacters(in: .whitespaces)
    }
    
    private func loadAvailableTags() async {
        do {
            availableTags = try tagClient.getAllTags()
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
            withAnimation { showSavedConfirmation = true }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSavedConfirmation = false }
            onSave()
        } catch {
            errorMessage = L("note_editor_error_save", error.localizedDescription)
            showError = true
        }
        isSaving = false
    }
}
