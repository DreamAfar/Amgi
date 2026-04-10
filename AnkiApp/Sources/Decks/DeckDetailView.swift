import SwiftUI
import AnkiKit
import AnkiClients
import Dependencies

struct DeckDetailView: View {
    let deck: DeckInfo
    @Dependency(\.deckClient) var deckClient
    @State private var counts: DeckCounts = .zero
    @State private var childDecks: [DeckTreeNode] = []
    @State private var showReview = false
    @State private var showConfig = false
    @State private var showTemplatePicker = false
    @State private var selectedChildDeck: DeckTreeNode?
    @State private var renameText = ""
    @State private var showRenamePrompt = false
    @State private var showDeleteConfirm = false
    @State private var actionError: String?
    @State private var showActionError = false

    private var shortTitle: String {
        String(deck.name.split(separator: "::", omittingEmptySubsequences: true).last ?? Substring(deck.name))
    }

    var body: some View {
        List {
            countsSection
            studySection

            if !childDecks.isEmpty {
                subdecksSection
            }
        }
        .navigationTitle(shortTitle)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showTemplatePicker = true
                } label: {
                    Image(systemName: "square.on.square")
                }
                .accessibilityLabel(L("card_info_template"))

                Button(action: { showConfig = true }) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(L("deck_detail_config"))
            }
        }
        .sheet(isPresented: $showConfig) {
            DeckConfigView(deckId: deck.id) {
                showConfig = false
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            DeckTemplateListView()
        }
        .fullScreenCover(isPresented: $showReview) {
            ReviewView(deckId: deck.id) {
                showReview = false
                Task { await loadCounts() }
            }
        }
        .alert(L("deck_rename_alert_title"), isPresented: $showRenamePrompt) {
            TextField(L("deck_rename_alert_placeholder"), text: $renameText)
            Button(L("btn_cancel"), role: .cancel) {}
            Button(L("btn_save")) {
                Task { await renameChildDeck() }
            }
        } message: {
            Text(L("deck_rename_alert_message"))
        }
        .confirmationDialog(
            L("deck_delete_confirm2_title"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L("btn_confirm_delete"), role: .destructive) {
                Task { await deleteChildDeck() }
            }
            Button(L("btn_cancel"), role: .cancel) {}
        } message: {
            Text(L("deck_delete_confirm2_message", selectedChildDeck?.name ?? ""))
        }
        .alert(L("deck_action_error_title"), isPresented: $showActionError) {
            Button(L("btn_got_it"), role: .cancel) {}
        } message: {
            Text(actionError ?? L("label_error_unknown"))
        }
        .task {
            await loadCounts()
            await loadChildren()
        }
    }

    // MARK: - Extracted Sub-Views

    private var countsSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    Text(L("deck_detail_count_new"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(counts.newCount)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(L("deck_detail_count_learning"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(counts.learnCount)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(L("deck_detail_count_review"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(counts.reviewCount)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var studySection: some View {
        Section {
            Button {
                showReview = true
            } label: {
                Label(L("deck_detail_study_now"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
            .disabled(counts.total == 0)
        }
    }

    private var subdecksSection: some View {
        Section(L("deck_detail_subdecks")) {
            ForEach(childDecks) { child in
                NavigationLink(value: DeckInfo(id: child.id, name: child.fullName, counts: child.counts)) {
                    HStack {
                        Text(child.name)
                        Spacer()
                        DeckCountsView(counts: child.counts)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        selectedChildDeck = child
                        renameText = child.name
                        showRenamePrompt = true
                    } label: {
                        Label(L("deck_row_rename"), systemImage: "pencil")
                    }
                    .tint(.blue)

                    Button(role: .destructive) {
                        selectedChildDeck = child
                        showDeleteConfirm = true
                    } label: {
                        Label(L("deck_row_delete"), systemImage: "trash")
                    }
                }
            }
        }
    }

    private func loadCounts() async {
        do {
            counts = try deckClient.countsForDeck(deck.id)
            print("[DeckDetail] Counts for '\(deck.name)' (\(deck.id)): new=\(counts.newCount), learn=\(counts.learnCount), review=\(counts.reviewCount)")
        } catch {
            print("[DeckDetail] Error loading counts for '\(deck.name)': \(error)")
            counts = .zero
        }
    }

    private func loadChildren() async {
        do {
            let tree = try deckClient.fetchTree()
            childDecks = findChildren(in: tree, parentId: deck.id)
        } catch {
            childDecks = []
        }
    }

    private func findChildren(in nodes: [DeckTreeNode], parentId: Int64) -> [DeckTreeNode] {
        for node in nodes {
            if node.id == parentId { return node.children }
            let found = findChildren(in: node.children, parentId: parentId)
            if !found.isEmpty { return found }
        }
        return []
    }

    private func renameChildDeck() async {
        guard let child = selectedChildDeck else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try deckClient.rename(child.id, trimmed)
            await loadChildren()
            await loadCounts()
        } catch {
            actionError = error.localizedDescription
            showActionError = true
        }
    }

    private func deleteChildDeck() async {
        guard let child = selectedChildDeck else { return }
        do {
            try deckClient.delete(child.id)
            selectedChildDeck = nil
            await loadChildren()
            await loadCounts()
        } catch {
            actionError = error.localizedDescription
            showActionError = true
        }
    }
}
