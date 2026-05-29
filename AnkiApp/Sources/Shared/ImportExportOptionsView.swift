import SwiftUI
import AnkiKit
import AnkiClients
import AmgiTheme
import Dependencies

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
    @Dependency(\.deckClient) private var deckClient
    @Environment(\.palette) private var palette

    @Binding var draft: ExportPackageDraft
    let availableKinds: [ExportPackageDraft.Kind]
    let decks: [DeckInfo]
    let selectedNotesCount: Int?
    let onCancel: () -> Void
    let onExport: () -> Void

    @State private var loadedDecks: [DeckInfo] = []
    @State private var isLoadingDecks = false

    private var canExport: Bool {
        switch draft.kind {
        case .collectionPackage, .selectedNotesPackage:
            return true
        case .deckPackage:
            return draft.selectedDeckID != nil
        }
    }

    private var resolvedDecks: [DeckInfo] {
        loadedDecks
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
                    if isLoadingDecks {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L("sync_syncing"))
                                .amgiFont(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    } else if resolvedDecks.isEmpty {
                        Text(L("review_no_decks_available"))
                            .amgiFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        Picker(
                            L("export_config_deck"),
                            selection: Binding(
                                get: { draft.selectedDeckID ?? resolvedDecks.first?.id ?? 0 },
                                set: { draft.selectedDeckID = $0 }
                            )
                        ) {
                            ForEach(resolvedDecks) { deck in
                                Text(deck.name).tag(deck.id)
                            }
                        }
                    }
                }

                if draft.kind == .selectedNotesPackage, let selectedNotesCount {
                    Text(L("export_config_selected_notes_count", selectedNotesCount))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .listRowBackground(palette.surfaceElevated)

            Section(L("export_config_options")) {
                Toggle(L("export_config_include_media"), isOn: $draft.includeMedia)

                if draft.kind != .collectionPackage {
                    Toggle(L("export_config_include_scheduling"), isOn: $draft.includeScheduling)
                    Toggle(L("export_config_include_deck_configs"), isOn: $draft.includeDeckConfigs)
                }

                Toggle(L("export_config_legacy_support"), isOn: $draft.legacySupport)
            }
            .listRowBackground(palette.surfaceElevated)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .tint(palette.accent)// Apply accent color to form elements like toggles and pickers
        .navigationTitle(L("menu_export_deck"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("common_cancel")) {
                    onCancel()
                }
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
            loadedDecks = decks
            if !availableKinds.contains(draft.kind), let firstKind = availableKinds.first {
                draft.kind = firstKind
            }
            if draft.kind == .deckPackage, draft.selectedDeckID == nil {
                draft.selectedDeckID = resolvedDecks.first?.id
            }
            if draft.kind == .deckPackage, resolvedDecks.isEmpty {
                Task { await ensureDeckOptionsLoaded() }
            }
        }
        .onChange(of: draft.kind) { _, newValue in
            if loadedDecks.isEmpty, !decks.isEmpty {
                loadedDecks = decks
            }
            if newValue == .deckPackage, draft.selectedDeckID == nil {
                draft.selectedDeckID = resolvedDecks.first?.id
            }
            if newValue == .deckPackage, resolvedDecks.isEmpty {
                Task { await ensureDeckOptionsLoaded() }
            }
        }
        .onChange(of: decks) { _, newValue in
            loadedDecks = newValue
            if draft.kind == .deckPackage, draft.selectedDeckID == nil {
                draft.selectedDeckID = newValue.first?.id
            }
        }
    }

    @MainActor
    private func ensureDeckOptionsLoaded() async {
        guard isLoadingDecks == false else { return }
        guard resolvedDecks.isEmpty else { return }

        isLoadingDecks = true
        defer { isLoadingDecks = false }

        let fetchedDecks = await loadDeckOptions()
        loadedDecks = fetchedDecks
        if draft.selectedDeckID == nil {
            draft.selectedDeckID = fetchedDecks.first?.id
        }
    }

    private func loadDeckOptions() async -> [DeckInfo] {
        let attempts: [() throws -> [DeckInfo]] = [
            { try deckClient.fetchNamesOnly() },
            { try deckClient.fetchAll() },
            { flattenDeckOptions(from: try deckClient.fetchTree()) }
        ]

        for pass in 0..<2 {
            for attempt in attempts {
                if let deckOptions = try? attempt() {
                    let sortedDecks = deckOptions.sorted { $0.name < $1.name }
                    if sortedDecks.isEmpty == false {
                        return sortedDecks
                    }
                }
            }

            if pass == 0 {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        return []
    }

    private func flattenDeckOptions(from nodes: [DeckTreeNode]) -> [DeckInfo] {
        nodes
            .flatMap { node -> [DeckInfo] in
                [
                    DeckInfo(id: node.id, name: node.fullName, counts: node.counts)
                ] + flattenDeckOptions(from: node.children)
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
    @Environment(\.palette) private var palette
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
                    .foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(palette.surfaceElevated)

            if isCollectionPackage {
                Section(L("import_config_collection_title")) {
                    Text(L("import_config_collection_message"))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surfaceElevated)
            } else {
                Section(L("import_config_options")) {
                    Toggle(L("import_config_include_scheduling"), isOn: $draft.includeScheduling)
                    Toggle(L("import_config_include_deck_configs"), isOn: $draft.includeDeckConfigs)
                    Toggle(L("import_config_merge_notetypes"), isOn: $draft.mergeNotetypes)
                }
                .listRowBackground(palette.surfaceElevated)

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
                .listRowBackground(palette.surfaceElevated)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .tint(palette.accent) // Apply accent color to form elements like toggles and pickers
        .navigationTitle(L("alert_import_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("common_cancel")) {
                    onCancel()
                }
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
