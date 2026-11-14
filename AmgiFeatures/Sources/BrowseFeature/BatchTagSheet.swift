//
//  BatchTagSheet.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 03.05.2026.
//

import SwiftUI
import AnkiClients
import AnkiKit
import Dependencies
import Theme

/// Adds tags to and removes tags from every selected note. Each tag shows
/// a three-state box — on all, some or none of the selection — and a tap
/// cycles it; only the tags the user touched are written back.
struct BatchTagSheet: View {
    let onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var model: BatchTagModel
    @State private var newTagName: String = ""

    init(noteIDs: Set<NoteID>, onApplied: @escaping () -> Void) {
        self.onApplied = onApplied
        _model = State(initialValue: BatchTagModel(noteIDs: noteIDs))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .searchable(text: $model.query, prompt: Text("Search tags", bundle: .module))
            .navigationTitle(String(localized: "Tags for \(model.noteIDs.count) notes", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Apply", bundle: .module)) { apply() }
                        .disabled(!model.canApply)
                }
            }
            .alert(
                String(localized: "Couldn't update tags", bundle: .module),
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .interactiveDismissDisabled(model.hasChanges)
            .task { await model.load() }
        }
    }

    private var form: some View {
        Form {
            Section(String(localized: "New tag", bundle: .module)) {
                HStack {
                    TextField(String(localized: "Add new tag", bundle: .module), text: $newTagName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(addTyped)
                    Button(String(localized: "Add", bundle: .module), action: addTyped)
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            let selection = model.visibleSelectionTags
            if !selection.isEmpty {
                Section {
                    ForEach(selection, id: \.self, content: row)
                } header: {
                    Text("On selected notes", bundle: .module)
                } footer: {
                    Text("Tap a tag to add it to or remove it from every selected note.", bundle: .module)
                }
            }

            let others = model.visibleOtherTags
            Section(String(localized: "Other tags", bundle: .module)) {
                if others.isEmpty {
                    Group {
                        if model.query.isEmpty {
                            Text("No tags yet", bundle: .module)
                        } else {
                            Text("No matching tags", bundle: .module)
                        }
                    }
                    .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(others, id: \.self, content: row)
                }
            }
        }
    }

    private func row(_ tag: String) -> some View {
        let coverage = model.coverage(of: tag)
        return Button {
            model.toggle(tag)
        } label: {
            HStack {
                Image(systemName: Self.symbol(for: coverage))
                    .foregroundStyle(coverage == .none ? palette.textSecondary : palette.accent)
                Text(tag)
                    .foregroundStyle(palette.textPrimary)
                    .fontWeight(model.isChanged(tag) ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if coverage == .some {
                    Text("\(model.noteCount(of: tag)) of \(model.noteIDs.count)", bundle: .module)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .accessibilityValue(Text(Self.accessibilityValue(for: coverage), bundle: .module))
    }

    private static func symbol(for coverage: BatchTagModel.Coverage) -> String {
        switch coverage {
        case .all: "checkmark.square.fill"
        case .some: "minus.square.fill"
        case .none: "square"
        }
    }

    private static func accessibilityValue(for coverage: BatchTagModel.Coverage) -> LocalizedStringKey {
        switch coverage {
        case .all: "On all selected notes"
        case .some: "On some selected notes"
        case .none: "Not on selected notes"
        }
    }
}

private extension BatchTagSheet {
    func addTyped() {
        model.addTyped(newTagName)
        newTagName = ""
    }

    func apply() {
        Task {
            if await model.apply() {
                onApplied()
                dismiss()
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let _ = prepareDependencies {
        $0.tagClient.getAllTags = { ["grammar", "vocab", "n5", "verb", "adjective"] }
        $0.noteClient.searchAll = { _, _ in
            [
                NoteRecord(id: NoteID(1), guid: "a", mid: NotetypeID(1), mod: 0,
                           tags: " vocab n5 ", flds: "", sfld: "", csum: 0),
                NoteRecord(id: NoteID(2), guid: "b", mid: NotetypeID(1), mod: 0,
                           tags: " vocab ", flds: "", sfld: "", csum: 0),
            ]
        }
    }
    return BatchTagSheet(noteIDs: [NoteID(1), NoteID(2)], onApplied: {})
}
#endif
