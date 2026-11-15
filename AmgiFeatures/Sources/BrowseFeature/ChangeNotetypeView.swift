//
//  ChangeNotetypeView.swift
//  BrowseFeature
//

import AnkiKit
import SwiftUI
import Theme
import UI

/// Browse › Change Note Type: pick the target notetype, then say where each
/// new field and card template comes from. Laid out like Anki's dialog —
/// one row per *new* field or template, each choosing its old source — so
/// the list reads as the note that will result.
struct ChangeNotetypeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var model: ChangeNotetypeModel
    @State private var confirming = false
    let onChanged: () -> Void

    init(noteIDs: [NoteID], onChanged: @escaping () -> Void) {
        _model = State(initialValue: ChangeNotetypeModel(noteIDs: noteIDs))
        self.onChanged = onChanged
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Change Note Type", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Change", bundle: .module)) { confirming = true }
                            .disabled(!model.canSave)
                            .amgiToolbarTextButton()
                    }
                }
                .confirmationDialog(
                    String(localized: "Change the note type of \(model.noteIDs.count) notes?", bundle: .module),
                    isPresented: $confirming,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Change", bundle: .module), role: .destructive) {
                        Task {
                            if await model.save() {
                                onChanged()
                                dismiss()
                            }
                        }
                    }
                    Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
                } message: {
                    Text(confirmationMessage)
                }
                .alert(
                    String(localized: "Couldn't change the note type", bundle: .module),
                    isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
                ) {
                    Button(String(localized: "OK", bundle: .module), role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
                .interactiveDismissDisabled(model.isSaving)
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .mixed(let names):
            ContentUnavailableView {
                Label(String(localized: "Different note types", bundle: .module), systemImage: "square.stack.3d.up.slash")
            } description: {
                Text("The selected notes use \(names.joined(separator: ", ")). Select notes of one note type to change it.", bundle: .module)
            }
        case .failed(let message):
            ContentUnavailableView(
                String(localized: "Couldn't load the notes", bundle: .module),
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .ready:
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Current", bundle: .module), value: model.oldNotetype?.name ?? "")
                Picker(String(localized: "New note type", bundle: .module), selection: Binding(
                    get: { model.target },
                    set: { if let target = $0 { Task { await model.selectTarget(target) } } }
                )) {
                    ForEach(model.targets) { notetype in
                        Text(notetype.name).tag(Optional(notetype))
                    }
                }
            } footer: {
                Text("\(model.noteIDs.count) notes", bundle: .module)
            }

            if let info = model.info, !model.isLoadingInfo {
                Section {
                    ForEach(Array(info.newFieldNames.enumerated()), id: \.offset) { index, name in
                        sourcePicker(
                            title: name,
                            options: info.oldFieldNames,
                            selection: model.newFields.indices.contains(index) ? model.newFields[index] : nil
                        ) { model.setField(index, from: $0) }
                    }
                } header: {
                    Text("Fields", bundle: .module)
                } footer: {
                    discardFooter(
                        model.discardedFields,
                        message: { Text("Content of these fields will be lost: \($0)", bundle: .module) }
                    )
                }

                if !model.isCloze, !info.newTemplateNames.isEmpty {
                    Section {
                        ForEach(Array(info.newTemplateNames.enumerated()), id: \.offset) { index, name in
                            sourcePicker(
                                title: name,
                                options: info.oldTemplateNames,
                                selection: model.newTemplates.indices.contains(index) ? model.newTemplates[index] : nil
                            ) { model.setTemplate(index, from: $0) }
                        }
                    } header: {
                        Text("Cards", bundle: .module)
                    } footer: {
                        discardFooter(
                            model.discardedTemplates,
                            message: { Text("These cards will be deleted, with their review history: \($0)", bundle: .module) }
                        )
                    }
                } else if model.isCloze {
                    Section {
                        Text("Cloze cards follow the cloze numbers in the text, so there are no cards to map.", bundle: .module)
                            .amgiFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    } header: {
                        Text("Cards", bundle: .module)
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
    }

    /// One row per new field or template: which old one it comes from.
    private func sourcePicker(
        title: String,
        options: [String],
        selection: Int?,
        onChange: @escaping (Int?) -> Void
    ) -> some View {
        Picker(selection: Binding(get: { selection }, set: onChange)) {
            Text("(Nothing)", bundle: .module).tag(Int?.none)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Text(option).tag(Int?.some(index))
            }
        } label: {
            Text(title)
                .foregroundStyle(selection == nil ? palette.textSecondary : palette.textPrimary)
        }
    }

    @ViewBuilder
    private func discardFooter(_ names: [String], message: (String) -> Text) -> some View {
        if !names.isEmpty {
            message(names.joined(separator: ", "))
                .foregroundStyle(palette.danger)
        }
    }

    private var confirmationMessage: String {
        String(localized: "This changes the collection's structure, so the next sync must upload or download the whole collection.", bundle: .module)
    }
}
