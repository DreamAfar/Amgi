import SwiftUI
import AnkiKit
import AnkiClients
import Dependencies

struct BrowseView: View {
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.tagClient) var tagClient
    @Environment(\.editMode) private var editMode

    @State private var searchText = ""
    @State private var allNotes: [NoteRecord] = []
    @State private var notes: [NoteRecord] = []
    @State private var allDecks: [DeckInfo] = []
    /// The top-level parent deck selected (stays set even when drilling into subdecks)
    @State private var parentDeck: DeckInfo?
    /// The actual deck filter applied (could be parent or a subdeck)
    @State private var activeDeck: DeckInfo?
    @State private var allTags: [String] = []
    @State private var activeTag: String?
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
    @State private var batchSuccessMessage: String?
    @State private var showBatchSuccess = false
    @State private var batchProgressDone = 0
    @State private var batchProgressTotal = 0

    private let pageSize = 50

    var body: some View {
        Group {
            if notes.isEmpty && !isLoading && searchText.isEmpty && activeDeck == nil {
                ContentUnavailableView(
                    L("browse_nav_title"),
                    systemImage: "magnifyingglass",
                    description: Text(L("browse_empty_desc"))
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
                                    Label(L("common_delete"), systemImage: "trash")
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

            if isBatchWorking {
                HStack(spacing: 8) {
                    ProgressView(value: Double(batchProgressDone), total: Double(max(batchProgressTotal, 1)))
                        .frame(maxWidth: 160)
                    Text("\(batchProgressDone)/\(batchProgressTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
        }
        .navigationTitle(L("browse_nav_title"))
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

                if !selectedNoteIDs.isEmpty {
                    Menu {
                        Button {
                            showTagsManager = true
                        } label: {
                            Label(L("browse_tag_manage"), systemImage: "tag")
                        }

                        Divider()

                        Menu(L("browse_batch_flags")) {
                            Button(L("browse_flag_1")) { Task { await batchFlag(1) } }
                            Button(L("browse_flag_2")) { Task { await batchFlag(2) } }
                            Button(L("browse_flag_3")) { Task { await batchFlag(3) } }
                            Button(L("browse_flag_4")) { Task { await batchFlag(4) } }
                            Button(L("browse_flag_5")) { Task { await batchFlag(5) } }
                            Button(L("browse_flag_6")) { Task { await batchFlag(6) } }
                            Button(L("browse_flag_7")) { Task { await batchFlag(7) } }
                            Divider()
                            Button(L("browse_flag_clear")) { Task { await batchFlag(0) } }
                        }

                        Button(L("browse_batch_suspend")) { Task { await batchSuspend() } }
                        Button(L("browse_batch_bury")) { Task { await batchBury() } }
                        Divider()
                        Button(L("browse_batch_clear_selection"), role: .cancel) { selectedNoteIDs.removeAll() }
                    } label: {
                        Image(systemName: isBatchWorking ? "hourglass" : "ellipsis.circle")
                    }
                    .disabled(isBatchWorking)
                }

                if !notes.isEmpty {
                    Text(L("browse_note_count", allNotes.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Text(L("browse_selected_count", selectedNoteIDs.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(L("browse_select_page")) {
                        selectAllVisibleNotes()
                    }
                    .disabled(notes.isEmpty)

                    Button(L("browse_select_filtered")) {
                        selectAllFilteredNotes()
                    }
                    .disabled(allNotes.isEmpty)

                    Button(L("browse_select_clear")) {
                        selectedNoteIDs.removeAll()
                    }
                    .disabled(selectedNoteIDs.isEmpty)

                    Menu {
                        Button {
                            showTagsManager = true
                        } label: {
                            Label(L("browse_batch_manage_tags"), systemImage: "tag")
                        }

                        Divider()

                        Menu(L("browse_batch_flag_menu")) {
                            Button(L("browse_batch_flag_1")) { Task { await batchFlag(1) } }
                            Button(L("browse_batch_flag_2")) { Task { await batchFlag(2) } }
                            Button(L("browse_batch_flag_3")) { Task { await batchFlag(3) } }
                            Button(L("browse_batch_flag_4")) { Task { await batchFlag(4) } }
                            Button(L("browse_batch_flag_5")) { Task { await batchFlag(5) } }
                            Button(L("browse_batch_flag_6")) { Task { await batchFlag(6) } }
                            Button(L("browse_batch_flag_7")) { Task { await batchFlag(7) } }
                            Divider()
                            Button(L("browse_batch_flag_clear")) { Task { await batchFlag(0) } }
                        }

                        Button(L("browse_batch_suspend")) { Task { await batchSuspend() } }
                        Button(L("browse_batch_bury")) { Task { await batchBury() } }
                    } label: {
                        if isBatchWorking {
                            ProgressView()
                        } else {
                            Label(L("browse_batch_menu_label"), systemImage: "slider.horizontal.3")
                        }
                    }
                    .disabled(selectedNoteIDs.isEmpty || isBatchWorking)
                }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView {
                Task { await performSearch() }
            }
        }
        .sheet(isPresented: $showTagsManager, onDismiss: {
            Task {
                await loadTags()
                await performSearch()
            }
        }) {
            TagsView(targetNoteIDs: Array(selectedNoteIDs))
        }
        .alert(L("browse_delete_title"), isPresented: $showDeleteConfirm) {
            Button(L("common_cancel"), role: .cancel) { }
            Button(L("common_delete"), role: .destructive) {
                if let note = selectedNoteForDelete {
                    Task { await deleteNote(note) }
                }
            }
        } message: {
            if let note = selectedNoteForDelete {
                Text(L("browse_delete_confirm", note.sfld))
            }
        }
        .alert(L("browse_batch_failed_title"), isPresented: $showBatchError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(batchErrorMessage ?? L("common_unknown_error"))
        }
        .alert(L("browse_batch_success_title"), isPresented: $showBatchSuccess) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(batchSuccessMessage ?? L("common_completed"))
        }
        .safeAreaInset(edge: .top) {
            if !allDecks.isEmpty || !allTags.isEmpty {
                deckFilterBar
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("browse_search_placeholder"))
        .onChange(of: searchText) {
            Task { await performSearch() }
        }
        .onChange(of: activeDeck) {
            Task { await performSearch() }
        }
        .onChange(of: activeTag) {
            Task { await performSearch() }
        }
        .task {
            await loadDecks()
            await loadTags()
            await performSearch()
        }
    }

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

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
                    chipButton(label: L("browse_filter_all"), isSelected: activeDeck == nil) {
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
                            label: L("browse_filter_all"),
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

            // Tag row
            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chipButton(
                            label: L("browse_filter_all"),
                            isSelected: activeTag == nil,
                            small: true
                        ) {
                            activeTag = nil
                        }

                        ForEach(allTags, id: \.self) { tag in
                            chipButton(
                                label: shortTagName(tag),
                                isSelected: activeTag == tag,
                                small: true
                            ) {
                                activeTag = tag
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

    private func loadTags() async {
        do {
            allTags = try tagClient.getAllTags().sorted()
            if let activeTag, !allTags.contains(activeTag) {
                self.activeTag = nil
            }
        } catch {
            allTags = []
            activeTag = nil
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
        if let activeTag {
            parts.append("tag:\"\(activeTag)\"")
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: " ")
    }

    private func batchFlag(_ flag: UInt32) async {
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
        defer {
            isBatchWorking = false
            batchProgressDone = 0
            batchProgressTotal = 0
        }
        let selectedNotesCount = selectedNoteIDs.count

        do {
            var allCardIDs = Set<Int64>()
            for noteId in selectedNoteIDs {
                let cards = try cardClient.fetchByNote(noteId)
                for card in cards {
                    allCardIDs.insert(card.id)
                }
            }

            batchProgressDone = 0
            batchProgressTotal = allCardIDs.count

            for cardId in allCardIDs {
                try action(cardId)
                batchProgressDone += 1
            }

            if allCardIDs.isEmpty {
                batchErrorMessage = L("browse_batch_no_cards")
                showBatchError = true
                return
            }

            selectedNoteIDs.removeAll()
            batchSuccessMessage = L("browse_batch_processed", allCardIDs.count, selectedNotesCount)
            showBatchSuccess = true
            await performSearch()
        } catch {
            batchErrorMessage = error.localizedDescription
            showBatchError = true
        }
    }

    private func selectAllVisibleNotes() {
        selectedNoteIDs = Set(notes.map(\.id))
    }

    private func selectAllFilteredNotes() {
        selectedNoteIDs = Set(allNotes.map(\.id))
    }
}

// MARK: - NoteRowView

struct NoteRowView: View {
    let note: NoteRecord

    private var tagList: [String] {
        note.tags
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var modifiedDateString: String {
        guard note.mod > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(note.mod))
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L("common_today") }
        if cal.isDateInYesterday(date) { return L("common_yesterday") }
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateStyle = .short
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(note.sfld == "Loading..." ? L("common_loading") : note.sfld)
                    .font(.body)
                    .lineLimit(2)
                    .redacted(reason: note.sfld == "Loading..." ? .placeholder : [])
                Spacer(minLength: 4)
                if !modifiedDateString.isEmpty && note.sfld != "Loading..." {
                    Text(modifiedDateString)
                        .font(.caption2)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }

            if !tagList.isEmpty && note.sfld != "Loading..." {
                let displayTags = Array(tagList.prefix(3))
                let extra = tagList.count - displayTags.count
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(displayTags, id: \.self) { tag in
                            Text(shortTagName(tag))
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        if extra > 0 {
                            Text("+\(extra)")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(.secondarySystemFill))
                                .foregroundStyle(Color(.secondaryLabel))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func shortTagName(_ tag: String) -> String {
        // Show only the last component of a hierarchical tag (e.g. "日语::词汇" → "词汇")
        String(tag.split(separator: "::").last ?? Substring(tag))
    }
}
