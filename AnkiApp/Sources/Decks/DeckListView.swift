import SwiftUI
import AnkiKit
import AnkiClients
import Dependencies

struct DeckListView: View {
    @Dependency(\.deckClient) var deckClient
    @State private var tree: [DeckTreeNode] = []
    @State private var isLoading = true
    var onDeckChanged: (() -> Void)? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if tree.isEmpty {
                ContentUnavailableView(
                    L("deck_list_empty_title"),
                    systemImage: "rectangle.stack",
                    description: Text(L("deck_list_empty_desc"))
                )
            } else {
                List {
                    ForEach(tree) { node in
                        DeckRowView(node: node, depth: 0, onDeckChanged: {
                            Task { await loadDecks() }
                            onDeckChanged?()
                        })
                    }
                }
                .navigationDestination(for: DeckInfo.self) { deck in
                    DeckDetailView(deck: deck)
                }
            }
        }
        .navigationTitle(L("deck_list_nav_title"))
        .task {
            await loadDecks()
        }
        .refreshable {
            await loadDecks()
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
}

// MARK: - DeckRowView

private struct DeckRowView: View {
    @Dependency(\.deckClient) var deckClient
    let node: DeckTreeNode
    let depth: Int
    let onDeckChanged: () -> Void

    @State private var showRenamePrompt = false
    @State private var showDeleteConfirmStep1 = false
    @State private var showDeleteConfirmStep2 = false
    @State private var renameText = ""
    @State private var actionError: String?
    @State private var showActionError = false

    var body: some View {
        Group {
            if node.children.isEmpty {
                if depth == 0 {
                    NavigationLink(value: deckInfo) {
                        rowContent
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            renameText = node.name
                            showRenamePrompt = true
                        } label: {
                            Label(L("deck_row_rename"), systemImage: "pencil")
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            showDeleteConfirmStep1 = true
                        } label: {
                            Label(L("deck_row_delete"), systemImage: "trash")
                        }
                    }
                } else {
                    NavigationLink(value: deckInfo) {
                        rowContent
                    }
                }
            } else {
                if depth == 0 {
                    DisclosureGroup {
                        ForEach(node.children) { child in
                            DeckRowView(node: child, depth: depth + 1, onDeckChanged: onDeckChanged)
                        }
                    } label: {
                        NavigationLink(value: deckInfo) {
                            rowContent
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            renameText = node.name
                            showRenamePrompt = true
                        } label: {
                            Label(L("deck_row_rename"), systemImage: "pencil")
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            showDeleteConfirmStep1 = true
                        } label: {
                            Label(L("deck_row_delete"), systemImage: "trash")
                        }
                    }
                } else {
                    DisclosureGroup {
                        ForEach(node.children) { child in
                            DeckRowView(node: child, depth: depth + 1, onDeckChanged: onDeckChanged)
                        }
                    } label: {
                        NavigationLink(value: deckInfo) {
                            rowContent
                        }
                    }
                }
            }
        }
        .alert(L("deck_rename_alert_title"), isPresented: $showRenamePrompt) {
            TextField(L("deck_rename_alert_placeholder"), text: $renameText)
            Button(L("btn_cancel"), role: .cancel) {}
            Button(L("btn_save")) {
                Task { await renameDeck() }
            }
        } message: {
            Text(L("deck_rename_alert_message"))
        }
        .alert(L("deck_delete_confirm1_title"), isPresented: $showDeleteConfirmStep1) {
            Button(L("btn_cancel"), role: .cancel) {}
            Button(L("btn_continue")) {
                showDeleteConfirmStep2 = true
            }
        } message: {
            Text(L("deck_delete_confirm1_message", node.name))
        }
        .alert(L("deck_delete_confirm2_title"), isPresented: $showDeleteConfirmStep2) {
            Button(L("btn_cancel"), role: .cancel) {}
            Button(L("btn_confirm_delete"), role: .destructive) {
                Task { await deleteDeck() }
            }
        } message: {
            Text(L("deck_delete_confirm2_message", node.name))
        }
        .alert(L("deck_action_error_title"), isPresented: $showActionError) {
            Button(L("btn_got_it"), role: .cancel) {}
        } message: {
            Text(actionError ?? L("label_error_unknown"))
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

    private func deleteDeck() async {
        do {
            try deckClient.delete(node.id)
            onDeckChanged()
        } catch {
            actionError = error.localizedDescription
            showActionError = true
        }
    }
}
