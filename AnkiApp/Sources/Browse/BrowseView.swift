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
    @State private var quickFilter: BrowseQuickFilter = .all
    @State private var sortMode: BrowseSortMode = .modifiedDesc
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
                noteListContent
            }

            if isBatchWorking {
                batchProgressOverlay
            }
        }
        .navigationTitle(L("browse_toolbar_title_count", allNotes.count))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showTagsManager = true
                } label: {
                    Text(L("tags_nav_title"))
                }
                .accessibilityLabel(L("tags_nav_title"))
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                trailingToolbarButtons
            }

            if isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    batchBottomBar
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
        .onChange(of: quickFilter) {
            Task { await performSearch() }
        }
        .task {
            await loadDecks()
            await loadTags()
            await performSearch()
        }
    }

    // MARK: - Extracted Sub-Views

    private var noteListContent: some View {
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

    private var batchProgressOverlay: some View {
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

    private var filterMenu: some View {
        Menu {
            ForEach(BrowseQuickFilter.allCases, id: \.self) { filter in
                Button {
                    quickFilter = filter
                } label: {
                    if quickFilter == filter {
                        Label(filter.title, systemImage: "checkmark.circle.fill")
                    } else {
                        Label(filter.title, systemImage: filter.symbol)
                    }
                }
            }

            if !allDecks.isEmpty {
                Divider()
                Menu(L("browse_filter_by_deck")) {
                    Button {
                        parentDeck = nil
                        activeDeck = nil
                    } label: {
                        if activeDeck == nil {
                            Label(L("browse_filter_all"), systemImage: "checkmark")
                        } else {
                            Text(L("browse_filter_all"))
                        }
                    }

                    ForEach(allDecks) { deck in
                        Button {
                            parentDeck = topLevelDecks.first(where: { deck.name.hasPrefix($0.name) })
                            activeDeck = deck
                        } label: {
                            if activeDeck?.id == deck.id {
                                Label(deck.name, systemImage: "checkmark.circle.fill")
                            } else {
                                Label(deck.name, systemImage: "rectangle.stack")
                            }
                        }
                    }
                }
            }

            if !allTags.isEmpty {
                Menu(L("browse_filter_by_tag")) {
                    Button {
                        activeTag = nil
                    } label: {
                        if activeTag == nil {
                            Label(L("browse_filter_all"), systemImage: "checkmark")
                        } else {
                            Text(L("browse_filter_all"))
                        }
                    }

                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            activeTag = tag
                        } label: {
                            if activeTag == tag {
                                Label(shortTagName(tag), systemImage: "checkmark.circle.fill")
                            } else {
                                Label(shortTagName(tag), systemImage: "tag")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(L("browse_filter_accessibility"))
    }

    @ViewBuilder
    private var trailingToolbarButtons: some View {
        Button {
            withAnimation {
                editMode?.wrappedValue = isEditing ? .inactive : .active
            }
        } label: {
            Image(systemName: isEditing ? "checkmark.circle" : "checklist")
        }
        .accessibilityLabel(L("browse_multiselect_accessibility"))

        Menu {
            ForEach(BrowseSortMode.allCases, id: \.self) { mode in
                Button {
                    sortMode = mode
                    applySort()
                } label: {
                    if sortMode == mode {
                        Label(mode.title, systemImage: "checkmark.circle.fill")
                    } else {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .accessibilityLabel(L("browse_sort_accessibility"))

        Button {
            showAddNote = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(L("browse_add_accessibility"))
    }

    @ViewBuilder
    private var batchBottomBar: some View {
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
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func shortName(_ fullName: String) -> String {
        String(fullName.split(separator: "::").last ?? Substring(fullName))
    }

    private func shortTagName(_ tag: String) -> String {
        // Show only the last component of a hierarchical tag (e.g. "日语::词汇" → "词汇")
        String(tag.split(separator: "::").last ?? Substring(tag))
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
            allNotes = sortNotes(results)
            notes = Array(allNotes.prefix(pageSize))
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
        if !quickFilter.query.isEmpty {
            parts.append(quickFilter.query)
        }
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

    private func sortNotes(_ input: [NoteRecord]) -> [NoteRecord] {
        sortBrowseNotes(input, mode: sortMode)
    }

    private func applySort() {
        allNotes = sortNotes(allNotes)
        notes = Array(allNotes.prefix(max(notes.count, pageSize)))
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

enum BrowseQuickFilter: CaseIterable {
    case all
    case addedToday
    case studiedToday
    case newCards
    case review
    case due
    case flag1
    case flag2
    case flag3
    case flag4
    case flag5
    case flag6
    case flag7

    var query: String {
        switch self {
        case .all: ""
        case .addedToday: "added:1"
        case .studiedToday: "rated:1"
        case .newCards: "is:new"
        case .review: "is:review"
        case .due: "prop:due<=0"
        case .flag1: "flag:1"
        case .flag2: "flag:2"
        case .flag3: "flag:3"
        case .flag4: "flag:4"
        case .flag5: "flag:5"
        case .flag6: "flag:6"
        case .flag7: "flag:7"
        }
    }

    var title: String {
        switch self {
        case .all: L("browse_filter_all")
        case .addedToday: L("browse_filter_added_today")
        case .studiedToday: L("browse_filter_studied_today")
        case .newCards: L("browse_filter_new_cards")
        case .review: L("browse_filter_review")
        case .due: L("browse_filter_due")
        case .flag1: L("browse_filter_flag", 1)
        case .flag2: L("browse_filter_flag", 2)
        case .flag3: L("browse_filter_flag", 3)
        case .flag4: L("browse_filter_flag", 4)
        case .flag5: L("browse_filter_flag", 5)
        case .flag6: L("browse_filter_flag", 6)
        case .flag7: L("browse_filter_flag", 7)
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .addedToday: "calendar.badge.plus"
        case .studiedToday: "calendar.badge.clock"
        case .newCards: "sparkles.rectangle.stack"
        case .review: "arrow.clockwise.circle"
        case .due: "clock.badge.exclamationmark"
        case .flag1, .flag2, .flag3, .flag4, .flag5, .flag6, .flag7: "flag"
        }
    }
}

enum BrowseSortMode: CaseIterable {
    case modifiedDesc
    case modifiedAsc
    case createdDesc
    case createdAsc

    var title: String {
        switch self {
        case .modifiedDesc: L("browse_sort_modified_desc")
        case .modifiedAsc: L("browse_sort_modified_asc")
        case .createdDesc: L("browse_sort_created_desc")
        case .createdAsc: L("browse_sort_created_asc")
        }
    }

    var symbol: String {
        switch self {
        case .modifiedDesc: "arrow.down.circle"
        case .modifiedAsc: "arrow.up.circle"
        case .createdDesc: "clock.arrow.circlepath"
        case .createdAsc: "clock"
        }
    }
}

func sortBrowseNotes(_ input: [NoteRecord], mode: BrowseSortMode) -> [NoteRecord] {
    input.sorted { lhs, rhs in
        switch mode {
        case .modifiedDesc:
            return lhs.mod > rhs.mod
        case .modifiedAsc:
            return lhs.mod < rhs.mod
        case .createdDesc:
            return lhs.id > rhs.id
        case .createdAsc:
            return lhs.id < rhs.id
        }
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
