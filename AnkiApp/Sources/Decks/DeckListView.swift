import SwiftUI
import AnkiKit
import AnkiBackend
import AnkiClients
import Dependencies

struct DeckListView: View {
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.deckClient) var deckClient
    @ObservedObject private var collectionState = AppCollectionState.shared
    @AppStorage(DeckListHeatmapSettings.showKey) private var showDeckListHeatmap = true

    @State private var tree: [DeckTreeNode] = []
    @State private var isLoading = true
    @State private var deckToDelete: DeckTreeNode?
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var heatmapRefreshID = 0
    @State private var hasLoadedHeatmap = false
    @State private var isExportingDeck = false
    @State private var exportedDeckFileURL: URL?
    @State private var showDeckExportShareSheet = false
    @State private var exportError: String?
    @State private var showExportError = false
    var onDeckChanged: (() -> Void)? = nil

    init(onDeckChanged: (() -> Void)? = nil) {
        self.onDeckChanged = onDeckChanged
        let cachedTree = DeckTreeCache.load()
        _tree = State(initialValue: cachedTree)
        _isLoading = State(initialValue: true)
    }

    var body: some View {
        Group {
            if isLoading && tree.isEmpty {
                ProgressView()
            } else if tree.isEmpty {
                ContentUnavailableView(
                    L("deck_list_empty_title"),
                    systemImage: "rectangle.stack",
                    description: Text(L("deck_list_empty_desc"))
                )
            } else {
                List {
                    if showDeckListHeatmap {
                        Section {
                            DeckListHeatmapCard(refreshID: heatmapRefreshID, showsExternalLoading: isLoading)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    Section {
                        ForEach(tree) { node in
                            DeckRowView(
                                node: node,
                                depth: 0,
                                isCollectionReady: collectionState.isReady,
                                onDeckChanged: {
                                    Task { await loadDecks() }
                                    refreshHeatmap()
                                    onDeckChanged?()
                                },
                                onDeleteRequested: { node in
                                    deckToDelete = node
                                    showDeleteConfirm = true
                                },
                                onExportRequested: { node in
                                    Task { await exportDeck(node) }
                                }
                            )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.amgiBackground)
                .listStyle(.insetGrouped)
                .navigationDestination(for: DeckInfo.self) { deck in
                    DeckDetailView(deck: deck)
                }
                .refreshable {
                    await loadDecks()
                    refreshHeatmap()
                }
            }
        }
        .background(Color.amgiBackground)
        .navigationTitle(L("deck_list_nav_title"))
        .onReceive(NotificationCenter.default.publisher(for: AppUserStore.didChangeNotification)) { _ in
            Task {
                await loadDecks()
                refreshHeatmap()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didResetNotification)) { _ in
            Task {
                await loadDecks()
                refreshHeatmap()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didOpenNotification)) { _ in
            Task {
                await loadDecks()
                refreshHeatmap()
            }
        }
        .alert(
            L("deck_delete_confirm2_title"),
            isPresented: $showDeleteConfirm
        ) {
            Button(L("btn_confirm_delete"), role: .destructive) {
                Task { await deleteDeck() }
            }
            Button(L("btn_cancel"), role: .cancel) {}
        } message: {
            Text(L("deck_delete_confirm2_message", deckToDelete?.name ?? ""))
        }
        .alert(L("deck_action_error_title"), isPresented: $showDeleteError) {
            Button(L("btn_got_it"), role: .cancel) {}
        } message: {
            Text(deleteError ?? L("label_error_unknown"))
        }
        .alert(L("deck_action_error_title"), isPresented: $showExportError) {
            Button(L("btn_got_it"), role: .cancel) {}
        } message: {
            Text(exportError ?? L("label_error_unknown"))
        }
        .sheet(isPresented: $showDeckExportShareSheet) {
            if let url = exportedDeckFileURL {
                ShareSheet(items: [url])
            }
        }
        .task {
            await loadDecks()
            if !hasLoadedHeatmap {
                hasLoadedHeatmap = true
                refreshHeatmap()
            }
        }
        .onChange(of: collectionState.isReady) { _, isReady in
            guard isReady else { return }
            Task {
                await loadDecks()
                refreshHeatmap()
            }
        }
    }

    private func loadDecks() async {
        guard collectionState.isReady else {
            isLoading = tree.isEmpty
            return
        }

        isLoading = true
        do {
            let freshTree = try deckClient.fetchTree()
            tree = freshTree
            DeckTreeCache.save(freshTree)
        } catch {
            print("[DeckListView] Error loading decks: \(error)")
        }
        isLoading = false
    }

    private func deleteDeck() async {
        guard collectionState.isReady else { return }
        guard let node = deckToDelete else { return }
        do {
            try deckClient.delete(node.id)
            DeckDeletionMaintenance.resetHeatmapSelectionIfNeeded(deletedDeckID: node.id)

            do {
                try DeckDeletionMaintenance.cleanupUnusedMedia(using: backend)
            } catch {
                print("[DeckListView] Media cleanup after deck deletion failed: \(error)")
            }

            await loadDecks()
            refreshHeatmap()
            onDeckChanged?()
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
        }
        deckToDelete = nil
    }

    private func refreshHeatmap() {
        guard showDeckListHeatmap, collectionState.isReady else { return }
        heatmapRefreshID += 1
    }

    private func exportDeck(_ node: DeckTreeNode) async {
        guard collectionState.isReady, !isExportingDeck else { return }
        isExportingDeck = true
        defer { isExportingDeck = false }

        let configuration = ImportHelper.ExportPackageConfiguration.deck(
            deckID: node.id,
            deckName: node.fullName,
            includeScheduling: true,
            includeDeckConfigs: true,
            includeMedia: true,
            legacy: false
        )
        let backend = self.backend
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try ImportHelper.exportPackage(backend: backend, configuration: configuration)
            }.value
            exportedDeckFileURL = url
            showDeckExportShareSheet = true
        } catch {
            exportError = L("deck_export_error", error.localizedDescription)
            showExportError = true
        }
    }
}

// MARK: - DeckRowView

private struct DeckRowView: View {
    @Dependency(\.deckClient) var deckClient
    let node: DeckTreeNode
    let depth: Int
    let isCollectionReady: Bool
    let onDeckChanged: () -> Void
    let onDeleteRequested: (DeckTreeNode) -> Void
    let onExportRequested: (DeckTreeNode) -> Void

    @State private var showRenamePrompt = false
    @State private var renameText = ""
    @State private var actionError: String?
    @State private var showActionError = false

    var body: some View {
        deckContent
        .listRowBackground(Color.amgiSurfaceElevated)
        .alert(L("deck_rename_alert_title"), isPresented: $showRenamePrompt) {
            TextField(L("deck_rename_alert_placeholder"), text: $renameText)
            Button(L("btn_cancel"), role: .cancel) {}
            Button(L("btn_save")) {
                Task { await renameDeck() }
            }
        } message: {
            Text(L("deck_rename_alert_message"))
        }
        .alert(L("deck_action_error_title"), isPresented: $showActionError) {
            Button(L("btn_got_it"), role: .cancel) {}
        } message: {
            Text(actionError ?? L("label_error_unknown"))
        }
    }

    @ViewBuilder
    private var deckContent: some View {
        if node.children.isEmpty {
            leafRow
        } else {
            parentRow
        }
    }

    @ViewBuilder
    private var leafRow: some View {
        NavigationLink(value: deckInfo) {
            rowContent
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            swipeButtons
        }
    }

    @ViewBuilder
    private var parentRow: some View {
        if depth == 0 {
            DisclosureGroup {
                childrenList
            } label: {
                NavigationLink(value: deckInfo) {
                    rowContent
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                swipeButtons
            }
        } else {
            DisclosureGroup {
                childrenList
            } label: {
                NavigationLink(value: deckInfo) {
                    rowContent
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                swipeButtons
            }
        }
    }

    @ViewBuilder
    private var swipeButtons: some View {
        Button(role: .destructive) {
            onDeleteRequested(node)
        } label: {
            Label(L("deck_row_delete"), systemImage: "trash")
        }
        .disabled(!isCollectionReady)

        Button {
            renameText = node.name
            showRenamePrompt = true
        } label: {
            Label(L("deck_row_rename"), systemImage: "pencil")
        }
        .tint(Color.amgiAccent)
        .disabled(!isCollectionReady)

        Button {
            onExportRequested(node)
        } label: {
            Label(L("deck_row_export"), systemImage: "square.and.arrow.up")
        }
        .tint(Color.amgiPositive)
        .disabled(!isCollectionReady)
    }

    private var childrenList: some View {
        ForEach(node.children) { child in
            DeckRowView(
                node: child,
                depth: depth + 1,
                isCollectionReady: isCollectionReady,
                onDeckChanged: onDeckChanged,
                onDeleteRequested: onDeleteRequested,
                onExportRequested: onExportRequested
            )
        }
    }

    private var rowContent: some View {
        HStack {
            Text(node.name)
                .amgiFont(.body)
                .foregroundStyle(Color.amgiTextPrimary)
            Spacer()
            DeckCountsView(counts: node.counts)
        }
    }

    private var deckInfo: DeckInfo {
        DeckInfo(id: node.id, name: node.fullName, counts: node.counts)
    }

    private func renameDeck() async {
        guard isCollectionReady else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try deckClient.rename(node.id, trimmed)
            onDeckChanged()
        } catch {
            actionError = error.localizedDescription
            showActionError = true
        }
    }
}
