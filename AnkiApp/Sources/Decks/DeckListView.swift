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
                    "No Decks",
                    systemImage: "rectangle.stack",
                    description: Text("Sync with your server to get your decks.")
                )
            } else {
                List {
                    ForEach(tree) { node in
                        DeckRowView(node: node, onDeckChanged: {
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
        .navigationTitle("Decks")
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
                NavigationLink(value: deckInfo) {
                    rowContent
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        renameText = node.name
                        showRenamePrompt = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        showDeleteConfirmStep1 = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } else {
                DisclosureGroup {
                    ForEach(node.children) { child in
                        DeckRowView(node: child, onDeckChanged: onDeckChanged)
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
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        showDeleteConfirmStep1 = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .alert("重命名牌组", isPresented: $showRenamePrompt) {
            TextField("新名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                Task { await renameDeck() }
            }
        } message: {
            Text("请输入新的牌组名称")
        }
        .alert("删除牌组（第1次确认）", isPresented: $showDeleteConfirmStep1) {
            Button("取消", role: .cancel) {}
            Button("继续") {
                showDeleteConfirmStep2 = true
            }
        } message: {
            Text("即将删除 \(node.name)，请再次确认。")
        }
        .alert("删除牌组（第2次确认）", isPresented: $showDeleteConfirmStep2) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                Task { await deleteDeck() }
            }
        } message: {
            Text("删除后不可恢复：\(node.name)")
        }
        .alert("操作失败", isPresented: $showActionError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(actionError ?? "未知错误")
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
