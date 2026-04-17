import SwiftUI
import AnkiKit

struct ExportPackageDraft: Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case collectionPackage
        case deckPackage
        case selectedNotesPackage

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .collectionPackage:
                return "export_config_scope_collection"
            case .deckPackage:
                return "export_config_scope_deck"
            case .selectedNotesPackage:
                return "export_config_scope_selected_notes"
            }
        }
    }

    var kind: Kind = .collectionPackage
    var selectedDeckID: Int64?
    var includeScheduling = false
    var includeDeckConfigs = true
    var includeMedia = true
    var legacySupport = false
}

struct ExportOptionsView: View {
    @Binding var draft: ExportPackageDraft
    let availableKinds: [ExportPackageDraft.Kind]
    let decks: [DeckInfo]
    let selectedNotesCount: Int?
    let onCancel: () -> Void
    let onExport: () -> Void

    private var canExport: Bool {
        switch draft.kind {
        case .collectionPackage, .selectedNotesPackage:
            return true
        case .deckPackage:
            return draft.selectedDeckID != nil
        }
    }

    var body: some View {
        Form {
            Section(L("export_config_scope")) {
                if availableKinds.count > 1 {
                    Picker(L("export_config_scope"), selection: $draft.kind) {
                        ForEach(availableKinds) { kind in
                            Text(L(kind.titleKey)).tag(kind)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } else if let onlyKind = availableKinds.first {
                    Text(L(onlyKind.titleKey))
                }

                if draft.kind == .deckPackage {
                    if decks.isEmpty {
                        Text(L("review_no_decks_available"))
                            .amgiFont(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                    } else {
                        Picker(
                            L("export_config_deck"),
                            selection: Binding(
                                get: { draft.selectedDeckID ?? decks.first?.id ?? 0 },
                                set: { draft.selectedDeckID = $0 }
                            )
                        ) {
                            ForEach(decks) { deck in
                                Text(deck.name).tag(deck.id)
                            }
                        }
                    }
                }

                if draft.kind == .selectedNotesPackage, let selectedNotesCount {
                    Text(L("export_config_selected_notes_count", selectedNotesCount))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }

            Section(L("export_config_options")) {
                Toggle(L("export_config_include_media"), isOn: $draft.includeMedia)

                if draft.kind != .collectionPackage {
                    Toggle(L("export_config_include_scheduling"), isOn: $draft.includeScheduling)
                    Toggle(L("export_config_include_deck_configs"), isOn: $draft.includeDeckConfigs)
                }

                Toggle(L("export_config_legacy_support"), isOn: $draft.legacySupport)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("menu_export_deck"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("common_cancel")) {
                    onCancel()
                }
                .amgiToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("export_config_export_button")) {
                    onExport()
                }
                .amgiToolbarTextButton()
                .disabled(!canExport)
            }
        }
        .onAppear {
            if !availableKinds.contains(draft.kind), let firstKind = availableKinds.first {
                draft.kind = firstKind
            }
            if draft.kind == .deckPackage, draft.selectedDeckID == nil {
                draft.selectedDeckID = decks.first?.id
            }
        }
        .onChange(of: draft.kind) { _, newValue in
            if newValue == .deckPackage, draft.selectedDeckID == nil {
                draft.selectedDeckID = decks.first?.id
            }
        }
    }
}

struct ImportPackageDraft: Sendable {
    var mergeNotetypes = true
    var updateNotes: ImportHelper.ImportUpdateStrategy = .ifNewer
    var updateNotetypes: ImportHelper.ImportUpdateStrategy = .ifNewer
    var includeScheduling = true
    var includeDeckConfigs = true

    var configuration: ImportHelper.ImportPackageConfiguration {
        .ankiPackage(
            mergeNotetypes: mergeNotetypes,
            updateNotes: updateNotes,
            updateNotetypes: updateNotetypes,
            includeScheduling: includeScheduling,
            includeDeckConfigs: includeDeckConfigs
        )
    }
}

struct ImportOptionsView: View {
    let fileName: String
    let fileExtension: String
    @Binding var draft: ImportPackageDraft
    let onCancel: () -> Void
    let onImport: () -> Void

    private var isCollectionPackage: Bool {
        fileExtension.lowercased() == "colpkg"
    }

    var body: some View {
        Form {
            Section(L("import_config_file")) {
                Text(fileName)
                Text(L(isCollectionPackage ? "import_config_file_type_collection" : "import_config_file_type_apkg"))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if isCollectionPackage {
                Section(L("import_config_collection_title")) {
                    Text(L("import_config_collection_message"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            } else {
                Section(L("import_config_options")) {
                    Toggle(L("import_config_include_scheduling"), isOn: $draft.includeScheduling)
                    Toggle(L("import_config_include_deck_configs"), isOn: $draft.includeDeckConfigs)
                    Toggle(L("import_config_merge_notetypes"), isOn: $draft.mergeNotetypes)
                }

                Section(L("import_config_update_policy")) {
                    Picker(L("import_config_update_notes"), selection: $draft.updateNotes) {
                        ForEach(ImportHelper.ImportUpdateStrategy.allCases) { strategy in
                            Text(L(strategy.titleKey)).tag(strategy)
                        }
                    }

                    Picker(L("import_config_update_notetypes"), selection: $draft.updateNotetypes) {
                        ForEach(ImportHelper.ImportUpdateStrategy.allCases) { strategy in
                            Text(L(strategy.titleKey)).tag(strategy)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("alert_import_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("common_cancel")) {
                    onCancel()
                }
                .amgiToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("import_config_import_button")) {
                    onImport()
                }
                .amgiToolbarTextButton()
            }
        }
    }
}

private extension ImportHelper.ImportUpdateStrategy {
    var titleKey: String {
        switch self {
        case .ifNewer:
            return "import_config_update_if_newer"
        case .always:
            return "import_config_update_always"
        case .never:
            return "import_config_update_never"
        }
    }
}