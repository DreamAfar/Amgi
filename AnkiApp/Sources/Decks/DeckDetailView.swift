import SwiftUI
import AnkiKit
import AnkiBackend
import AnkiClients
import Dependencies

struct DeckDetailView: View {
    let deck: DeckInfo
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.deckClient) var deckClient
    @State private var counts: DeckCounts = .zero
    @State private var childDecks: [DeckTreeNode] = []
    @State private var showReview = false
    @State private var showConfig = false
    @State private var showTemplateManager = false
    @State private var showAddNote = false
    @State private var showAddImageOcclusion = false
    @State private var selectedChildDeck: DeckTreeNode?
    @State private var renameText = ""
    @State private var showRenamePrompt = false
    @State private var showDeleteConfirm = false
    @State private var actionError: String?
    @State private var showActionError = false
    @State private var showStats = false
    @State private var showBrowse = false
    @State private var showAddSubdeck = false
    @State private var newSubdeckName = ""

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
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(shortTitle)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showBrowse = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel(L("deck_detail_browse"))

                Button {
                    showStats = true
                } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel(L("deck_detail_stats"))

                Menu {
                    Button {
                        showAddNote = true
                    } label: {
                        Label(L("browse_add_note"), systemImage: "note.text.badge.plus")
                    }

                    Button {
                        showAddImageOcclusion = true
                    } label: {
                        Label(L("browse_add_image_occlusion"), systemImage: "rectangle.dashed.badge.record")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L("browse_add_accessibility"))

                Menu {
                    Button {
                        newSubdeckName = ""
                        showAddSubdeck = true
                    } label: {
                        Label(L("deck_detail_add_subdeck"), systemImage: "rectangle.stack.badge.plus")
                    }

                    Button {
                        showTemplateManager = true
                    } label: {
                        Label(L("deck_template_nav_title"), systemImage: "square.on.square")
                    }

                    Button {
                        showConfig = true
                    } label: {
                        Label(L("deck_detail_config"), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView(
                onSave: {
                    Task { await loadCounts() }
                },
                preselectedDeckId: deck.id
            )
        }
        .sheet(isPresented: $showAddImageOcclusion) {
            AddImageOcclusionNoteView {
                Task { await loadCounts() }
            }
        }
        .sheet(isPresented: $showConfig) {
            DeckConfigView(deckId: deck.id) {
                showConfig = false
            }
        }
        .sheet(isPresented: $showTemplateManager) {
            NavigationStack {
                DeckTemplateListView()
            }
        }
        .fullScreenCover(isPresented: $showReview) {
            ReviewView(deckId: deck.id) {
                showReview = false
                Task { await loadCounts() }
            }
        }
        .sheet(isPresented: $showStats) {
            NavigationStack {
                StatsDashboardView(initialDeckID: deck.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L("common_done")) { showStats = false }
                                .amgiToolbarTextButton(tone: .neutral)
                        }
                    }
            }
        }
        .sheet(isPresented: $showBrowse) {
            NavigationStack {
                BrowseView(preselectedDeck: deck)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L("common_done")) { showBrowse = false }
                                .amgiToolbarTextButton(tone: .neutral)
                        }
                    }
            }
        }
        .alert(L("deck_detail_add_subdeck"), isPresented: $showAddSubdeck) {
            TextField(L("deck_detail_add_subdeck_placeholder"), text: $newSubdeckName)
                .autocorrectionDisabled()
            Button(L("btn_cancel"), role: .cancel) {}
            Button(L("btn_save")) {
                Task { await createSubdeck() }
            }
        } message: {
            Text(L("deck_detail_add_subdeck_message"))
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
        .alert(
            L("deck_delete_confirm2_title"),
            isPresented: $showDeleteConfirm
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
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                    Text("\(counts.newCount)")
                        .amgiStatusText(.accent, font: .sectionHeading)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(L("deck_detail_count_learning"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                    Text("\(counts.learnCount)")
                        .amgiStatusText(.warning, font: .sectionHeading)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text(L("deck_detail_count_review"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                    Text("\(counts.reviewCount)")
                        .amgiStatusText(.positive, font: .sectionHeading)
                }
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.amgiSurfaceElevated)
        }
    }

    private var studySection: some View {
        Section {
            Button {
                showReview = true
            } label: {
                Label(L("deck_detail_study_now"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .amgiFont(.bodyEmphasis)
            }
            .foregroundStyle(Color.amgiAccent)
            .disabled(counts.total == 0)
            .listRowBackground(Color.amgiSurfaceElevated)
        }
    }

    private var subdecksSection: some View {
        Section(L("deck_detail_subdecks")) {
            ForEach(childDecks) { child in
                NavigationLink(value: DeckInfo(id: child.id, name: child.fullName, counts: child.counts)) {
                    HStack {
                        Text(child.name)
                            .amgiFont(.body)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Spacer()
                        DeckCountsView(counts: child.counts)
                    }
                }
                .listRowBackground(Color.amgiSurfaceElevated)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        selectedChildDeck = child
                        showDeleteConfirm = true
                    } label: {
                        Label(L("deck_row_delete"), systemImage: "trash")
                    }

                    Button {
                        selectedChildDeck = child
                        renameText = child.name
                        showRenamePrompt = true
                    } label: {
                        Label(L("deck_row_rename"), systemImage: "pencil")
                    }
                    .tint(Color.amgiAccent)
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
            DeckDeletionMaintenance.resetHeatmapSelectionIfNeeded(deletedDeckID: child.id)

            do {
                try DeckDeletionMaintenance.cleanupUnusedMedia(using: backend)
            } catch {
                print("[DeckDetailView] Media cleanup after deck deletion failed: \(error)")
            }

            selectedChildDeck = nil
            await loadChildren()
            await loadCounts()
        } catch {
            actionError = error.localizedDescription
            showActionError = true
        }
    }

    private func createSubdeck() async {
        let trimmed = newSubdeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fullName = "\(deck.name)::\(trimmed)"
        do {
            _ = try deckClient.create(fullName)
            await loadChildren()
        } catch {
            actionError = error.localizedDescription
            showActionError = true
        }
    }
}
