//
//  NotetypeFieldManagerView.swift
//  TemplatesFeature
//
//  Created by Vladimir Gusev on 14.05.2026.
//

import SwiftUI
import Theme
import AnkiKit

/// Anki's Fields dialog: add, rename, remove and reorder a notetype's
/// fields, pick the sort field, and edit each field's options. Edits are
/// staged in `NotetypeFieldManagerModel` and saved together; a structural
/// change (add, remove, reorder) asks first, because it forces a one-way
/// full sync.
struct NotetypeFieldManagerView: View {
    let notetypeId: NotetypeID
    let preferredName: String
    var onSaved: (@Sendable () async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var model = NotetypeFieldManagerModel()
    @State private var prompt: FieldNamePrompt?
    @State private var promptText = ""
    @State private var nameError: String?
    @State private var pendingRemoval: NotetypeFieldManagerModel.EditableField?
    @State private var confirmFullSync = false
    @State private var confirmDiscard = false

    var body: some View {
        content
            .background(palette.background)
            .navigationTitle(String(localized: "Fields", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.hasChanges)
            .toolbar { toolbarContent }
            .alert(prompt?.title ?? "", isPresented: isPrompting) {
                TextField(String(localized: "Field name", bundle: .module), text: $promptText)
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
                Button(prompt?.confirmLabel ?? "") { submitPrompt() }
            }
            .alert(
                String(localized: "Invalid field name", bundle: .module),
                isPresented: Binding(get: { nameError != nil }, set: { if !$0 { nameError = nil } })
            ) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {}
            } message: {
                Text(nameError ?? "")
            }
            .confirmationDialog(
                String(localized: "Delete “\(pendingRemoval?.name ?? "")”?", bundle: .module),
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete Field", bundle: .module), role: .destructive) {
                    if let pendingRemoval { model.remove(pendingRemoval.id) }
                }
            } message: {
                Text("Its content is removed from every note of this type when you save.", bundle: .module)
            }
            .confirmationDialog(
                String(localized: "Save and require a full sync?", bundle: .module),
                isPresented: $confirmFullSync,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Save", bundle: .module)) { Task { await save() } }
            } message: {
                Text(
                    "Adding, removing or reordering fields, or changing the sort field, changes the collection's structure. The next sync will have to upload or download the whole collection, and changes made on other devices since the last sync may be lost.",
                    bundle: .module
                )
            }
            .confirmationDialog(
                String(localized: "Discard changes?", bundle: .module),
                isPresented: $confirmDiscard,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Discard", bundle: .module), role: .destructive) { dismiss() }
            }
            .alert(
                String(localized: "Save Failed", bundle: .module),
                isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })
            ) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {}
            } message: {
                Text(model.saveError ?? "")
            }
            .task { await model.load(notetypeId: notetypeId) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError = model.loadError {
            ContentUnavailableView(
                String(localized: "Couldn't Load Fields", bundle: .module),
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else {
            fieldList
        }
    }

    private var fieldList: some View {
        List {
            Section {
                ForEach($model.fields) { $item in
                    NavigationLink {
                        FieldOptionsView(field: $item.field)
                    } label: {
                        FieldRow(
                            field: item,
                            isSortField: item.id == model.sortFieldID
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if model.canRemove(item) {
                            Button(role: .destructive) { pendingRemoval = item } label: {
                                Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
                            }
                        }
                        Button { beginRename(item) } label: {
                            Label(String(localized: "Rename", bundle: .module), systemImage: "pencil")
                        }
                        .tint(palette.accent)
                    }
                    .contextMenu {
                        Button(String(localized: "Rename", bundle: .module), systemImage: "pencil") { beginRename(item) }
                        if model.canRemove(item) {
                            Button(String(localized: "Delete", bundle: .module), systemImage: "trash", role: .destructive) {
                                pendingRemoval = item
                            }
                        }
                    }
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    promptText = ""
                    prompt = .add
                } label: {
                    Label(String(localized: "Add Field", bundle: .module), systemImage: "plus.circle.fill")
                        .amgiFont(.body)
                }
            } header: {
                HStack {
                    Text(model.notetypeName.isEmpty ? preferredName : model.notetypeName)
                    Spacer()
                    EditButton()
                        .amgiFont(.caption)
                        .textCase(nil)
                }
            } footer: {
                Text("Drag to reorder with Edit. The order is the order fields appear in when you edit a note.", bundle: .module)
            }

            Section {
                Picker(String(localized: "Sort by", bundle: .module), selection: $model.sortFieldID) {
                    ForEach(model.fields) { item in
                        Text(item.name).tag(Optional(item.id))
                    }
                }
            } header: {
                Text("Sort Field", bundle: .module)
            } footer: {
                Text("Browse shows and sorts notes of this type by this field.", bundle: .module)
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel", bundle: .module)) {
                if model.hasChanges { confirmDiscard = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isSaving {
                ProgressView()
            } else {
                Button(String(localized: "Save", bundle: .module)) {
                    if model.requiresFullSync {
                        confirmFullSync = true
                    } else {
                        Task { await save() }
                    }
                }
                .disabled(!model.hasChanges)
            }
        }
    }

    // MARK: - Actions

    private var isPrompting: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }

    private func beginRename(_ item: NotetypeFieldManagerModel.EditableField) {
        promptText = item.name
        prompt = .rename(item.id)
    }

    private func submitPrompt() {
        guard let prompt else { return }
        let error: NotetypeFieldManagerModel.NameError?
        switch prompt {
        case .add: error = model.addField(named: promptText)
        case .rename(let id): error = model.rename(id, to: promptText)
        }
        nameError = error?.message
    }

    private func save() async {
        guard await model.save() else { return }
        if let onSaved { await onSaved() }
        dismiss()
    }
}

/// Which name prompt is up: a new field, or a rename of an existing one.
enum FieldNamePrompt: Equatable {
    case add
    case rename(UUID)

    var title: String {
        switch self {
        case .add: String(localized: "Add Field", bundle: .module)
        case .rename: String(localized: "Rename Field", bundle: .module)
        }
    }

    var confirmLabel: String {
        switch self {
        case .add: String(localized: "Add", bundle: .module)
        case .rename: String(localized: "Rename", bundle: .module)
        }
    }
}

private struct FieldRow: View {
    let field: NotetypeFieldManagerModel.EditableField
    let isSortField: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: AmgiSpacing.sm) {
            Text(field.name)
                .amgiFont(.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            if isSortField {
                badge(String(localized: "Sort", bundle: .module), color: palette.accent)
            }
            if field.isNew {
                badge(String(localized: "New", bundle: .module), color: palette.positive)
            }
            if field.isProtected {
                Image(systemName: "lock.fill")
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityLabel(String(localized: "Required by this notetype", bundle: .module))
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .amgiFont(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, AmgiSpacing.xs)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// One field's options, as in Anki's Fields dialog.
private struct FieldOptionsView: View {
    @Binding var field: Notetype.Field

    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Section {
                TextField(
                    String(localized: "Shown in the empty field while editing", bundle: .module),
                    text: $field.config.description,
                    axis: .vertical
                )
            } header: {
                Text("Description", bundle: .module)
            }

            Section {
                Toggle(String(localized: "Remember last input when adding", bundle: .module), isOn: $field.config.sticky)
                Toggle(String(localized: "Right-to-left text", bundle: .module), isOn: $field.config.rtl)
                Toggle(String(localized: "Use the HTML editor by default", bundle: .module), isOn: $field.config.plainText)
                Toggle(String(localized: "Collapse by default", bundle: .module), isOn: $field.config.collapsed)
                Toggle(String(localized: "Exclude from unqualified searches", bundle: .module), isOn: $field.config.excludeFromSearch)
            } header: {
                Text("Editing", bundle: .module)
            } footer: {
                Text("Unqualified searches are ones that don't name a field, like a plain word typed into Browse.", bundle: .module)
            }

            Section {
                TextField(String(localized: "Font", bundle: .module), text: $field.config.fontName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Stepper(value: $field.config.fontSize, in: 6...72) {
                    Text("Size: \(field.config.fontSize)", bundle: .module)
                }
            } header: {
                Text("Editor Font", bundle: .module)
            } footer: {
                Text("Used by Anki's note editor on desktop. It doesn't change how cards look; that's the card template's styling.", bundle: .module)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(field.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
