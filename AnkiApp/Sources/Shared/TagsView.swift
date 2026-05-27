import SwiftUI
import AnkiClients
import Dependencies

/// View for managing tags in the collection.
/// When `targetNoteIDs` is non-empty the view acts as a "apply / remove tag"
/// picker for the selected notes.  When empty it is a collection-level tag
/// manager.
@MainActor
struct TagsView: View {
    @Dependency(\.tagClient) var tagClient
    let targetNoteIDs: [Int64]
    let onSelectTag: ((String) -> Void)?
    /// Controls behaviour when `targetNoteIDs` is non-empty.
    /// `.addToNotes` — tapping a tag immediately adds it to all selected notes.
    /// `.removeFromNotes` — tapping a tag immediately removes it from all selected notes.
    /// `.manage` (default) — tapping a tag shows a confirmation dialog.
    let noteMode: NoteMode

    enum NoteMode { case manage, addToNotes, removeFromNotes }

    @Environment(\.dismiss) private var dismiss

    @State private var allTags: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showAddTag = false
    @State private var newTagName: String = ""
    @State private var selectedTag: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var tagActionTag: String?
    @State private var isApplying = false
    @State private var showRenameTag = false
    @State private var tagToRename: String?
    @State private var renameTagName = ""
    @State private var showClearUnusedConfirm = false
    @State private var clearUnusedResultMessage: String?
    @State private var showClearUnusedResult = false

    init(
        targetNoteIDs: [Int64] = [],
        noteMode: NoteMode = .manage,
        onSelectTag: ((String) -> Void)? = nil
    ) {
        self.targetNoteIDs = targetNoteIDs
        self.noteMode = noteMode
        self.onSelectTag = onSelectTag
    }

    // Whether this view is in "apply tags to notes" mode
    private var isNoteMode: Bool { !targetNoteIDs.isEmpty }
    private var canBrowseTagNotes: Bool { !isNoteMode && onSelectTag != nil }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if allTags.isEmpty {
                    ContentUnavailableView(
                        L("tags_empty_title"),
                        systemImage: "tag.slash",
                        description: Text(isNoteMode
                            ? L("tags_empty_note_mode")
                            : L("tags_empty_collection_mode"))
                    )
                } else {
                    tagListContent
                }
            }
            .background(Color.amgiBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .accessibilityLabel(L("common_done"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddTag = true }) {
                        Image(systemName: "plus")
                    }
                }
                if !isNoteMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showClearUnusedConfirm = true
                            } label: {
                                Label(L("tags_clear_unused_action"), systemImage: "trash.slash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddTag) {
                addTagSheet
            }
            .alert(L("tags_clear_unused_title"), isPresented: $showClearUnusedConfirm) {
                Button(L("common_cancel"), role: .cancel) { }
                Button(L("tags_clear_unused_action"), role: .destructive) {
                    Task { await clearUnusedTagsAction() }
                }
            } message: {
                Text(L("tags_clear_unused_confirm"))
            }
            .alert(L("tags_delete_title"), isPresented: $showDeleteConfirm) {
                Button(L("common_cancel"), role: .cancel) { }
                Button(L("common_delete"), role: .destructive) {
                    if let tag = selectedTag {
                        Task { await deleteTag(tag) }
                    }
                }
            } message: {
                if let tag = selectedTag {
                    Text(L("tags_delete_confirm", tag))
                }
            }
            .alert(L("tags_rename_title"), isPresented: $showRenameTag) {
                TextField(L("tags_rename_placeholder"), text: $renameTagName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(L("common_cancel"), role: .cancel) { tagToRename = nil }
                Button(L("tags_rename_confirm")) {
                    if let old = tagToRename {
                        Task { await renameTagAction(from: old, to: renameTagName) }
                    }
                }
            } message: {
                if let tag = tagToRename {
                    Text(L("tags_delete_confirm", tag))
                }
            }
            .alert(L("common_error"), isPresented: $showError) {
                Button(L("common_ok")) { }
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .alert(L("tags_clear_unused_title"), isPresented: $showClearUnusedResult) {
                Button(L("common_ok")) { clearUnusedResultMessage = nil }
            } message: {
                Text(clearUnusedResultMessage ?? "")
            }
            .confirmationDialog(
                L("tags_action_dialog_title", tagActionTag ?? ""),
                isPresented: Binding(
                    get: { tagActionTag != nil && isNoteMode && noteMode == .manage },
                    set: { if !$0 { tagActionTag = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let tag = tagActionTag {
                    Button(L("tags_apply_to_notes", targetNoteIDs.count)) {
                        Task { await applyTag(tag) }
                    }
                    Button(L("tags_remove_from_notes", targetNoteIDs.count), role: .destructive) {
                        Task { await removeTagFromSelectedNotes(tag) }
                    }
                    Button(L("common_cancel"), role: .cancel) { tagActionTag = nil }
                }
            }
            .task {
                await loadTags()
            }
        }
    }

    // MARK: - Computed

    private var navigationTitle: String {
        switch noteMode {
        case .addToNotes: return L("tags_nav_title_add_mode")
        case .removeFromNotes: return L("tags_nav_title_remove_mode")
        case .manage: return isNoteMode ? L("tags_nav_title_note_mode") : L("tags_nav_title")
        }
    }

    // MARK: - Extracted Sub-Views

    private var tagListContent: some View {
        List {
            if isNoteMode {
                Section {
                    Label(L("tags_apply_hint", targetNoteIDs.count), systemImage: "doc.text")
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            } else if canBrowseTagNotes {
                Section {
                    Label(L("tags_browse_hint"), systemImage: "line.3.horizontal.decrease.circle")
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }

            Section(isNoteMode ? L("tags_section_select") : L("tags_section_all")) {
                ForEach(allTags.sorted(), id: \.self) { tag in
                    tagRow(tag)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .listStyle(.insetGrouped)
    }

    private var addTagSheet: some View {
        NavigationStack {
            Form {
                if isNoteMode {
                    Section(L("tags_target_notes")) {
                        Text(L("tags_new_tag_will_apply", targetNoteIDs.count))
                            .amgiFont(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
                Section(L("tags_new_tag_name_section")) {
                    TextField(L("tags_new_tag_placeholder"), text: $newTagName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button(isNoteMode ? L("tags_create_and_apply") : L("tags_create_tag")) {
                        Task { await createTag() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(L("tags_add_tag_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { showAddTag = false }
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func tagRow(_ tag: String) -> some View {
        HStack {
            Label(tag, systemImage: "tag.fill")
                .foregroundStyle(Color.amgiAccent)
            Spacer()
            if isApplying && tagActionTag == tag {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                if isNoteMode || canBrowseTagNotes {
                    Image(systemName: "chevron.right")
                        .font(AmgiFont.caption.font)
                        .foregroundStyle(Color.amgiTextTertiary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isNoteMode {
                switch noteMode {
                case .addToNotes:
                    Task { await applyTag(tag) }
                case .removeFromNotes:
                    Task { await removeTagFromSelectedNotes(tag) }
                case .manage:
                    tagActionTag = tag
                }
            } else {
                if let onSelectTag {
                    onSelectTag(tag)
                    dismiss()
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if isNoteMode {
                Button {
                    Task { await removeTagFromSelectedNotes(tag) }
                } label: {
                    Label(L("tags_remove_swipe"), systemImage: "tag.slash")
                }
                .tint(Color.amgiWarning)

                Button {
                    Task { await applyTag(tag) }
                } label: {
                    Label(L("tags_apply_swipe"), systemImage: "tag")
                }
                .tint(Color.amgiAccent)
            } else {
                Button(role: .destructive) {
                    selectedTag = tag
                    showDeleteConfirm = true
                } label: {
                    Label(L("common_delete"), systemImage: "trash")
                }

                Button {
                    tagToRename = tag
                    renameTagName = tag
                    showRenameTag = true
                } label: {
                    Label(L("tags_rename_swipe"), systemImage: "pencil")
                }
                .tint(Color.amgiAccent)
            }
        }
    }

    // MARK: - Actions

    private func loadTags() async {
        do {
            allTags = try tagClient.getAllTags()
            isLoading = false
        } catch {
            errorMessage = L("tags_error_load", error.localizedDescription)
            showError = true
            isLoading = false
        }
    }

    private func createTag() async {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        do {
            if isNoteMode {
                try tagClient.addTagToNotes(name, targetNoteIDs)
            } else {
                try tagClient.addTag(name)
            }
            newTagName = ""
            showAddTag = false
            await loadTags()
        } catch {
            errorMessage = L("tags_error_create", error.localizedDescription)
            showError = true
        }
    }

    private func applyTag(_ tag: String) async {
        isApplying = true
        defer { isApplying = false; tagActionTag = nil }
        do {
            try tagClient.addTagToNotes(tag, targetNoteIDs)
        } catch {
            errorMessage = L("tags_error_apply", error.localizedDescription)
            showError = true
        }
    }

    private func removeTagFromSelectedNotes(_ tag: String) async {
        isApplying = true
        defer { isApplying = false; tagActionTag = nil }
        do {
            try tagClient.removeTagFromNotes(tag, targetNoteIDs)
        } catch {
            errorMessage = L("tags_error_remove", error.localizedDescription)
            showError = true
        }
    }

    private func deleteTag(_ tag: String) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try tagClient.removeTag(tag)
            selectedTag = nil
            await loadTags()
        } catch {
            errorMessage = L("tags_error_delete", error.localizedDescription)
            showError = true
        }
    }

    private func renameTagAction(from oldName: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else {
            tagToRename = nil
            return
        }
        do {
            try tagClient.renameTag(oldName, trimmed)
            tagToRename = nil
            await loadTags()
        } catch {
            errorMessage = L("tags_error_rename", error.localizedDescription)
            showError = true
        }
    }

    private func clearUnusedTagsAction() async {
        do {
            let removedCount = try tagClient.clearUnusedTags()
            await loadTags()
            clearUnusedResultMessage = L("tags_clear_unused_result", removedCount)
            showClearUnusedResult = true
        } catch {
            errorMessage = L("tags_error_clear_unused", error.localizedDescription)
            showError = true
        }
    }
}

#Preview {
    TagsView()
        .preferredColorScheme(.dark)
}

#Preview("注记模式") {
    TagsView(targetNoteIDs: [1, 2, 3])
        .preferredColorScheme(.dark)
}
