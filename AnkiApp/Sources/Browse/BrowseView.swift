import SwiftUI
import UIKit
import AnkiKit
import AnkiBackend
import AnkiProto
import AnkiClients
import Dependencies

func browseEscapedSearchTerm(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func browseNotetypeQuery(name: String) -> String {
    "note:\"\(browseEscapedSearchTerm(name))\""
}

struct BrowseView: View {
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.ankiBackend) var backend
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var allNoteIDs: [Int64] = []
    @State private var notes: [NoteRecord] = []
    @State private var allDecks: [DeckInfo] = []
    /// The top-level parent deck selected (stays set even when drilling into subdecks)
    @State private var parentDeck: DeckInfo?
    /// The actual deck filter applied (could be parent or a subdeck)
    @State private var activeDeck: DeckInfo?
    @State private var allTags: [String] = []
    @State private var activeTag: String?
    @State private var activeNotetypeID: Int64?
    @State private var quickFilter: BrowseQuickFilter = .all
    @AppStorage("browse_sort_field") private var sortFieldRaw = BrowseSortField.sortField.rawValue
    @AppStorage("browse_sort_reverse") private var sortReverse = true
    @State private var notetypeNamesByID: [Int64: String] = [:]
    @AppStorage("browse_show_notetype_subtitle") private var showNotetypeSubtitle = true
    @AppStorage("browse_show_deck_quick_filters") private var showDeckQuickFilters = true
    @AppStorage("browse_show_tag_quick_filters") private var showTagQuickFilters = true
    @AppStorage("browse_show_notetype_quick_filters") private var showNotetypeQuickFilters = true
    @State private var isLoading = true
    @State private var hasMorePages = true
    @State private var showAddNote = false
    @State private var showAddImageOcclusion = false
    @State private var editIOItem: IONoteEditItem?
    @State private var selectedNoteForDelete: NoteRecord?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showTagsManager = false
    @State private var tagsTargetNoteIDs: [Int64] = []
    @State private var tagsNoteMode: TagsView.NoteMode = .manage
    @State private var showTagsActionSheet = false
    @State private var showBatchDeleteConfirm = false
    @State private var showMoveToDeck = false
    @State private var showChangeNotetype = false
    @State private var selectedNoteIDs = Set<Int64>()
    @State private var isMultiSelecting = false
    @State private var isBatchWorking = false
    @State private var batchErrorMessage: String?
    @State private var showBatchError = false
    @State private var batchSuccessMessage: String?
    @State private var showBatchSuccess = false
    @State private var showSuspendConfirm = false
    @State private var showResetNewConfirm = false
    @State private var showBuryConfirm = false
    @State private var isBuryingUnbury = false
    @State private var showFindReplace = false
    @State private var showSetDueDate = false
    @State private var setDueDateDays = "0"
    @State private var suspendedNoteIDs = Set<Int64>()
    @State private var buriedNoteIDs = Set<Int64>()
    @State private var flaggedNoteIDs: [Int: Set<Int64>] = [:]
    @State private var batchProgressDone = 0
    @State private var batchProgressTotal = 0
    @State private var showExportOptions = false
    @State private var showExportShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var exportDraft = ExportPackageDraft(kind: .selectedNotesPackage)
    @State private var isExportingSelection = false
    @State private var activeSearchTask: Task<Void, Never>?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var searchGeneration = 0
    @State private var hasLoadedInitialData = false
    @State private var showTopLevelDecksSheet = false
    @State private var showChildDecksSheet = false
    @State private var showAllTagsSheet = false
    @State private var showAllNotetypesSheet = false
    @State private var showFindDuplicates = false

    private let preselectedDeck: DeckInfo?
    private let initialSearchQuery: String
    private let isActive: Bool
    private let pageSize = 50

    private var sortField: BrowseSortField {
        get { BrowseSortField(rawValue: sortFieldRaw) ?? .sortField }
        nonmutating set { sortFieldRaw = newValue.rawValue }
    }

    init(
        preselectedDeck: DeckInfo? = nil,
        initialSearchQuery: String = "",
        isActive: Bool = true
    ) {
        self.preselectedDeck = preselectedDeck
        self.initialSearchQuery = initialSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isActive = isActive

        if let deck = preselectedDeck {
            _activeDeck = State(initialValue: deck)
            _parentDeck = State(initialValue: deck)
        }
    }

    var body: some View {
        let rootContent = browseRootContent
        let presentedContent = browsePresentationContent(rootContent)
        return browseLifecycleContent(presentedContent)
    }

    private var browseRootContent: AnyView {
        AnyView(
            ZStack {
                if usesSidebarLayout {
                    browseSplitRoot
                } else {
                    browseCompactRoot
                }

                if isBatchWorking {
                    batchProgressOverlay
                }

                if isExportingSelection {
                    exportProgressOverlay
                }
            }
        )
    }

    private func browsePresentationContent<Content: View>(_ content: Content) -> some View {
        content
        .sheet(isPresented: $showTagsManager, onDismiss: {
            activeSearchTask?.cancel()
            activeSearchTask = nil
            activeSearchTask = Task {
                await loadTags()
                await performSearch()
            }
        }) {
            TagsView(
                targetNoteIDs: tagsTargetNoteIDs,
                noteMode: tagsNoteMode,
                onSelectTag: tagsTargetNoteIDs.isEmpty ? { tag in
                    activeTag = tag
                } : nil
            )
        }
        .sheet(isPresented: $showFindDuplicates) {
            BrowseFindDuplicatesSheet(
                initialSearch: buildQuery(),
                onOpenDuplicateGroup: { noteIDs in
                    showDuplicateNotes(noteIDs)
                }
            )
        }
        .sheet(isPresented: $showFindReplace) {
            BrowseFindReplaceSheet(noteIDs: Array(selectedNoteIDs)) {
                scheduleSearch()
            }
        }
        .alert(
            L("browse_batch_manage_tags"),
            isPresented: $showTagsActionSheet
        ) {
            Button(L("browse_batch_tags_add")) {
                presentBatchTagsManager(mode: .addToNotes)
            }
            Button(L("browse_batch_tags_remove"), role: .destructive) {
                presentBatchTagsManager(mode: .removeFromNotes)
            }
            Button(L("common_cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showMoveToDeck) {
            MoveToDeckSheet(decks: allDecks) { targetDeck in
                Task { await batchMoveToDeck(deckId: targetDeck.id) }
            }
        }
        .sheet(isPresented: $showChangeNotetype) {
            ChangeNotetypeSheet(noteIDs: Array(selectedNoteIDs)) {
                scheduleSearch()
            }
        }
        .sheet(isPresented: $showTopLevelDecksSheet) {
            NavigationStack {
                BrowseFilterQuickPickerSheet(
                    title: L("browse_filter_by_deck"),
                    allTitle: L("browse_filter_all"),
                    options: topLevelDecks.map { deck in
                        BrowseQuickPickerOption(id: String(deck.id), title: deck.name)
                    },
                    selectedOptionID: {
                        guard let activeDeck, parentDeck?.id == activeDeck.id else { return nil }
                        return String(activeDeck.id)
                    }()
                ) { selectedID in
                    guard let selectedID,
                          let deckID = Int64(selectedID),
                          let deck = topLevelDecks.first(where: { $0.id == deckID }) else {
                        parentDeck = nil
                        activeDeck = nil
                        return
                    }
                    parentDeck = deck
                    activeDeck = deck
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showChildDecksSheet) {
            NavigationStack {
                BrowseFilterQuickPickerSheet(
                    title: parentDeck.map { shortName($0.name) } ?? L("browse_filter_by_deck"),
                    allTitle: L("browse_filter_all"),
                    options: childDecks.map { deck in
                        BrowseQuickPickerOption(id: String(deck.id), title: shortName(deck.name))
                    },
                    selectedOptionID: {
                        guard let activeDeck, activeDeck.id != parentDeck?.id else { return nil }
                        return String(activeDeck.id)
                    }()
                ) { selectedID in
                    guard let selectedID,
                          let deckID = Int64(selectedID),
                          let deck = childDecks.first(where: { $0.id == deckID }) else {
                        activeDeck = parentDeck
                        return
                    }
                    activeDeck = deck
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAllTagsSheet) {
            NavigationStack {
                BrowseFilterQuickPickerSheet(
                    title: L("browse_filter_by_tag"),
                    allTitle: L("browse_filter_all"),
                    options: allTags.map { tag in
                        BrowseQuickPickerOption(id: tag, title: shortTagName(tag))
                    },
                    selectedOptionID: activeTag
                ) { selectedTag in
                    activeTag = selectedTag
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAllNotetypesSheet) {
            NavigationStack {
                BrowseFilterQuickPickerSheet(
                    title: L("browse_filter_by_notetype"),
                    allTitle: L("browse_filter_all"),
                    options: sortedNotetypeOptions.map { notetype in
                        BrowseQuickPickerOption(id: String(notetype.id), title: notetype.name)
                    },
                    selectedOptionID: activeNotetypeID.map { String($0) }
                ) { selectedID in
                    guard let selectedID,
                          let notetypeID = Int64(selectedID) else {
                        activeNotetypeID = nil
                        return
                    }
                    activeNotetypeID = notetypeID
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExportOptions) {
            NavigationStack {
                ExportOptionsView(
                    draft: $exportDraft,
                    availableKinds: [.selectedNotesPackage],
                    decks: [],
                    selectedNotesCount: selectedNoteIDs.count,
                    onCancel: { showExportOptions = false },
                    onExport: {
                        showExportOptions = false
                        startSelectedNotesExport(using: exportDraft)
                    }
                )
            }
        }
        .sheet(isPresented: $showExportShareSheet) {
            if let exportedFileURL {
                ShareSheet(items: [exportedFileURL])
            }
        }
    }

    private func browseLifecycleContent<Content: View>(_ content: Content) -> some View {
        let alertContent = browseAlertContent(content)
        return browseStateObserverContent(alertContent)
    }

    private func browseAlertContent<Content: View>(_ content: Content) -> some View {
        content
        .alert(L("browse_batch_delete_title"), isPresented: $showBatchDeleteConfirm) {
            Button(L("common_cancel"), role: .cancel) { }
            Button(L("common_delete"), role: .destructive) {
                Task { await batchDeleteNotes() }
            }
        } message: {
            Text(L("browse_batch_delete_confirm", selectedNoteIDs.count))
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
        .alert(L("browse_batch_suspend_confirm_title"), isPresented: $showSuspendConfirm) {
            Button(L("common_ok")) { Task { await batchToggleSuspend() } }
            Button(L("common_cancel"), role: .cancel) {}
        } message: {
            Text(L("browse_batch_suspend_confirm_msg", selectedNoteIDs.count))
        }
        .alert(L("browse_batch_reset_confirm_title"), isPresented: $showResetNewConfirm) {
            Button(L("browse_batch_reset_confirm_action"), role: .destructive) { Task { await batchResetToNew() } }
            Button(L("common_cancel"), role: .cancel) {}
        } message: {
            Text(L("browse_batch_reset_confirm_msg", selectedNoteIDs.count))
        }
        .alert(
            isBuryingUnbury ? L("browse_batch_unbury_confirm_title") : L("browse_batch_bury_confirm_title"),
            isPresented: $showBuryConfirm
        ) {
            Button(isBuryingUnbury ? L("browse_batch_unbury_confirm_action") : L("browse_batch_bury_confirm_action")) {
                Task { await batchPerformBuryToggle() }
            }
            Button(L("common_cancel"), role: .cancel) {}
        } message: {
            Text(isBuryingUnbury
                 ? String(format: L("browse_batch_unbury_confirm_msg"), selectedNoteIDs.count)
                 : String(format: L("browse_batch_bury_confirm_msg"), selectedNoteIDs.count))
        }
        .alert(L("review_set_due_title"), isPresented: $showSetDueDate) {
            TextField(L("review_set_due_placeholder"), text: $setDueDateDays)
                .keyboardType(.numbersAndPunctuation)
            Button(L("common_ok")) {
                let days = setDueDateDays
                Task { await batchSetDueDate(days: days) }
            }
            Button(L("common_cancel"), role: .cancel) { setDueDateDays = "0" }
        } message: {
            Text(L("review_set_due_hint"))
        }
    }

    private func browseStateObserverContent<Content: View>(_ content: Content) -> some View {
        let filterObserverContent = browseFilterObserverContent(content)
        let notificationObserverContent = browseNotificationObserverContent(filterObserverContent)
        return browsePresentationObserverContent(notificationObserverContent)
    }

    private func browseFilterObserverContent<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: searchText) {
            scheduleSearch(debounce: true)
        }
        .onChange(of: activeDeck?.id) { _, _ in
            Task {
                await loadTags()
                await performSearch()
            }
        }
        .onChange(of: activeTag) {
            scheduleSearch()
        }
        .onChange(of: activeNotetypeID) {
            scheduleSearch()
        }
        .onChange(of: quickFilter) {
            scheduleSearch()
        }
        .onChange(of: showNotetypeSubtitle) { _, isEnabled in
            Task {
                if isEnabled {
                    await loadNotetypeNames()
                }
            }
        }
    }

    private func browseNotificationObserverContent<Content: View>(_ content: Content) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didOpenNotification)) { _ in
            guard isActive else { return }
            Task {
                async let decksLoad: Void = loadDecks()
                async let tagsLoad: Void = loadTags()
                async let notetypesLoad: Void = loadNotetypeNames()
                _ = await (decksLoad, tagsLoad, notetypesLoad)
                await performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.openBrowseSearchNotification)) { notification in
            let query = notification.userInfo?[AppCollectionEvents.browseSearchQueryUserInfoKey] as? String ?? ""
            applyExternalSearchQuery(query)
        }
        .task(id: isActive) {
            guard isActive, !hasLoadedInitialData else { return }
            hasLoadedInitialData = true
            async let decksLoad: Void = loadDecks()
            async let tagsLoad: Void = loadTags()
            async let notetypesLoad: Void = loadNotetypeNames()
            _ = await (decksLoad, tagsLoad, notetypesLoad)
            if let pendingQuery = AppCollectionEvents.consumePendingBrowseSearchQuery() {
                applyExternalSearchQuery(pendingQuery)
            } else if initialSearchQuery.isEmpty == false {
                applyExternalSearchQuery(initialSearchQuery)
            }
            await performSearch()
        }
    }

    private func browsePresentationObserverContent<Content: View>(_ content: Content) -> some View {
        content
        // Keep Add Note outside the searchable host; otherwise Browse can recreate the
        // presented tree on app state transitions and wipe the in-progress draft.
        .sheet(isPresented: $showAddNote) {
            AddNoteView {
                scheduleSearch()
            }
        }
        // Present IO flows outside the searchable wrapper; otherwise the search host can
        // immediately dismiss nested system pickers when Browse launches the IO add/edit pages.
        .fullScreenCover(isPresented: $showAddImageOcclusion) {
            AddImageOcclusionNoteView {
                scheduleSearch()
            }
        }
        .fullScreenCover(item: $editIOItem) { item in
            EditImageOcclusionNoteView(noteId: item.noteId) {
                scheduleSearch()
            }
        }
    }

    // MARK: - Extracted Sub-Views

    @ToolbarContentBuilder
    private var browseToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if isEditing {
                VStack(spacing: 1) {
                    Text(L("browse_nav_title"))
                        .amgiFont(.cardTitle)
                        .foregroundStyle(Color.amgiTextPrimary)
                    Text(L("browse_selected_count", selectedNoteIDs.count))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            } else {
                VStack(spacing: 1) {
                    Text(L("browse_nav_title"))
                        .amgiFont(.cardTitle)
                        .foregroundStyle(Color.amgiTextPrimary)
                    Text(L("browse_total_count", allNoteIDs.count))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }

        if isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    selectAllFilteredNotes()
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel(L("browse_select_all"))
                .disabled(allNoteIDs.isEmpty)
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    invertSelection()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .accessibilityLabel(L("browse_select_invert"))
                .disabled(allNoteIDs.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showBatchDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L("browse_batch_delete_notes"))
                .disabled(selectedNoteIDs.isEmpty || isBatchWorking)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        selectedNoteIDs.removeAll()
                        isMultiSelecting = false
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(L("common_done"))
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation {
                        isMultiSelecting = true
                    }
                } label: {
                    Image(systemName: "checklist")
                }
                .accessibilityLabel(L("browse_multiselect_accessibility"))
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if usesSidebarLayout {
                    Button {
                        presentCollectionTagsManager()
                    } label: {
                        Image(systemName: "tag")
                    }
                    .accessibilityLabel(L("browse_tags_manage"))

                    Menu {
                        ForEach(BrowseSortField.allCases, id: \.self) { field in
                            Button {
                                sortField = field
                                applySort()
                            } label: {
                                if sortField == field {
                                    Label(field.title, systemImage: "checkmark.circle.fill")
                                } else {
                                    Label(field.title, systemImage: field.symbol)
                                }
                            }
                        }

                        Divider()

                        Button {
                            sortReverse = false
                            applySort()
                        } label: {
                            if !sortReverse {
                                Label(L("browse_sort_order_forward"), systemImage: "checkmark.circle.fill")
                            } else {
                                Label(L("browse_sort_order_forward"), systemImage: "arrow.up")
                            }
                        }

                        Button {
                            sortReverse = true
                            applySort()
                        } label: {
                            if sortReverse {
                                Label(L("browse_sort_order_reverse"), systemImage: "checkmark.circle.fill")
                            } else {
                                Label(L("browse_sort_order_reverse"), systemImage: "arrow.down")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel(L("browse_sort_menu_title"))
                }

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
                        showFindDuplicates = true
                    } label: {
                        Label(L("browse_find_duplicates"), systemImage: "rectangle.and.text.magnifyingglass.rtl")
                    }

                    if !usesSidebarLayout {
                        Button {
                            presentCollectionTagsManager()
                        } label: {
                            Label(L("browse_tags_manage"), systemImage: "tag")
                        }

                        Menu {
                            ForEach(BrowseSortField.allCases, id: \.self) { field in
                                Button {
                                    sortField = field
                                    applySort()
                                } label: {
                                    if sortField == field {
                                        Label(field.title, systemImage: "checkmark.circle.fill")
                                    } else {
                                        Label(field.title, systemImage: field.symbol)
                                    }
                                }
                            }

                            Divider()

                            Button {
                                sortReverse = false
                                applySort()
                            } label: {
                                if !sortReverse {
                                    Label(L("browse_sort_order_forward"), systemImage: "checkmark.circle.fill")
                                } else {
                                    Label(L("browse_sort_order_forward"), systemImage: "arrow.up")
                                }
                            }

                            Button {
                                sortReverse = true
                                applySort()
                            } label: {
                                if sortReverse {
                                    Label(L("browse_sort_order_reverse"), systemImage: "checkmark.circle.fill")
                                } else {
                                    Label(L("browse_sort_order_reverse"), systemImage: "arrow.down")
                                }
                            }
                        } label: {
                            Label(L("browse_sort_menu_title"), systemImage: "arrow.up.arrow.down.circle")
                        }
                    }

                    Divider()

                    Menu {
                        Toggle(L("browse_filter_by_deck"), isOn: $showDeckQuickFilters)
                        Toggle(L("browse_filter_by_tag"), isOn: $showTagQuickFilters)
                        Toggle(L("browse_filter_by_notetype"), isOn: $showNotetypeQuickFilters)
                    } label: {
                        Label(L("browse_quick_filter_buttons"), systemImage: "rectangle.3.group")
                    }

                    Divider()

                    Toggle(L("browse_display_note_type_subtitle"), isOn: $showNotetypeSubtitle)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(L("browse_more_accessibility"))
            }
        }
    }

    private var usesSidebarLayout: Bool {
        horizontalSizeClass == .regular && !isEditing
    }

    private var sortedNotetypeOptions: [(id: Int64, name: String)] {
        notetypeNamesByID
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var browseCompactRoot: some View {
        NavigationStack {
            browseNavigationScaffold {
                browseResultsContent
            }
        }
    }

    private var browseSplitRoot: some View {
        NavigationSplitView {
            browseSidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 360)
        } detail: {
            NavigationStack {
                browseNavigationScaffold {
                    browseResultsContent
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func browseNavigationScaffold<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                browseToolbarContent
                if isEditing && !usesWideBatchBottomBar {
                    batchBottomToolbarContent
                }
            }
            .safeAreaInset(edge: .top) {
                if shouldShowQuickFilterToolbar {
                    deckFilterBar
                }
            }
            .safeAreaInset(edge: .bottom) {
                if usesWideBatchBottomBar {
                    wideBatchBottomBar
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L("browse_search_placeholder")
            )
            .toolbar(isEditing ? .hidden : .visible, for: .tabBar)
    }

    @ViewBuilder
    private var browseResultsContent: some View {
        if isLoading && notes.isEmpty {
            VStack(spacing: AmgiSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text(L("browse_loading"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        } else if notes.isEmpty && !isLoading && searchText.isEmpty && activeDeck == nil {
            ContentUnavailableView(
                L("browse_nav_title"),
                systemImage: "magnifyingglass",
                description: Text(L("browse_empty_desc"))
            )
        } else if notes.isEmpty && !isLoading {
            ContentUnavailableView.search(text: searchText)
        } else {
            noteNavigationList
        }
    }

    private var noteNavigationList: some View {
        List(selection: $selectedNoteIDs) {
            ForEach(notes, id: \.id) { note in
                if isEditing {
                    NoteRowView(note: note, notetypeName: showNotetypeSubtitle ? notetypeNamesByID[note.mid] : nil)
                        .listRowBackground(selectedNoteIDs.contains(note.id) ? Color.accentColor.opacity(0.10) : noteRowBgColor(note))
                        .onAppear {
                            if note.id == notes.last?.id {
                                Task { await loadNextPage() }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 12))
                } else {
                    NavigationLink(value: note) {
                        NoteRowView(note: note, notetypeName: showNotetypeSubtitle ? notetypeNamesByID[note.mid] : nil)
                            .onAppear {
                                if note.id == notes.last?.id {
                                    Task { await loadNextPage() }
                                }
                            }
                    }
                    .listRowBackground(noteRowBgColor(note))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            selectedNoteForDelete = note
                            showDeleteConfirm = true
                        } label: {
                            Label(L("common_delete"), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if note.isImageOcclusionNote {
                            Button {
                                editIOItem = IONoteEditItem(noteId: note.id)
                            } label: {
                                Label(L("io_edit_action"), systemImage: "pencil.and.scribble")
                            }
                            .tint(.indigo)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 12))
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
        .environment(\.editMode, editModeBinding)
        .listStyle(.plain)
        .navigationDestination(for: NoteRecord.self) { note in
            NoteEditingDestinationView(note: note) {
                scheduleSearch()
            }
        }
    }

    private var browseSidebar: some View {
        List {
            if !allDecks.isEmpty {
                Section(L("browse_filter_by_deck")) {
                    browseSidebarDeckChips
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
            }

            if !allTags.isEmpty {
                Section(L("browse_filter_by_tag")) {
                    browseSidebarTagChips
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
            }

            if !sortedNotetypeOptions.isEmpty {
                Section(L("browse_filter_by_notetype")) {
                    browseSidebarNotetypeChips
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                }
            }

            Section(L("browse_batch_flag_label")) {
                browseSidebarFlagList
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(.secondarySystemBackground))
    }

    private var browseSidebarDeckChips: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            browseSidebarChipGrid {
                chipButton(
                    label: L("browse_filter_all"),
                    isSelected: activeDeck == nil
                ) {
                    parentDeck = nil
                    activeDeck = nil
                }

                ForEach(topLevelDecks) { deck in
                    chipButton(
                        label: deck.name,
                        isSelected: parentDeck?.id == deck.id && activeDeck?.id == deck.id
                    ) {
                        if parentDeck?.id == deck.id && activeDeck?.id == deck.id {
                            parentDeck = nil
                            activeDeck = nil
                        } else {
                            parentDeck = deck
                            activeDeck = deck
                        }
                    }
                }
            }

            if !childDecks.isEmpty {
                browseSidebarChipGrid {
                    chipButton(
                        label: L("browse_filter_all"),
                        isSelected: activeDeck?.id == parentDeck?.id,
                        small: true
                    ) {
                        activeDeck = activeDeck?.id == parentDeck?.id ? nil : parentDeck
                    }

                    ForEach(childDecks) { child in
                        chipButton(
                            label: shortName(child.name),
                            isSelected: activeDeck?.id == child.id,
                            small: true
                        ) {
                            activeDeck = activeDeck?.id == child.id ? parentDeck : child
                        }
                    }
                }
            }
        }
    }

    private var browseSidebarTagChips: some View {
        browseSidebarChipGrid {
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
                    activeTag = activeTag == tag ? nil : tag
                }
            }
        }
    }

    private var browseSidebarNotetypeChips: some View {
        browseSidebarChipGrid {
            chipButton(
                label: L("browse_filter_all"),
                isSelected: activeNotetypeID == nil,
                small: true
            ) {
                activeNotetypeID = nil
            }

            ForEach(sortedNotetypeOptions, id: \.id) { notetype in
                chipButton(
                    label: notetype.name,
                    isSelected: activeNotetypeID == notetype.id,
                    small: true
                ) {
                    activeNotetypeID = activeNotetypeID == notetype.id ? nil : notetype.id
                }
            }
        }
    }

    private var browseSidebarFlagList: some View {
        VStack(spacing: 2) {
            browseSidebarFlagRow(
                title: L("browse_filter_all"),
                color: .secondary,
                isSelected: quickFilter == .all
            ) {
                quickFilter = .all
            }

            ForEach(BrowseQuickFilter.flagCases, id: \.self) { filter in
                let flagValue = UInt32(BrowseQuickFilter.flagCases.firstIndex(of: filter)! + 1)
                browseSidebarFlagRow(
                    title: filter.title,
                    color: browseFlagColor(for: flagValue),
                    isSelected: quickFilter == filter
                ) {
                    quickFilter = quickFilter == filter ? .all : filter
                }
            }
        }
    }

    private func browseSidebarFlagRow(
        title: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(title)
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.amgiAccent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func browseSidebarChipGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: AmgiSpacing.sm)],
            alignment: .leading,
            spacing: AmgiSpacing.sm
        ) {
            content()
        }
    }

    private var batchProgressOverlay: some View {
        HStack(spacing: AmgiSpacing.sm) {
            ProgressView(value: Double(batchProgressDone), total: Double(max(batchProgressTotal, 1)))
                .frame(maxWidth: 160)
            Text("\(batchProgressDone)/\(batchProgressTotal)")
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
        }
        .padding(.horizontal, AmgiSpacing.md)
        .padding(.vertical, AmgiSpacing.xs)
        .background(Color.amgiSurface)
        .clipShape(Capsule())
    }

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: AmgiSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text(L("import_export_progress_exporting"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(Color.amgiTextPrimary)
                Text(L("import_export_progress_detail"))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AmgiSpacing.xl)
            .padding(.vertical, AmgiSpacing.lg)
            .frame(maxWidth: 300)
            .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .amgiShadow()
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(BrowseQuickFilter.primaryCases, id: \.self) { filter in
                Button {
                    quickFilter = quickFilter == filter ? .all : filter
                } label: {
                    if quickFilter == filter {
                        Label(filter.title, systemImage: "checkmark.circle.fill")
                    } else {
                        Label(filter.title, systemImage: filter.symbol)
                    }
                }
            }

            Menu {
                ForEach(BrowseQuickFilter.flagCases, id: \.self) { filter in
                    Button {
                        quickFilter = quickFilter == filter ? .all : filter
                    } label: {
                        if quickFilter == filter {
                            Label(filter.title, systemImage: "checkmark.circle.fill")
                        } else {
                            Label(filter.title, systemImage: "flag.fill")
                        }
                    }
                }
            } label: {
                if quickFilter.isFlagFilter {
                    Label(L("browse_batch_flag_label"), systemImage: "checkmark.circle.fill")
                } else {
                    Label(L("browse_batch_flag_label"), systemImage: "flag.fill")
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

            if !sortedNotetypeOptions.isEmpty {
                Menu(L("browse_filter_by_notetype")) {
                    Button {
                        activeNotetypeID = nil
                    } label: {
                        if activeNotetypeID == nil {
                            Label(L("browse_filter_all"), systemImage: "checkmark")
                        } else {
                            Text(L("browse_filter_all"))
                        }
                    }

                    ForEach(sortedNotetypeOptions, id: \.id) { notetype in
                        Button {
                            activeNotetypeID = notetype.id
                        } label: {
                            if activeNotetypeID == notetype.id {
                                Label(notetype.name, systemImage: "checkmark.circle.fill")
                            } else {
                                Label(notetype.name, systemImage: "doc.text")
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

    @ToolbarContentBuilder
    private var batchBottomToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            // 旗标
            Menu {
                browseFlagButton(1) { Task { await batchFlag(1) } }
                browseFlagButton(2) { Task { await batchFlag(2) } }
                browseFlagButton(3) { Task { await batchFlag(3) } }
                browseFlagButton(4) { Task { await batchFlag(4) } }
                browseFlagButton(5) { Task { await batchFlag(5) } }
                browseFlagButton(6) { Task { await batchFlag(6) } }
                browseFlagButton(7) { Task { await batchFlag(7) } }
                Divider()
                browseFlagButton(0) { Task { await batchFlag(0) } }
            } label: {
                Label(L("browse_batch_flag_label"), systemImage: "flag.fill")
            }
            .disabled(selectedNoteIDs.isEmpty || isBatchWorking)

            // 标签
            Button { showTagsActionSheet = true } label: {
                Label(L("browse_batch_manage_tags_short"), systemImage: "tag")
            }
            .disabled(selectedNoteIDs.isEmpty || isBatchWorking)

            // 暂停
            Button { showSuspendConfirm = true } label: {
                Label(L("browse_batch_suspend_toggle"), systemImage: "pause.circle")
            }
            .disabled(selectedNoteIDs.isEmpty || isBatchWorking)

            // 标记
            Button { Task { await batchToggleMark() } } label: {
                Label(L("browse_batch_mark_short"), systemImage: "bookmark")
            }
            .disabled(selectedNoteIDs.isEmpty || isBatchWorking)

            // 立即评分
            Menu {
                Button { Task { await batchGradeNow(rating: .again) } } label: {
                    Label(L("review_rating_again"), systemImage: "1.circle")
                }
                Button { Task { await batchGradeNow(rating: .hard) } } label: {
                    Label(L("review_rating_hard"), systemImage: "2.circle")
                }
                Button { Task { await batchGradeNow(rating: .good) } } label: {
                    Label(L("review_rating_good"), systemImage: "3.circle")
                }
                Button { Task { await batchGradeNow(rating: .easy) } } label: {
                    Label(L("review_rating_easy"), systemImage: "4.circle")
                }
            } label: {
                Label(L("browse_batch_grade_now_short"), systemImage: "star.circle")
            }
            .disabled(selectedNoteIDs.isEmpty || isBatchWorking)

            // 更多
            Menu {
                Button { showMoveToDeck = true } label: {
                    Label(L("browse_batch_move_deck_short"), systemImage: "rectangle.stack.badge.plus")
                }
                Button { showChangeNotetype = true } label: {
                    Label(L("browse_batch_change_notetype_short"), systemImage: "doc.badge.gearshape")
                }
                Button { presentSelectedNotesExportOptions() } label: {
                    Label(L("browse_batch_export_short"), systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) { showResetNewConfirm = true } label: {
                    Label(L("browse_batch_reset_new"), systemImage: "arrow.counterclockwise")
                }
                Button { showSetDueDate = true } label: {
                    Label(L("card_action_set_due_date"), systemImage: "calendar.badge.clock")
                }
                Button { Task { await batchToggleBury() } } label: {
                    Label(L("browse_batch_bury_short"), systemImage: "moon.zzz")
                }
                Divider()
                Button { showFindReplace = true } label: {
                    Label(L("browse_find_replace_short"), systemImage: "magnifyingglass")
                }
            } label: {
                Label(L("browse_more_accessibility"), systemImage: "ellipsis.circle")
            }
            .disabled(selectedNoteIDs.isEmpty || isBatchWorking)
        }
    }

    private var usesWideBatchBottomBar: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular && isEditing
    }

    private enum WideBatchBottomAction: CaseIterable, Identifiable {
        case flag
        case manageTags
        case suspend
        case mark
        case gradeNow
        case moveDeck
        case changeNotetype
        case export
        case setDueDate
        case bury
        case findReplace
        case resetNew

        var id: Self { self }
    }

    private var wideBatchBottomBar: some View {
        let isDisabled = selectedNoteIDs.isEmpty || isBatchWorking

        return GeometryReader { proxy in
            let layout = wideBatchBottomBarLayout(for: proxy.size.width)

            HStack(spacing: 16) {
                ForEach(layout.visible) { action in
                    wideBatchBottomActionView(action, isDisabled: isDisabled)
                }

                if !layout.overflow.isEmpty {
                    Menu {
                        wideBatchOverflowMenuContent(layout.overflow)
                    } label: {
                        Text(L("browse_more_accessibility"))
                            .lineLimit(1)
                            .fixedSize()
                            .amgiToolbarTextButton()
                    }
                    .disabled(isDisabled)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 44)
        .background(Color.amgiSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.amgiBorder.opacity(0.28))
                .frame(height: 1)
        }
    }

    private func wideBatchBottomBarLayout(for availableWidth: CGFloat) -> (visible: [WideBatchBottomAction], overflow: [WideBatchBottomAction]) {
        let actions = WideBatchBottomAction.allCases
        let contentWidth = max(availableWidth - 32, 0)
        let totalWidth = totalWideBatchActionsWidth(actions)

        guard totalWidth > contentWidth else {
            return (actions, [])
        }

        let moreWidth = estimatedWideBatchActionWidth(forTitle: L("browse_more_accessibility"), showsMenuIndicator: true)
        var visible: [WideBatchBottomAction] = []
        var usedWidth: CGFloat = 0

        for (index, action) in actions.enumerated() {
            let actionWidth = estimatedWideBatchActionWidth(for: action)
            let spacingBefore = visible.isEmpty ? 0 : 16
            let needsOverflowMenu = index < actions.count - 1
            let reserveWidth = needsOverflowMenu ? 16 + moreWidth : 0

            if usedWidth + spacingBefore + actionWidth + reserveWidth <= contentWidth {
                visible.append(action)
                usedWidth += spacingBefore + actionWidth
            } else {
                break
            }
        }

        return (visible, Array(actions.dropFirst(visible.count)))
    }

    private func totalWideBatchActionsWidth(_ actions: [WideBatchBottomAction]) -> CGFloat {
        guard !actions.isEmpty else { return 0 }

        let widths = actions.map(estimatedWideBatchActionWidth(for:))
        return widths.reduce(0, +) + CGFloat(actions.count - 1) * 16
    }

    private func estimatedWideBatchActionWidth(for action: WideBatchBottomAction) -> CGFloat {
        estimatedWideBatchActionWidth(
            forTitle: wideBatchActionTitle(action),
            showsMenuIndicator: wideBatchActionShowsMenuIndicator(action)
        )
    }

    private func estimatedWideBatchActionWidth(forTitle title: String, showsMenuIndicator: Bool) -> CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        let indicatorWidth: CGFloat = showsMenuIndicator ? 18 : 0
        return textWidth + indicatorWidth + 4
    }

    private func wideBatchActionShowsMenuIndicator(_ action: WideBatchBottomAction) -> Bool {
        switch action {
        case .flag, .gradeNow:
            return true
        case .manageTags, .suspend, .mark, .moveDeck, .changeNotetype, .export, .setDueDate, .bury, .findReplace, .resetNew:
            return false
        }
    }

    private func wideBatchActionTitle(_ action: WideBatchBottomAction) -> String {
        switch action {
        case .flag:
            return L("browse_batch_flag_label")
        case .manageTags:
            return L("browse_batch_manage_tags_short")
        case .suspend:
            return L("browse_batch_suspend_toggle")
        case .mark:
            return L("browse_batch_mark_short")
        case .gradeNow:
            return L("browse_batch_grade_now_short")
        case .moveDeck:
            return L("browse_batch_move_deck_short")
        case .changeNotetype:
            return L("browse_batch_change_notetype_short")
        case .export:
            return L("browse_batch_export_short")
        case .setDueDate:
            return L("card_action_set_due_date")
        case .bury:
            return L("browse_batch_bury_short")
        case .findReplace:
            return L("browse_find_replace_short")
        case .resetNew:
            return L("browse_batch_reset_new")
        }
    }

    @ViewBuilder
    private func wideBatchBottomActionView(_ action: WideBatchBottomAction, isDisabled: Bool) -> some View {
        switch action {
        case .flag:
            Menu {
                browseFlagButton(1) { Task { await batchFlag(1) } }
                browseFlagButton(2) { Task { await batchFlag(2) } }
                browseFlagButton(3) { Task { await batchFlag(3) } }
                browseFlagButton(4) { Task { await batchFlag(4) } }
                browseFlagButton(5) { Task { await batchFlag(5) } }
                browseFlagButton(6) { Task { await batchFlag(6) } }
                browseFlagButton(7) { Task { await batchFlag(7) } }
                Divider()
                browseFlagButton(0) { Task { await batchFlag(0) } }
            } label: {
                Text(wideBatchActionTitle(action))
                    .lineLimit(1)
                    .fixedSize()
                    .amgiToolbarTextButton()
            }
            .disabled(isDisabled)

        case .manageTags:
            Button(wideBatchActionTitle(action)) {
                showTagsActionSheet = true
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .suspend:
            Button(wideBatchActionTitle(action)) {
                showSuspendConfirm = true
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .mark:
            Button(wideBatchActionTitle(action)) {
                Task { await batchToggleMark() }
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .gradeNow:
            Menu {
                Button(L("review_rating_again")) { Task { await batchGradeNow(rating: .again) } }
                Button(L("review_rating_hard")) { Task { await batchGradeNow(rating: .hard) } }
                Button(L("review_rating_good")) { Task { await batchGradeNow(rating: .good) } }
                Button(L("review_rating_easy")) { Task { await batchGradeNow(rating: .easy) } }
            } label: {
                Text(wideBatchActionTitle(action))
                    .lineLimit(1)
                    .fixedSize()
                    .amgiToolbarTextButton()
            }
            .disabled(isDisabled)

        case .moveDeck:
            Button(wideBatchActionTitle(action)) {
                showMoveToDeck = true
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .changeNotetype:
            Button(wideBatchActionTitle(action)) {
                showChangeNotetype = true
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .export:
            Button(wideBatchActionTitle(action)) {
                presentSelectedNotesExportOptions()
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .setDueDate:
            Button(wideBatchActionTitle(action)) {
                showSetDueDate = true
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .bury:
            Button(wideBatchActionTitle(action)) {
                Task { await batchToggleBury() }
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .findReplace:
            Button(wideBatchActionTitle(action)) {
                showFindReplace = true
            }
            .lineLimit(1)
            .fixedSize()
            .amgiToolbarTextButton()
            .disabled(isDisabled)

        case .resetNew:
            Button(wideBatchActionTitle(action), role: .destructive) {
                showResetNewConfirm = true
            }
            .lineLimit(1)
            .fixedSize()
            .disabled(isDisabled)
        }
    }

    @ViewBuilder
    private func wideBatchOverflowMenuContent(_ actions: [WideBatchBottomAction]) -> some View {
        ForEach(actions) { action in
            wideBatchOverflowMenuItem(action)
        }
    }

    @ViewBuilder
    private func wideBatchOverflowMenuItem(_ action: WideBatchBottomAction) -> some View {
        switch action {
        case .flag:
            Menu(wideBatchActionTitle(action)) {
                browseFlagButton(1) { Task { await batchFlag(1) } }
                browseFlagButton(2) { Task { await batchFlag(2) } }
                browseFlagButton(3) { Task { await batchFlag(3) } }
                browseFlagButton(4) { Task { await batchFlag(4) } }
                browseFlagButton(5) { Task { await batchFlag(5) } }
                browseFlagButton(6) { Task { await batchFlag(6) } }
                browseFlagButton(7) { Task { await batchFlag(7) } }
                Divider()
                browseFlagButton(0) { Task { await batchFlag(0) } }
            }

        case .gradeNow:
            Menu(wideBatchActionTitle(action)) {
                Button(L("review_rating_again")) { Task { await batchGradeNow(rating: .again) } }
                Button(L("review_rating_hard")) { Task { await batchGradeNow(rating: .hard) } }
                Button(L("review_rating_good")) { Task { await batchGradeNow(rating: .good) } }
                Button(L("review_rating_easy")) { Task { await batchGradeNow(rating: .easy) } }
            }

        case .manageTags:
            Button(wideBatchActionTitle(action)) { showTagsActionSheet = true }
        case .suspend:
            Button(wideBatchActionTitle(action)) { showSuspendConfirm = true }
        case .mark:
            Button(wideBatchActionTitle(action)) { Task { await batchToggleMark() } }
        case .moveDeck:
            Button(wideBatchActionTitle(action)) { showMoveToDeck = true }
        case .changeNotetype:
            Button(wideBatchActionTitle(action)) { showChangeNotetype = true }
        case .export:
            Button(wideBatchActionTitle(action)) { presentSelectedNotesExportOptions() }
        case .setDueDate:
            Button(wideBatchActionTitle(action)) { showSetDueDate = true }
        case .bury:
            Button(wideBatchActionTitle(action)) { Task { await batchToggleBury() } }
        case .findReplace:
            Button(wideBatchActionTitle(action)) { showFindReplace = true }
        case .resetNew:
            Button(wideBatchActionTitle(action), role: .destructive) { showResetNewConfirm = true }
        }
    }

    private func browseFlagButton(_ value: UInt32, action: @escaping () -> Void) -> some View {
        let color = browseFlagColor(for: value)
        let icon = value == 0 ? "flag.slash.fill" : "flag.fill"
        let label = value == 0 ? L("flag_none") : L("flag_\(browseFlagKey(for: value))")
        return Button(action: action) {
            Label(label, systemImage: icon)
        }
        .tint(color)
    }

    private func browseFlagColor(for value: UInt32) -> Color {
        switch value {
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        case 5: return .pink
        case 6: return .cyan
        case 7: return .purple
        default: return .secondary
        }
    }

    private func browseFlagKey(for value: UInt32) -> String {
        switch value {
        case 1: return "red"
        case 2: return "orange"
        case 3: return "green"
        case 4: return "blue"
        case 5: return "pink"
        case 6: return "cyan"
        case 7: return "purple"
        default: return "none"
        }
    }

    private var isEditing: Bool {
        isMultiSelecting
    }

    private var editModeBinding: Binding<EditMode> {
        Binding(
            get: { isMultiSelecting ? .active : .inactive },
            set: { newMode in isMultiSelecting = (newMode == .active) }
        )
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

    private var shouldShowQuickFilterToolbar: Bool {
        guard !usesSidebarLayout else { return false }
        return shouldShowDeckQuickFilterRow || shouldShowTagQuickFilterRow || shouldShowNotetypeQuickFilterRow
    }

    private var shouldShowDeckQuickFilterRow: Bool {
        showDeckQuickFilters && !allDecks.isEmpty
    }

    private var shouldShowTagQuickFilterRow: Bool {
        showTagQuickFilters && !allTags.isEmpty
    }

    private var shouldShowNotetypeQuickFilterRow: Bool {
        showNotetypeQuickFilters && !sortedNotetypeOptions.isEmpty
    }

    private var deckFilterBar: some View {
        VStack(spacing: 0) {
            // Top-level deck chips
            if shouldShowDeckQuickFilterRow {
                ScrollViewReader { proxy in
                    HStack(spacing: 8) {
                        chipButton(
                            label: L("browse_filter_all"),
                            isSelected: activeDeck == nil,
                            onLongPress: topLevelDecks.isEmpty ? nil : { showTopLevelDecksSheet = true }
                        ) {
                            parentDeck = nil
                            activeDeck = nil
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(topLevelDecks) { deck in
                                    chipButton(
                                        label: deck.name,
                                        isSelected: parentDeck?.id == deck.id && activeDeck?.id == deck.id
                                    ) {
                                        if parentDeck?.id == deck.id && activeDeck?.id == deck.id {
                                            parentDeck = nil
                                            activeDeck = nil
                                        } else {
                                            parentDeck = deck
                                            activeDeck = deck
                                        }
                                    }
                                    .id(deckChipID(deck.id))
                                }
                            }
                            .padding(.trailing)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.leading)
                    .onAppear {
                        scrollToDeckChip(proxy: proxy, animated: false)
                    }
                    .onChange(of: activeDeck?.id) { _, _ in
                        scrollToDeckChip(proxy: proxy)
                    }
                }
            }

            // Subdeck row — stays visible as long as a parent with children is selected
            if shouldShowDeckQuickFilterRow && !childDecks.isEmpty {
                ScrollViewReader { proxy in
                    HStack(spacing: 8) {
                        chipButton(
                            label: L("browse_filter_all"),
                            isSelected: activeDeck?.id == parentDeck?.id,
                            small: true,
                            onLongPress: childDecks.isEmpty ? nil : { showChildDecksSheet = true }
                        ) {
                            if activeDeck?.id == parentDeck?.id {
                                parentDeck = nil
                                activeDeck = nil
                            } else {
                                activeDeck = parentDeck
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(childDecks) { child in
                                    chipButton(
                                        label: shortName(child.name),
                                        isSelected: activeDeck?.id == child.id,
                                        small: true
                                    ) {
                                        activeDeck = activeDeck?.id == child.id ? parentDeck : child
                                    }
                                    .id(childDeckChipID(child.id))
                                }
                            }
                            .padding(.trailing)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.leading)
                    .onAppear {
                        scrollToChildDeckChip(proxy: proxy, animated: false)
                    }
                    .onChange(of: activeDeck?.id) { _, _ in
                        scrollToChildDeckChip(proxy: proxy)
                    }
                }
            }

            // Tag row
            if shouldShowTagQuickFilterRow {
                ScrollViewReader { proxy in
                    HStack(spacing: 8) {
                        chipButton(
                            label: L("browse_filter_all"),
                            isSelected: activeTag == nil,
                            small: true,
                            onLongPress: {
                                showAllTagsSheet = true
                            }
                        ) {
                            activeTag = nil
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allTags, id: \.self) { tag in
                                    chipButton(
                                        label: shortTagName(tag),
                                        isSelected: activeTag == tag,
                                        small: true
                                    ) {
                                        activeTag = activeTag == tag ? nil : tag
                                    }
                                    .id(tagChipID(tag))
                                }
                            }
                            .padding(.trailing)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.leading)
                    .onAppear {
                        scrollToTagChip(proxy: proxy, animated: false)
                    }
                    .onChange(of: activeTag) { _, _ in
                        scrollToTagChip(proxy: proxy)
                    }
                }
            }

            if shouldShowNotetypeQuickFilterRow {
                ScrollViewReader { proxy in
                    HStack(spacing: 8) {
                        chipButton(
                            label: L("browse_filter_all"),
                            isSelected: activeNotetypeID == nil,
                            small: true,
                            onLongPress: {
                                showAllNotetypesSheet = true
                            }
                        ) {
                            activeNotetypeID = nil
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sortedNotetypeOptions, id: \.id) { notetype in
                                    chipButton(
                                        label: notetype.name,
                                        isSelected: activeNotetypeID == notetype.id,
                                        small: true
                                    ) {
                                        activeNotetypeID = activeNotetypeID == notetype.id ? nil : notetype.id
                                    }
                                    .id(notetypeChipID(notetype.id))
                                }
                            }
                            .padding(.trailing)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.leading)
                    .onAppear {
                        scrollToNotetypeChip(proxy: proxy, animated: false)
                    }
                    .onChange(of: activeNotetypeID) { _, _ in
                        scrollToNotetypeChip(proxy: proxy)
                    }
                }
            }
        }
        .background(.bar)
    }

    @ViewBuilder
    private func chipButton(
        label: String,
        isSelected: Bool,
        small: Bool = false,
        onLongPress: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Text(label)
                .font(small ? AmgiFont.caption.font : AmgiFont.body.font)
                .padding(.horizontal, small ? 10 : 12)
                .padding(.vertical, small ? 4 : 6)
                .background(isSelected ? Color.amgiAccent : Color.amgiSurface)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.amgiTextPrimary))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)

        if let onLongPress {
            button
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            onLongPress()
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            onLongPress()
                        }
                )
        } else {
            button
        }
    }

    private func shortName(_ fullName: String) -> String {
        String(fullName.split(separator: "::").last ?? Substring(fullName))
    }

    private func shortTagName(_ tag: String) -> String {
        // Show only the last component of a hierarchical tag (e.g. "日语::词汇" → "词汇")
        String(tag.split(separator: "::").last ?? Substring(tag))
    }

    private func deckChipID(_ deckID: Int64?) -> String {
        if let deckID {
            return "deck-\(deckID)"
        }
        return "deck-all"
    }

    private func childDeckChipID(_ deckID: Int64?) -> String {
        if let deckID {
            return "child-deck-\(deckID)"
        }
        return "child-deck-all"
    }

    private func tagChipID(_ tag: String?) -> String {
        if let tag {
            return "tag-\(tag)"
        }
        return "tag-all"
    }

    private func notetypeChipID(_ notetypeID: Int64?) -> String {
        if let notetypeID {
            return "notetype-\(notetypeID)"
        }
        return "notetype-all"
    }

    private func scrollToDeckChip(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let deckID = activeDeck?.id else { return }
        let target = deckChipID(deckID)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func scrollToChildDeckChip(proxy: ScrollViewProxy, animated: Bool = true) {
        guard activeDeck?.id != parentDeck?.id, let deckID = activeDeck?.id else { return }
        let target = childDeckChipID(deckID)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func scrollToTagChip(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let activeTag else { return }
        let target = tagChipID(activeTag)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    // MARK: - Data Loading

    private func loadDecks() async {
        do {
            allDecks = try deckClient.fetchAll()
            await loadTags()
        } catch {
            allDecks = []
            allTags = []
        }
    }

    private func loadTags() async {
        do {
            if let activeDeck {
                let noteIDs = try noteClient.searchIds("deck:\"\(activeDeck.name)\"")
                var tagSet = Set<String>()
                let batchSize = 500
                var startIndex = 0
                while startIndex < noteIDs.count {
                    let endIndex = min(startIndex + batchSize, noteIDs.count)
                    let batchIDs = Array(noteIDs[startIndex..<endIndex])
                    let batchNotes = try noteClient.fetchBatch(batchIDs)
                    for note in batchNotes {
                        let tags = note.tags
                            .split(separator: " ")
                            .map(String.init)
                            .filter { !$0.isEmpty }
                        tagSet.formUnion(tags)
                    }
                    startIndex = endIndex
                }
                allTags = tagSet.sorted()
            } else {
                allTags = try tagClient.getAllTags().sorted()
            }
            if let activeTag, !allTags.contains(activeTag) {
                self.activeTag = nil
            }
        } catch {
            allTags = []
            activeTag = nil
        }
    }

    private func scrollToNotetypeChip(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let activeNotetypeID else { return }
        let target = notetypeChipID(activeNotetypeID)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func resolveParentDeck(for deck: DeckInfo?) -> DeckInfo? {
        guard let deck else { return nil }
        if let topLevelDeck = allDecks.first(where: { $0.id == deck.id && !$0.name.contains("::") }) {
            return topLevelDeck
        }

        let prefix = deck.name.split(separator: "::", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let prefix else { return nil }
        return allDecks.first(where: { $0.name == String(prefix) })
    }

    private func presentSelectedNotesExportOptions() {
        guard !selectedNoteIDs.isEmpty, !isBatchWorking, !isExportingSelection else { return }
        exportDraft = ExportPackageDraft(kind: .selectedNotesPackage)
        showExportOptions = true
    }

    private func startSelectedNotesExport(using draft: ExportPackageDraft) {
        guard !selectedNoteIDs.isEmpty, !isExportingSelection else { return }

        let configuration = ImportHelper.ExportPackageConfiguration.noteIDs(
            noteIDs: selectedNoteIDs.sorted(),
            filenameStem: selectedNotesExportFilenameStem(),
            includeScheduling: draft.includeScheduling,
            includeDeckConfigs: draft.includeDeckConfigs,
            includeMedia: draft.includeMedia,
            legacy: draft.legacySupport
        )

        exportedFileURL = nil
        isExportingSelection = true
        let backend = self.backend
        Task {
            defer {
                Task { @MainActor in
                    isExportingSelection = false
                }
            }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try ImportHelper.exportPackage(backend: backend, configuration: configuration)
                }.value
                await MainActor.run {
                    exportedFileURL = url
                    showExportShareSheet = true
                }
            } catch {
                await MainActor.run {
                    batchErrorMessage = error.localizedDescription
                    showBatchError = true
                }
            }
        }
    }

    private func presentCollectionTagsManager() {
        tagsTargetNoteIDs = []
        tagsNoteMode = .manage
        showTagsManager = true
    }

    private func presentBatchTagsManager(mode: TagsView.NoteMode) {
        tagsTargetNoteIDs = Array(selectedNoteIDs)
        tagsNoteMode = mode
        showTagsManager = true
    }

    private func selectedNotesExportFilenameStem() -> String {
        if selectedNoteIDs.count == 1,
           let note = notes.first(where: { selectedNoteIDs.contains($0.id) }) {
            return note.sfld
        }
        return "selected-notes-\(selectedNoteIDs.count)"
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

    // MARK: - Note Row State Colors

    /// Background color for a note row based on its state (marked, flag, suspended, buried).
    /// Priority mirrors upstream Anki: marked > flag > suspended > buried > default.
    private func noteRowBgColor(_ note: NoteRecord) -> Color {
        let tags = note.tags.split(separator: " ").map(String.init)
        if tags.contains("marked") {
            return Color.orange.opacity(0.15)
        }
        for flag in 1...7 {
            if flaggedNoteIDs[flag]?.contains(note.id) == true {
                return browseFlagColor(for: UInt32(flag)).opacity(0.12)
            }
        }
        if suspendedNoteIDs.contains(note.id) {
            return Color.gray.opacity(0.15)
        }
        if buriedNoteIDs.contains(note.id) {
            return Color.teal.opacity(0.12)
        }
        return Color.clear
    }

    /// Concurrently search for notes in each special state and update the color dicts.
    private func loadNoteStates() async {
        let query = buildQuery()
        let baseQuery = query.isEmpty ? "deck:*" : query
        let client = noteClient

        struct SR: Sendable { let key: String; let ids: [Int64] }

        var newSuspended = Set<Int64>()
        var newBuried = Set<Int64>()
        var newFlagged: [Int: Set<Int64>] = [:]

        await withTaskGroup(of: SR.self) { group in
            let pairs: [(String, String)] = [
                ("is:suspended", "\(baseQuery) is:suspended"),
                ("is:buried",    "\(baseQuery) is:buried"),
                ("flag:1", "\(baseQuery) flag:1"),
                ("flag:2", "\(baseQuery) flag:2"),
                ("flag:3", "\(baseQuery) flag:3"),
                ("flag:4", "\(baseQuery) flag:4"),
                ("flag:5", "\(baseQuery) flag:5"),
                ("flag:6", "\(baseQuery) flag:6"),
                ("flag:7", "\(baseQuery) flag:7"),
            ]
            for (key, q) in pairs {
                group.addTask {
                    SR(key: key, ids: (try? client.searchIds(q)) ?? [])
                }
            }
            for await sr in group {
                switch sr.key {
                case "is:suspended": newSuspended = Set(sr.ids)
                case "is:buried":    newBuried    = Set(sr.ids)
                case "flag:1": newFlagged[1] = Set(sr.ids)
                case "flag:2": newFlagged[2] = Set(sr.ids)
                case "flag:3": newFlagged[3] = Set(sr.ids)
                case "flag:4": newFlagged[4] = Set(sr.ids)
                case "flag:5": newFlagged[5] = Set(sr.ids)
                case "flag:6": newFlagged[6] = Set(sr.ids)
                case "flag:7": newFlagged[7] = Set(sr.ids)
                default: break
                }
            }
        }

        suspendedNoteIDs = newSuspended
        buriedNoteIDs    = newBuried
        flaggedNoteIDs   = newFlagged
    }

    /// Cancel any in-flight search and start a new one.
    /// Pass `debounce: true` to delay 300 ms (for live search-text typing).
    private func scheduleSearch(debounce: Bool = false) {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        activeSearchTask?.cancel()
        activeSearchTask = nil
        searchGeneration += 1
        let generation = searchGeneration
        if notes.isEmpty {
            isLoading = true
        }
        if debounce {
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await performSearch(generation: generation)
            }
        } else {
            activeSearchTask = Task { await performSearch(generation: generation) }
        }
    }

    private func performSearch(generation: Int? = nil) async {
        let generation = generation ?? nextSearchGeneration()
        guard generation == searchGeneration else { return }
        isLoading = true
        let query = buildQuery()
        let client = noteClient
        let sortField = self.sortField
        let sortReverse = self.sortReverse
        do {
            let ids = try await Task.detached(priority: .userInitiated) {
                try client.searchIdsSorted(query, sortField.backendColumn, sortReverse)
            }.value
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }
            allNoteIDs = ids
            if isEditing {
                let visibleIDs = Set(allNoteIDs)
                selectedNoteIDs = selectedNoteIDs.intersection(visibleIDs)
            }
            let firstBatch = try await Task.detached(priority: .userInitiated) {
                try client.fetchBatch(Array(ids.prefix(pageSize)))
            }.value
            try Task.checkCancellation()
            guard generation == searchGeneration else { return }
            notes = orderedNotes(firstBatch, matching: Array(ids.prefix(pageSize)))
            hasMorePages = ids.count > pageSize
        } catch is CancellationError {
            if generation == searchGeneration {
                isLoading = false
            }
            return
        } catch {
            guard generation == searchGeneration else { return }
            allNoteIDs = []
            notes = []
            hasMorePages = false
        }
        if generation == searchGeneration {
            isLoading = false
            Task { await loadNoteStates() }
        }
    }

    private func nextSearchGeneration() -> Int {
        searchGeneration += 1
        return searchGeneration
    }

    private func loadNextPage() async {
        guard hasMorePages, !isLoading else { return }
        let loaded = notes.count
        let nextIDs = Array(allNoteIDs.dropFirst(loaded).prefix(pageSize))
        guard !nextIDs.isEmpty else { return }
        let client = noteClient
        let batch = (try? await Task.detached(priority: .userInitiated) {
            try client.fetchBatch(nextIDs)
        }.value) ?? []
        notes.append(contentsOf: orderedNotes(batch, matching: nextIDs))
        hasMorePages = notes.count < allNoteIDs.count
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
        if let activeNotetypeID, let notetypeName = notetypeNamesByID[activeNotetypeID] {
            parts.append(browseNotetypeQuery(name: notetypeName))
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: " ")
    }

    private func orderedNotes(_ input: [NoteRecord], matching ids: [Int64]) -> [NoteRecord] {
        let notesByID = Dictionary(uniqueKeysWithValues: input.map { ($0.id, $0) })
        return ids.compactMap { notesByID[$0] }
    }

    private func applySort() {
        scheduleSearch()
    }

    private func showDuplicateNotes(_ noteIDs: [Int64]) {
        parentDeck = nil
        activeDeck = nil
        activeTag = nil
        activeNotetypeID = nil
        quickFilter = .all
        searchText = BrowseFindDuplicatesSheet.noteIDsQuery(noteIDs)
    }

    private func applyExternalSearchQuery(_ query: String) {
        parentDeck = nil
        activeDeck = nil
        activeTag = nil
        activeNotetypeID = nil
        quickFilter = .all
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchText == trimmed {
            scheduleSearch()
        } else {
            searchText = trimmed
        }
    }

    private func loadNotetypeNames() async {
        do {
            let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )
            notetypeNamesByID = Dictionary(uniqueKeysWithValues: response.entries.map { ($0.id, $0.name) })
            if let activeNotetypeID, notetypeNamesByID[activeNotetypeID] == nil {
                self.activeNotetypeID = nil
            }
        } catch {
            notetypeNamesByID = [:]
            activeNotetypeID = nil
        }
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

    private func batchToggleBury() async {
        // Collect all cards; if all are buried (queue == -2 or -3), unbury; otherwise bury
        var allCardIDs = [(id: Int64, buried: Bool)]()
        do {
            for noteId in selectedNoteIDs {
                let cards = try cardClient.fetchByNote(noteId)
                for card in cards {
                    allCardIDs.append((id: card.id, buried: card.queue == -2 || card.queue == -3))
                }
            }
        } catch { return }

        isBuryingUnbury = !allCardIDs.isEmpty && allCardIDs.allSatisfy { $0.buried }
        showBuryConfirm = true
    }

    private func batchPerformBuryToggle() async {
        var allCardIDs = [(id: Int64, buried: Bool)]()
        do {
            for noteId in selectedNoteIDs {
                let cards = try cardClient.fetchByNote(noteId)
                for card in cards {
                    allCardIDs.append((id: card.id, buried: card.queue == -2 || card.queue == -3))
                }
            }
        } catch { return }

        let allBuried = !allCardIDs.isEmpty && allCardIDs.allSatisfy { $0.buried }
        if allBuried {
            await performBatchAction { cardId in
                try cardClient.unbury(cardId)
            }
        } else {
            await performBatchAction { cardId in
                try cardClient.bury(cardId)
            }
        }
    }

    private func batchToggleMark() async {
        // Check if all selected notes have "marked" tag
        let selectedIDs = selectedNoteIDs
        let noteList = notes.filter { selectedIDs.contains($0.id) }
        let allMarked = !noteList.isEmpty && noteList.allSatisfy { note in
            note.tags.split(separator: " ").map(String.init).contains("marked")
        }
        do {
            if allMarked {
                try tagClient.removeTagFromNotes("marked", Array(selectedIDs))
            } else {
                try tagClient.addTagToNotes("marked", Array(selectedIDs))
            }
            scheduleSearch()
        } catch {
            batchErrorMessage = error.localizedDescription
            showBatchError = true
        }
    }

    private func batchToggleSuspend() async {
        // Collect all cards; if all are suspended (queue == -1), unsuspend all; otherwise suspend all
        var allCardIDs = [(id: Int64, suspended: Bool)]()
        do {
            for noteId in selectedNoteIDs {
                let cards = try cardClient.fetchByNote(noteId)
                for card in cards {
                    allCardIDs.append((id: card.id, suspended: card.queue == -1))
                }
            }
        } catch { return }

        let allSuspended = !allCardIDs.isEmpty && allCardIDs.allSatisfy { $0.suspended }
        if allSuspended {
            await performBatchAction { cardId in
                try cardClient.unsuspend(cardId)
            }
        } else {
            await performBatchAction { cardId in
                try cardClient.suspend(cardId)
            }
        }
    }

    private func batchMoveToDeck(deckId: Int64) async {
        await performBatchAction { cardId in
            try cardClient.moveToDeck(cardId, deckId)
        }
    }

    private func batchResetToNew() async {
        await performBatchAction { cardId in
            try cardClient.resetToNew(cardId)
        }
    }

    private func batchGradeNow(rating: Anki_Scheduler_CardAnswer.Rating) async {
        guard !selectedNoteIDs.isEmpty else { return }
        isBatchWorking = true
        defer { isBatchWorking = false; batchProgressDone = 0; batchProgressTotal = 0 }
        do {
            var allCardIDs = [Int64]()
            for noteId in selectedNoteIDs {
                let cards = try cardClient.fetchByNote(noteId)
                allCardIDs.append(contentsOf: cards.map(\.id))
            }
            var req = Anki_Scheduler_GradeNowRequest()
            req.cardIds = allCardIDs
            req.rating = rating
            let _: Anki_Collection_OpChanges = try backend.invoke(
                service: AnkiBackend.Service.scheduler,
                method: AnkiBackend.SchedulerMethod.gradeNow,
                request: req
            )
            let selectedCount = selectedNoteIDs.count
            selectedNoteIDs.removeAll()
            batchSuccessMessage = L("browse_batch_processed", allCardIDs.count, selectedCount)
            showBatchSuccess = true
            await performSearch()
        } catch {
            batchErrorMessage = error.localizedDescription
            showBatchError = true
        }
    }

    private func batchSetDueDate(days: String) async {
        guard !selectedNoteIDs.isEmpty else { return }
        isBatchWorking = true
        defer { isBatchWorking = false; batchProgressDone = 0; batchProgressTotal = 0 }
        do {
            var allCardIDs = [Int64]()
            for noteId in selectedNoteIDs {
                let cards = try cardClient.fetchByNote(noteId)
                allCardIDs.append(contentsOf: cards.map(\.id))
            }
            var req = Anki_Scheduler_SetDueDateRequest()
            req.cardIds = allCardIDs
            req.days = days
            let _: Anki_Collection_OpChanges = try backend.invoke(
                service: AnkiBackend.Service.scheduler,
                method: AnkiBackend.SchedulerMethod.setDueDate,
                request: req
            )
            let selectedCount = selectedNoteIDs.count
            selectedNoteIDs.removeAll()
            batchSuccessMessage = L("browse_batch_processed", allCardIDs.count, selectedCount)
            showBatchSuccess = true
            await performSearch()
        } catch {
            batchErrorMessage = error.localizedDescription
            showBatchError = true
        }
    }

    private func batchDeleteNotes() async {
        guard !selectedNoteIDs.isEmpty else { return }
        isBatchWorking = true
        batchProgressTotal = selectedNoteIDs.count
        batchProgressDone = 0
        defer {
            isBatchWorking = false
            batchProgressDone = 0
            batchProgressTotal = 0
        }
        do {
            for noteId in selectedNoteIDs {
                try noteClient.delete(noteId)
                batchProgressDone += 1
            }
            let count = selectedNoteIDs.count
            selectedNoteIDs.removeAll()
            batchSuccessMessage = L("browse_batch_processed", count, count)
            showBatchSuccess = true
            await performSearch()
        } catch {
            batchErrorMessage = error.localizedDescription
            showBatchError = true
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
        selectedNoteIDs = Set(allNoteIDs)
    }

    private func invertSelection() {
        let allIDs = Set(allNoteIDs)
        selectedNoteIDs = allIDs.subtracting(selectedNoteIDs)
    }
}

private struct BrowseQuickPickerOption: Identifiable {
    let id: String
    let title: String
}

private struct BrowseFilterQuickPickerSheet: View {
    let title: String
    let allTitle: String
    let options: [BrowseQuickPickerOption]
    let selectedOptionID: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                optionButton(title: allTitle, isSelected: selectedOptionID == nil) {
                    onSelect(nil)
                    dismiss()
                }

                ForEach(options) { option in
                    optionButton(title: option.title, isSelected: selectedOptionID == option.id) {
                        onSelect(option.id)
                        dismiss()
                    }
                }
            }
            .padding()
        }
        .background(Color.amgiBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L("common_cancel")) { dismiss() }
            }
        }
    }

    private func optionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AmgiFont.caption.font)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? Color.amgiAccent : Color.amgiSurfaceElevated)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.amgiTextPrimary))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

enum BrowseQuickFilter: CaseIterable {
    case all
    case addedToday
    case studiedToday
    case newCards
    case learning
    case review
    case suspended
    case buried
    case due
    case flag1
    case flag2
    case flag3
    case flag4
    case flag5
    case flag6
    case flag7

    static var primaryCases: [BrowseQuickFilter] {
        [.all, .addedToday, .studiedToday, .newCards, .learning, .review, .suspended, .buried, .due]
    }

    static var flagCases: [BrowseQuickFilter] {
        [.flag1, .flag2, .flag3, .flag4, .flag5, .flag6, .flag7]
    }

    var isFlagFilter: Bool {
        Self.flagCases.contains(self)
    }

    var query: String {
        switch self {
        case .all: ""
        case .addedToday: "added:1"
        case .studiedToday: "rated:1"
        case .newCards: "is:new"
        case .learning: "is:learn"
        case .review: "is:review"
        case .suspended: "is:suspended"
        case .buried: "is:buried"
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
        case .learning: L("card_queue_learning")
        case .review: L("browse_filter_review")
        case .suspended: L("stats_card_suspended")
        case .buried: L("stats_card_buried")
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
        case .learning: "text.badge.clock"
        case .review: "arrow.clockwise.circle"
        case .suspended: "pause.circle"
        case .buried: "tray.and.arrow.down"
        case .due: "clock.badge.exclamationmark"
        case .flag1, .flag2, .flag3, .flag4, .flag5, .flag6, .flag7: "flag"
        }
    }
}

enum BrowseSortField: String, CaseIterable {
    case due
    case cardModified
    case cardTemplate
    case reviews
    case tags
    case addedDate
    case sortField
    case deck
    case noteModified
    case notetype
    case ease
    case lapses
    case interval

    var backendColumn: String {
        switch self {
        case .due: "cardDue"
        case .cardModified: "cardMod"
        case .cardTemplate: "template"
        case .reviews: "cardReps"
        case .tags: "noteTags"
        case .addedDate: "noteCrt"
        case .sortField: "noteFld"
        case .deck: "deck"
        case .noteModified: "noteMod"
        case .notetype: "note"
        case .ease: "cardEase"
        case .lapses: "cardLapses"
        case .interval: "cardIvl"
        }
    }

    var title: String {
        switch self {
        case .due: L("browse_sort_field_due")
        case .cardModified: L("browse_sort_field_card_modified")
        case .cardTemplate: L("browse_sort_field_card_template")
        case .reviews: L("browse_sort_field_reviews")
        case .tags: L("browse_sort_field_tags")
        case .addedDate: L("browse_sort_field_added_date")
        case .sortField: L("browse_sort_field_sort_field")
        case .deck: L("browse_sort_field_deck")
        case .noteModified: L("browse_sort_field_note_modified")
        case .notetype: L("browse_sort_field_notetype")
        case .ease: L("browse_sort_field_ease")
        case .lapses: L("browse_sort_field_lapses")
        case .interval: L("browse_sort_field_interval")
        }
    }

    var symbol: String {
        switch self {
        case .due: "clock.badge.exclamationmark"
        case .cardModified: "rectangle.and.pencil.and.ellipsis"
        case .cardTemplate: "rectangle.stack"
        case .reviews: "arrow.clockwise.circle"
        case .tags: "tag"
        case .addedDate: "calendar.badge.plus"
        case .sortField: "list.bullet.rectangle.portrait"
        case .deck: "square.stack"
        case .noteModified: "note.text.badge.plus"
        case .notetype: "doc.text"
        case .ease: "gauge.with.dots.needle.50percent"
        case .lapses: "clock.badge.questionmark"
        case .interval: "timer"
        }
    }
}

// MARK: - NoteRowView

struct NoteRowView: View {
    let note: NoteRecord
    let notetypeName: String?

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
                Text(note.sfld)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if !modifiedDateString.isEmpty {
                    Text(modifiedDateString)
                        .font(.caption2)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }

            if let notetypeName, !notetypeName.isEmpty {
                Text(notetypeName)
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineLimit(1)
            }

            if !tagList.isEmpty {
                let displayTags = Array(tagList.prefix(3))
                let extra = tagList.count - displayTags.count
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(displayTags, id: \.self) { tag in
                            Text(shortTagName(tag))
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        if extra > 0 {
                            Text("+\(extra)")
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
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

// MARK: - MoveToDeckSheet

struct MoveToDeckSheet: View {
    let decks: [DeckInfo]
    let onSelect: (DeckInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(decks) { deck in
                Button {
                    onSelect(deck)
                    dismiss()
                } label: {
                    Text(deck.name)
                        .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .navigationTitle(L("browse_batch_move_deck"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - ChangeNotetypeSheet

private struct ChangeNotetypeMappingData: Identifiable, Sendable, Hashable {
    let id = UUID()
    let info: Anki_Notetypes_ChangeNotetypeInfo
    let noteIDs: [Int64]
    let newNotetypeName: String
}

struct ChangeNotetypeSheet: View {
    let noteIDs: [Int64]
    let onComplete: () -> Void

    @Dependency(\.ankiBackend) var backend
    @Environment(\.dismiss) private var dismiss

    @State private var notetypeNames: [(id: Int64, name: String)] = []
    @State private var isLoading = true
    @State private var isFetchingInfo = false
    @State private var errorTitle = L("common_error")
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var mappingData: ChangeNotetypeMappingData?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List(notetypeNames, id: \.id) { notetype in
                        Button {
                            Task { await prepareMappingInfo(newNotetypeId: notetype.id, newNotetypeName: notetype.name) }
                        } label: {
                            HStack {
                                Text(notetype.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isFetchingInfo {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isFetchingInfo)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L("browse_batch_change_notetype"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                }
            }
            .alert(errorTitle, isPresented: $showError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .task { await loadNotetypes() }
            .navigationDestination(item: $mappingData) { data in
                ChangeNotetypeFieldMappingView(data: data) { finalReq in
                    Task { await applyFinalRequest(finalReq) }
                }
            }
        }
    }

    private func loadNotetypes() async {
        isLoading = true
        do {
            notetypeNames = try loadStandardNotetypeEntries(backend: backend)
        } catch {
            notetypeNames = []
        }
        isLoading = false
    }

    private func prepareMappingInfo(newNotetypeId: Int64, newNotetypeName: String) async {
        isFetchingInfo = true
        defer { isFetchingInfo = false }

        do {
            var notesByOldNotetype: [Int64: [Int64]] = [:]
            for noteId in noteIDs {
                var req = Anki_Notes_NoteId()
                req.nid = noteId
                let note: Anki_Notes_Note = try backend.invoke(
                    service: AnkiBackend.Service.notes,
                    method: AnkiBackend.NotesMethod.getNote,
                    request: req
                )
                if note.notetypeID != newNotetypeId {
                    notesByOldNotetype[note.notetypeID, default: []].append(noteId)
                }
            }

            guard !notesByOldNotetype.isEmpty else {
                presentErrorAlert(
                    title: L("browse_batch_change_notetype"),
                    message: L("browse_batch_change_notetype_same_msg")
                )
                return
            }

            if notesByOldNotetype.count == 1,
               let (oldNotetypeId, groupNoteIDs) = notesByOldNotetype.first {
                // Single old notetype: show full field mapping UI
                var infoReq = Anki_Notetypes_GetChangeNotetypeInfoRequest()
                infoReq.oldNotetypeID = oldNotetypeId
                infoReq.newNotetypeID = newNotetypeId
                let info: Anki_Notetypes_ChangeNotetypeInfo = try backend.invoke(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.getChangeNotetypeInfo,
                    request: infoReq
                )
                mappingData = ChangeNotetypeMappingData(
                    info: info,
                    noteIDs: groupNoteIDs,
                    newNotetypeName: newNotetypeName
                )
            } else {
                // Multiple old notetypes: reject with informative error (align with upstream Anki)
                let count = notesByOldNotetype.count
                presentErrorAlert(
                    title: L("browse_batch_change_notetype_mixed_title"),
                    message: String(format: L("browse_batch_change_notetype_mixed_msg"), count)
                )
            }
        } catch {
            presentErrorAlert(title: L("common_error"), message: error.localizedDescription)
        }
    }

    private func applyFinalRequest(_ req: Anki_Notetypes_ChangeNotetypeRequest) async {
        do {
            try backend.callVoid(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.changeNotetype,
                request: req
            )
            onComplete()
            dismiss()
        } catch {
            presentErrorAlert(title: L("common_error"), message: error.localizedDescription)
        }
    }

    private func presentErrorAlert(title: String, message: String) {
        errorTitle = title
        errorMessage = message
        showError = true
    }
}

// MARK: - ChangeNotetypeFieldMappingView

private struct ChangeNotetypeFieldMappingView: View {
    let data: ChangeNotetypeMappingData
    let onApply: (Anki_Notetypes_ChangeNotetypeRequest) -> Void

    @Environment(\.dismiss) private var dismiss

    // field mapping: index = new field idx, value = old field idx (-1 = discard)
    @State private var fieldMapping: [Int]
    // template mapping: same semantics
    @State private var templateMapping: [Int]

    private var info: Anki_Notetypes_ChangeNotetypeInfo { data.info }

    init(data: ChangeNotetypeMappingData, onApply: @escaping (Anki_Notetypes_ChangeNotetypeRequest) -> Void) {
        self.data = data
        self.onApply = onApply
        _fieldMapping = State(initialValue: data.info.input.newFields.map { Int($0) })
        _templateMapping = State(initialValue: data.info.input.newTemplates.map { Int($0) })
    }

    private var unmappedOldFields: [String] {
        let usedIndices = Set(fieldMapping.filter { $0 >= 0 })
        return info.oldFieldNames.enumerated()
            .filter { !usedIndices.contains($0.offset) }
            .map { $0.element }
    }

    var body: some View {
        List {
            // Info header
            Section {
                LabeledContent(L("browse_batch_change_notetype_from")) {
                    Text(info.oldNotetypeName).foregroundStyle(.secondary)
                }
                LabeledContent(L("browse_batch_change_notetype_to")) {
                    Text(data.newNotetypeName).foregroundStyle(.secondary)
                }
            }

            // Discard warning
            if !unmappedOldFields.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("browse_batch_change_notetype_discard_warning"))
                                .font(.subheadline).fontWeight(.medium)
                            ForEach(unmappedOldFields, id: \.self) { name in
                                Text("· \(name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Field mapping
            Section(L("browse_batch_change_notetype_fields")) {
                ForEach(info.newFieldNames.indices, id: \.self) { newIdx in
                    Picker(info.newFieldNames[newIdx], selection: $fieldMapping[newIdx]) {
                        Text(L("browse_batch_change_notetype_nothing")).tag(-1)
                        ForEach(info.oldFieldNames.indices, id: \.self) { oldIdx in
                            Text(info.oldFieldNames[oldIdx]).tag(oldIdx)
                        }
                    }
                }
            }

            // Template mapping (non-cloze only)
            if !info.input.isCloze && !info.newTemplateNames.isEmpty {
                Section(L("browse_batch_change_notetype_templates")) {
                    ForEach(info.newTemplateNames.indices, id: \.self) { newIdx in
                        let binding = Binding<Int>(
                            get: { newIdx < templateMapping.count ? templateMapping[newIdx] : -1 },
                            set: { if newIdx < templateMapping.count { templateMapping[newIdx] = $0 } }
                        )
                        Picker(info.newTemplateNames[newIdx], selection: binding) {
                            Text(L("browse_batch_change_notetype_nothing")).tag(-1)
                            ForEach(info.oldTemplateNames.indices, id: \.self) { oldIdx in
                                Text(info.oldTemplateNames[oldIdx]).tag(oldIdx)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("browse_batch_change_notetype_field_mapping"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_save")) {
                    var req = info.input
                    req.noteIds = data.noteIDs
                    req.newFields = fieldMapping.map { Int32($0) }
                    if !info.input.isCloze {
                        req.newTemplates = templateMapping.map { Int32($0) }
                    }
                    onApply(req)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct BrowseDuplicateGroup: Identifiable {
    let value: String
    let noteIDs: [Int64]

    var id: String { value + ":" + noteIDs.map(String.init).joined(separator: ",") }
}

struct BrowseFindDuplicatesSheet: View {
    let initialSearch: String
    let onOpenDuplicateGroup: ([Int64]) -> Void

    @Dependency(\.noteClient) var noteClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.ankiBackend) var backend
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String
    @State private var fieldFilterText = ""
    @State private var fieldNames: [String] = []
    @State private var selectedField = ""
    @State private var fieldIndexByNotetypeID: [Int64: [String: Int]] = [:]
    @State private var duplicateGroups: [BrowseDuplicateGroup] = []
    @State private var isLoadingFields = true
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var resultMessage: String?
    @State private var showResultMessage = false
    @State private var errorMessage: String?
    @State private var showError = false

    init(initialSearch: String, onOpenDuplicateGroup: @escaping ([Int64]) -> Void) {
        self.initialSearch = initialSearch
        self.onOpenDuplicateGroup = onOpenDuplicateGroup
        _searchText = State(initialValue: initialSearch)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingFields {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fieldNames.isEmpty {
                    ContentUnavailableView(
                        L("browse_find_duplicates"),
                        systemImage: "rectangle.and.text.magnifyingglass.rtl",
                        description: Text(L("browse_find_duplicates_no_fields"))
                    )
                } else {
                    content
                }
            }
            .navigationTitle(L("browse_find_duplicates"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                }
            }
            .alert(L("common_error"), isPresented: $showError) {
                Button(L("common_ok"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .alert(L("browse_find_duplicates"), isPresented: $showResultMessage) {
                Button(L("common_ok"), role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
            .task {
                await loadFieldMetadata()
            }
        }
    }

    private var content: some View {
        List {
            Section(L("browse_find_duplicates_search_section")) {
                TextField(L("browse_find_duplicates_field_filter"), text: $fieldFilterText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if filteredFieldNames.isEmpty {
                    Text(L("browse_find_duplicates_no_fields"))
                        .foregroundStyle(Color.amgiTextSecondary)
                } else {
                    ForEach(filteredFieldNames, id: \.self) { fieldName in
                        Button {
                            selectedField = fieldName
                        } label: {
                            HStack {
                                Text(fieldName)
                                    .foregroundStyle(Color.amgiTextPrimary)
                                Spacer()
                                if selectedField == fieldName {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.amgiAccent)
                                }
                            }
                        }
                    }
                }

                TextField(L("browse_find_duplicates_search_placeholder"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await findDuplicates() }
                } label: {
                    HStack {
                        Label(L("browse_find_duplicates_run"), systemImage: "magnifyingglass")
                        Spacer()
                        if isSearching {
                            ProgressView()
                        }
                    }
                }
                .disabled(selectedField.isEmpty || isSearching)
            }

            if hasSearched {
                Section {
                    if duplicateGroups.isEmpty {
                        Text(L("browse_find_duplicates_none"))
                            .foregroundStyle(Color.amgiTextSecondary)
                    } else {
                        Text(L("browse_find_duplicates_summary", duplicateGroups.count, totalDuplicateNotes))
                            .foregroundStyle(Color.amgiTextSecondary)

                        Button {
                            Task { await tagDuplicates() }
                        } label: {
                            Label(L("browse_find_duplicates_tag_duplicates"), systemImage: "tag")
                        }
                        .disabled(isSearching)
                    }
                }

                if !duplicateGroups.isEmpty {
                    Section(L("browse_find_duplicates_results_section")) {
                        ForEach(duplicateGroups) { group in
                            Button {
                                onOpenDuplicateGroup(group.noteIDs)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.value)
                                        .foregroundStyle(Color.amgiTextPrimary)
                                        .lineLimit(2)
                                    Text(L("browse_note_count", group.noteIDs.count))
                                        .amgiFont(.caption)
                                        .foregroundStyle(Color.amgiTextSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .listStyle(.insetGrouped)
    }

    private var totalDuplicateNotes: Int {
        duplicateGroups.reduce(0) { $0 + $1.noteIDs.count }
    }

    private var filteredFieldNames: [String] {
        let trimmed = fieldFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fieldNames }
        return fieldNames.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    static func noteIDsQuery(_ noteIDs: [Int64]) -> String {
        let uniqueIDs = Array(Set(noteIDs)).sorted()
        guard !uniqueIDs.isEmpty else { return "nid:0" }
        return "nid:" + uniqueIDs.map(String.init).joined(separator: ",")
    }

    private func loadFieldMetadata() async {
        isLoadingFields = true
        defer { isLoadingFields = false }

        do {
            let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )

            var allFieldNames: [String] = []
            var seenFieldNames = Set<String>()
            var fieldMapByNotetypeID: [Int64: [String: Int]] = [:]

            for entry in response.entries {
                guard let notetype = try? fetchNotetype(backend: backend, id: entry.id) else {
                    continue
                }

                var fieldIndexMap: [String: Int] = [:]
                for (index, field) in notetype.fields.enumerated() {
                    let normalized = field.name.lowercased()
                    fieldIndexMap[normalized] = index
                    if seenFieldNames.insert(normalized).inserted {
                        allFieldNames.append(field.name)
                    }
                }
                fieldMapByNotetypeID[entry.id] = fieldIndexMap
            }

            fieldNames = allFieldNames.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            fieldIndexByNotetypeID = fieldMapByNotetypeID
            if selectedField.isEmpty {
                selectedField = fieldNames.first ?? ""
            }
        } catch {
            fieldNames = []
            fieldIndexByNotetypeID = [:]
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func findDuplicates() async {
        guard !selectedField.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        do {
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteIDs = try noteClient.searchIds(trimmedSearch)

            var groupedIDs: [String: [Int64]] = [:]
            let normalizedFieldName = selectedField.lowercased()
            let batchSize = 250
            var startIndex = 0

            while startIndex < noteIDs.count {
                let endIndex = min(startIndex + batchSize, noteIDs.count)
                let batch = Array(noteIDs[startIndex..<endIndex])
                let notes = try noteClient.fetchBatch(batch)

                for note in notes {
                    guard let fieldIndex = fieldIndexByNotetypeID[note.mid]?[normalizedFieldName],
                          let rawValue = note.readerLookupFieldValue(at: fieldIndex) else {
                        continue
                    }

                    let normalizedValue = Self.normalizedFieldValue(rawValue)
                    guard !normalizedValue.isEmpty else { continue }
                    groupedIDs[normalizedValue, default: []].append(note.id)
                }

                startIndex = endIndex
            }

            duplicateGroups = groupedIDs
                .filter { $0.value.count > 1 }
                .map { BrowseDuplicateGroup(value: $0.key, noteIDs: $0.value.sorted()) }
                .sorted { lhs, rhs in
                    lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
                }
            hasSearched = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func tagDuplicates() async {
        let noteIDs = Array(Set(duplicateGroups.flatMap(\.noteIDs))).sorted()
        guard !noteIDs.isEmpty else { return }

        do {
            let duplicateTag = L("browse_find_duplicates_duplicate_tag")
            try tagClient.addTagToNotes(duplicateTag, noteIDs)
            resultMessage = L("browse_find_duplicates_tagged", noteIDs.count, duplicateTag)
            showResultMessage = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    static func normalizedFieldValue(_ value: String) -> String {
        var normalized = value
            .replacingOccurrences(of: "(?is)\\[sound:[^\\]]+\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }
}

// MARK: - IONoteEditItem

struct IONoteEditItem: Identifiable {
    let id = UUID()
    let noteId: Int64
}
