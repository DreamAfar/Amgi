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
    @State private var draggedDeckID: Int64?
    @State private var isMovingDeck = false
    @State private var moveError: String?
    @State private var showMoveError = false
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
                                draggedDeckID: $draggedDeckID,
                                isMovingDeck: isMovingDeck,
                                canAcceptDrop: canAcceptDrop,
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
                                },
                                onMoveRequested: { sourceID, targetID in
                                    Task { await moveDeck(sourceID: sourceID, targetID: targetID) }
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
        .alert(L("deck_action_error_title"), isPresented: $showMoveError) {
            Button(L("btn_got_it"), role: .cancel) {}
        } message: {
            Text(moveError ?? L("label_error_unknown"))
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
            DeckListHeatmapCache.clearCurrent()

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

    @MainActor
    private func exportDeck(_ node: DeckTreeNode) async {
        guard collectionState.isReady, !isExportingDeck else { return }
        exportedDeckFileURL = nil
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
            await MainActor.run {
                exportedDeckFileURL = url
                showDeckExportShareSheet = true
            }
        } catch {
            await MainActor.run {
                exportError = L("deck_export_error", error.localizedDescription)
                showExportError = true
            }
        }
    }

    private func canAcceptDrop(sourceID: Int64, targetID: Int64) -> Bool {
        guard sourceID != targetID else { return false }
        guard let source = findNode(id: sourceID, in: tree) else { return false }
        return !contains(deckID: targetID, in: source)
    }

    @MainActor
    private func moveDeck(sourceID: Int64, targetID: Int64) async {
        defer { draggedDeckID = nil }

        guard collectionState.isReady, !isMovingDeck else { return }
        guard canAcceptDrop(sourceID: sourceID, targetID: targetID) else { return }
        guard let source = findNode(id: sourceID, in: tree) else { return }
        guard let target = findNode(id: targetID, in: tree) else { return }

        let destinationName = "\(target.fullName)::\(source.name)"
        guard destinationName != source.fullName else { return }

        isMovingDeck = true
        defer { isMovingDeck = false }

        do {
            try deckClient.rename(sourceID, destinationName)
            await loadDecks()
            refreshHeatmap()
            onDeckChanged?()
        } catch {
            moveError = error.localizedDescription
            showMoveError = true
        }
    }

    private func findNode(id: Int64, in nodes: [DeckTreeNode]) -> DeckTreeNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let child = findNode(id: id, in: node.children) {
                return child
            }
        }
        return nil
    }

    private func contains(deckID: Int64, in node: DeckTreeNode) -> Bool {
        if node.id == deckID {
            return true
        }
        return node.children.contains { contains(deckID: deckID, in: $0) }
    }
}

// MARK: - DeckRowView

private struct DeckRowView: View {
    @Dependency(\.deckClient) var deckClient
    let node: DeckTreeNode
    let depth: Int
    let isCollectionReady: Bool
    @Binding var draggedDeckID: Int64?
    let isMovingDeck: Bool
    let canAcceptDrop: (Int64, Int64) -> Bool
    let onDeckChanged: () -> Void
    let onDeleteRequested: (DeckTreeNode) -> Void
    let onExportRequested: (DeckTreeNode) -> Void
    let onMoveRequested: (Int64, Int64) -> Void

    @State private var showRenamePrompt = false
    @State private var renameText = ""
    @State private var actionError: String?
    @State private var showActionError = false
    @State private var isExpanded = false
    @State private var isDropTargeted = false

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
        interactiveRow {
            NavigationLink(value: deckInfo) {
                rowContent
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            swipeButtons
        }
    }

    @ViewBuilder
    private var parentRow: some View {
        let disclosureGroup = DisclosureGroup(isExpanded: $isExpanded) {
            childrenList
        } label: {
            interactiveRow {
                NavigationLink(value: deckInfo) {
                    rowContent
                }
            }
        }

        if isExpanded {
            disclosureGroup
        } else {
            disclosureGroup
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    swipeButtons
                }
        }
    }

    private func interactiveRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                if showsDropTarget {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.amgiAccent, lineWidth: 2)
                        .padding(.vertical, 2)
                }
            }
            .onDrag {
                draggedDeckID = node.id
                return NSItemProvider(object: NSString(string: String(node.id)))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first, let sourceID = Int64(item) else {
                    draggedDeckID = nil
                    return false
                }
                guard canAcceptDrop(sourceID, node.id) else {
                    draggedDeckID = nil
                    return false
                }
                onMoveRequested(sourceID, node.id)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .disabled(!isCollectionReady || isMovingDeck)
    }

    private var showsDropTarget: Bool {
        guard isDropTargeted, let sourceID = draggedDeckID else { return false }
        return canAcceptDrop(sourceID, node.id)
    }

    private var childrenList: some View {
        ForEach(node.children) { child in
            DeckRowView(
                node: child,
                depth: depth + 1,
                isCollectionReady: isCollectionReady,
                draggedDeckID: $draggedDeckID,
                isMovingDeck: isMovingDeck,
                canAcceptDrop: canAcceptDrop,
                onDeckChanged: onDeckChanged,
                onDeleteRequested: onDeleteRequested,
                onExportRequested: onExportRequested,
                onMoveRequested: onMoveRequested
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

    @ViewBuilder
    private var swipeButtons: some View {
        Button {
            onExportRequested(node)
        } label: {
            Label(L("deck_row_export"), systemImage: "square.and.arrow.up")
        }
        .tint(Color.amgiPositive)
        .disabled(!isCollectionReady)

        Button {
            renameText = node.fullName
            showRenamePrompt = true
        } label: {
            Label(L("deck_row_rename"), systemImage: "pencil")
        }
        .tint(Color.amgiAccent)
        .disabled(!isCollectionReady)

        Button(role: .destructive) {
            onDeleteRequested(node)
        } label: {
            Label(L("deck_row_delete"), systemImage: "trash")
        }
        .disabled(!isCollectionReady)
    }
}
