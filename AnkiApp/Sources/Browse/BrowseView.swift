import SwiftUI
import AnkiKit
import AnkiClients
import Dependencies

struct BrowseView: View {
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.cardClient) var cardClient
    @Environment(\.editMode) private var editMode

    @State private var searchText = ""
    @State private var allNotes: [NoteRecord] = []
    @State private var notes: [NoteRecord] = []
    @State private var allDecks: [DeckInfo] = []
    /// The top-level parent deck selected (stays set even when drilling into subdecks)
    @State private var parentDeck: DeckInfo?
    /// The actual deck filter applied (could be parent or a subdeck)
    @State private var activeDeck: DeckInfo?
    @State private var isLoading = false
    @State private var hasMorePages = true
    @State private var showAddNote = false
    @State private var selectedNoteForDelete: NoteRecord?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showTagsManager = false
    @State private var selectedNoteIDs = Set<Int64>()
    @State private var isBatchWorking = false
    @State private var batchErrorMessage: String?
    @State private var showBatchError = false

    private let pageSize = 50

    var body: some View {
        Group {
            if notes.isEmpty && !isLoading && searchText.isEmpty && activeDeck == nil {
                ContentUnavailableView(
                    "Browse Notes",
                    systemImage: "magnifyingglass",
                    description: Text("Search by content, tags, or filter by deck.")
                )
            } else if notes.isEmpty && !isLoading {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selectedNoteIDs) {
                    ForEach(notes, id: \.id) { note in
                        if isEditing {
                            NoteRowView(note: note)
                                .tag(note.id)
                                .onAppear {
                                    if note.sfld == "Loading..." {
                                        Task { await fetchNoteDetails(id: note.id) }
                                    }
                                    if note.id == notes.last?.id {
                                        Task { await loadNextPage() }
                                    }
                                }
                        } else {
                            NavigationLink(value: note) {
                                NoteRowView(note: note)
                                    .onAppear {
                                        if note.sfld == "Loading..." {
                                            Task { await fetchNoteDetails(id: note.id) }
                                        }
                                        if note.id == notes.last?.id {
                                            Task { await loadNextPage() }
                                        }
                                    }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    selectedNoteForDelete = note
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .navigationDestination(for: NoteRecord.self) { note in
                    let resolvedNote = (note.sfld == "Loading...")
                        ? (try? noteClient.fetch(note.id)) ?? note
                        : note
                    NoteEditorView(note: resolvedNote) {
                        Task { await performSearch() }
                    }
                }
            }
        }
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showAddNote = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()

                Button {
                    showTagsManager = true
                } label: {
                    Image(systemName: "tag")
                }

                if !selectedNoteIDs.isEmpty {
                    Menu {
                        Menu("批量标记") {
                            Button("旗标1（红）") { Task { await batchFlag(1) } }
                            Button("旗标2（橙）") { Task { await batchFlag(2) } }
                            Button("旗标3（绿）") { Task { await batchFlag(3) } }
                            Button("旗标4（蓝）") { Task { await batchFlag(4) } }
                            Button("旗标5（粉）") { Task { await batchFlag(5) } }
                            Button("旗标6（青）") { Task { await batchFlag(6) } }
                            Button("旗标7（紫）") { Task { await batchFlag(7) } }
                        }

                        Button("批量暂停") { Task { await batchSuspend() } }
                        Button("批量搁置") { Task { await batchBury() } }
                        Divider()
                        Button("清空选择", role: .cancel) { selectedNoteIDs.removeAll() }
                    } label: {
                        Image(systemName: isBatchWorking ? "hourglass" : "ellipsis.circle")
                    }
                    .disabled(isBatchWorking)
                }

                if !notes.isEmpty {
                    Text("\(allNotes.count) notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView {
                Task { await performSearch() }
            }
        }
        .sheet(isPresented: $showTagsManager) {
            TagsView()
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let note = selectedNoteForDelete {
                    Task { await deleteNote(note) }
                }
            }
        } message: {
            if let note = selectedNoteForDelete {
                Text("Are you sure you want to delete '\(note.sfld)'?")
            }
        }
        .alert("批量操作失败", isPresented: $showBatchError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(batchErrorMessage ?? "未知错误")
        }
        .safeAreaInset(edge: .top) {
            if !allDecks.isEmpty {
                deckFilterBar
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes...")
        .onChange(of: searchText) {
            Task { await performSearch() }
        }
        .onChange(of: activeDeck) {
            Task { await performSearch() }
        }
        .task {
            await loadDecks()
            await performSearch()
        }
    }

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

                List(selection: $selectedNoteIDs) {

    private var topLevelDecks: [DeckInfo] {
        allDecks.filter { !$0.name.contains("::") }
    }

    /// Direct children of the parent deck (shown as second row)
    private var childDecks: [DeckInfo] {
        guard let parent = parentDeck else { return [] }
        let prefix = parent.name + "::"
        return allDecks.filter { deck in
            guard deck.name.hasPrefix(prefix) else { return false }
            let remainder = deck.name.dropFirst(prefix.count)
            return !remainder.contains("::")
        }
    }

    private var deckFilterBar: some View {
        VStack(spacing: 0) {
            // Top-level deck chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipButton(label: "All", isSelected: activeDeck == nil) {
                        parentDeck = nil
                        activeDeck = nil
                    }
                    ForEach(topLevelDecks) { deck in
                        chipButton(
                            label: deck.name,
                            isSelected: parentDeck?.id == deck.id && activeDeck?.id == deck.id
                        ) {
                            parentDeck = deck
                            activeDeck = deck
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Subdeck row — stays visible as long as a parent with children is selected
            if !childDecks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" chip = parent deck (includes subdecks)
                        chipButton(
                            label: "All",
                            isSelected: activeDeck?.id == parentDeck?.id,
                            small: true
                        ) {
                            activeDeck = parentDeck
                        }
                        ForEach(childDecks) { child in
                            chipButton(
                                label: shortName(child.name),
                                isSelected: activeDeck?.id == child.id,
                                small: true
                            ) {
                                activeDeck = child
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(.bar)
    }

    private func chipButton(
        label: String,
        isSelected: Bool,
        small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(small ? .caption : .subheadline)
                .padding(.horizontal, small ? 10 : 12)
                .padding(.vertical, small ? 4 : 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func shortName(_ fullName: String) -> String {
        String(fullName.split(separator: "::").last ?? Substring(fullName))
    }

    // MARK: - Data Loading

    private func loadDecks() async {
        do {
            allDecks = try deckClient.fetchAll()
        } catch {
            allDecks = []
        }
    }

    private func deleteNote(_ note: NoteRecord) async {
        isDeleting = true
        defer { isDeleting = false }
        
        do {
            try noteClient.delete(note.id)
            selectedNoteForDelete = nil
            await performSearch()
        } catch {
            selectedNoteForDelete = nil
            print("[Browse] Failed to delete note: \(error)")
        }
    }

    private func performSearch() async {
        isLoading = true
        let query = buildQuery()
        do {
            let results = try noteClient.search(query, nil)
            allNotes = results
            notes = Array(results.prefix(pageSize))
            hasMorePages = results.count > pageSize
        } catch {
            allNotes = []
            notes = []
            hasMorePages = false
        }
        isLoading = false
    }

    private func loadNextPage() async {
        guard hasMorePages, !isLoading else { return }
        let loaded = notes.count
        let nextBatch = Array(allNotes.dropFirst(loaded).prefix(pageSize))
        notes.append(contentsOf: nextBatch)
        hasMorePages = notes.count < allNotes.count
    }

    /// Lazy-fetch full note details for a stub and update the arrays in place.
    private func fetchNoteDetails(id: Int64) async {
        guard let fullNote = try? noteClient.fetch(id) else { return }
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            notes[idx] = fullNote
        }
        if let idx = allNotes.firstIndex(where: { $0.id == id }) {
            allNotes[idx] = fullNote
        }
    }

    private func buildQuery() -> String {
        var parts: [String] = []
        if let deck = activeDeck {
            parts.append("deck:\"\(deck.name)\"")
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: " ")
    }

    private func batchFlag(_ flag: Int32) async {
        await performBatchAction { cardId in
            try cardClient.flag(cardId, flag)
        }
    }

    private func batchSuspend() async {
        await performBatchAction { cardId in
            try cardClient.suspend(cardId)
        }
    }

    private func batchBury() async {
        await performBatchAction { cardId in
            try cardClient.bury(cardId)
        }
    }

    private func performBatchAction(_ action: (Int64) throws -> Void) async {
        guard !selectedNoteIDs.isEmpty else { return }
        isBatchWorking = true
        defer { isBatchWorking = false }

        do {
            var allCardIDs = Set<Int64>()
            for noteId in selectedNoteIDs {
                let cards = try cardClient.fetchByNote(noteId)
                for card in cards {
                    allCardIDs.insert(card.id)
                }
            }

            for cardId in allCardIDs {
                try action(cardId)
            }

            selectedNoteIDs.removeAll()
            await performSearch()
        } catch {
            batchErrorMessage = error.localizedDescription
            showBatchError = true
        }
    }
}

// MARK: - NoteRowView

struct NoteRowView: View {
    let note: NoteRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.sfld)
                .font(.body)
                .lineLimit(1)
            if !note.tags.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(note.tags.trimmingCharacters(in: .whitespaces))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
