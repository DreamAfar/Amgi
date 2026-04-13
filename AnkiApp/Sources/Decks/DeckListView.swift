import SwiftUI
import AnkiKit
import AnkiBackend
import AnkiClients
import AnkiProto
import Dependencies

struct DeckListView: View {
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.deckClient) var deckClient
    @AppStorage(DeckListHeatmapSettings.showKey) private var showDeckListHeatmap = true
    @AppStorage(DeckListHeatmapSettings.scopeKey) private var heatmapScopeRaw = DeckListHeatmapScope.allDecks.rawValue
    @AppStorage(DeckListHeatmapSettings.selectedDeckIDKey) private var heatmapSelectedDeckID = DeckListHeatmapSettings.defaultSelectedDeckID

    @State private var tree: [DeckTreeNode] = []
    @State private var isLoading = true
    @State private var deckToDelete: DeckTreeNode?
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var heatmapRefreshID = 0
    var onDeckChanged: (() -> Void)? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 0) {
                    if showDeckListHeatmap && !tree.isEmpty {
                        DeckListHeatmapCard(refreshID: heatmapRefreshID)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }

                    if tree.isEmpty {
                        ContentUnavailableView(
                            L("deck_list_empty_title"),
                            systemImage: "rectangle.stack",
                            description: Text(L("deck_list_empty_desc"))
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(tree) { node in
                                DeckRowView(
                                    node: node,
                                    depth: 0,
                                    onDeckChanged: {
                                        Task { await loadDecks() }
                                        refreshHeatmap()
                                        onDeckChanged?()
                                    },
                                    onDeleteRequested: { node in
                                        deckToDelete = node
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                        }
                        .refreshable {
                            await loadDecks()
                            refreshHeatmap()
                        }
                    }
                }
                .navigationDestination(for: DeckInfo.self) { deck in
                    DeckDetailView(deck: deck)
                }
            }
        }
        .navigationTitle(L("deck_list_nav_title"))
        .onAppear {
            refreshHeatmap()
        }
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
        .task {
            await loadDecks()
            refreshHeatmap()
        }
    }

    private func loadDecks() async {
        do {
            tree = try deckClient.fetchTree()
        } catch {
            print("[DeckListView] Error loading decks: \(error)")
            tree = []
        }
        isLoading = false
    }

    private func deleteDeck() async {
        guard let node = deckToDelete else { return }
        do {
            try deckClient.delete(node.id)
            clearDeletedHeatmapSelection(ifNeeded: node.id)

            do {
                try cleanupUnusedMedia()
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
        guard showDeckListHeatmap else { return }
        heatmapRefreshID += 1
    }

    private func clearDeletedHeatmapSelection(ifNeeded deletedDeckID: Int64) {
        let scope = DeckListHeatmapScope(rawValue: heatmapScopeRaw) ?? .allDecks
        guard scope == .selectedDeck, Int64(heatmapSelectedDeckID) == deletedDeckID else { return }
        heatmapScopeRaw = DeckListHeatmapScope.allDecks.rawValue
        heatmapSelectedDeckID = DeckListHeatmapSettings.defaultSelectedDeckID
    }

    private func cleanupUnusedMedia() throws {
        let response: Anki_Media_CheckMediaResponse = try backend.invoke(
            service: AnkiBackend.Service.media,
            method: AnkiBackend.MediaMethod.checkMedia
        )

        if !response.unused.isEmpty {
            var request = Anki_Media_TrashMediaFilesRequest()
            request.fnames = response.unused
            try backend.callVoid(
                service: AnkiBackend.Service.media,
                method: AnkiBackend.MediaMethod.trashMediaFiles,
                request: request
            )
        }

        if response.haveTrash || !response.unused.isEmpty {
            try backend.callVoid(
                service: AnkiBackend.Service.media,
                method: AnkiBackend.MediaMethod.emptyTrash
            )
        }
    }
}

// MARK: - DeckRowView

private struct DeckRowView: View {
    @Dependency(\.deckClient) var deckClient
    let node: DeckTreeNode
    let depth: Int
    let onDeckChanged: () -> Void
    let onDeleteRequested: (DeckTreeNode) -> Void

    @State private var showRenamePrompt = false
    @State private var renameText = ""
    @State private var actionError: String?
    @State private var showActionError = false

    var body: some View {
        deckContent
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

        Button {
            renameText = node.name
            showRenamePrompt = true
        } label: {
            Label(L("deck_row_rename"), systemImage: "pencil")
        }
        .tint(.blue)
    }

    private var childrenList: some View {
        ForEach(node.children) { child in
            DeckRowView(
                node: child,
                depth: depth + 1,
                onDeckChanged: onDeckChanged,
                onDeleteRequested: onDeleteRequested
            )
        }
    }

    private var rowContent: some View {
        HStack {
            Text(node.name)
            Spacer()
            DeckCountsView(counts: node.counts)
        }
    }

    private var deckInfo: DeckInfo {
        DeckInfo(id: node.id, name: node.fullName, counts: node.counts)
    }

    private func renameDeck() async {
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
