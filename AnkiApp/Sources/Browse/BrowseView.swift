import SwiftUI
import AnkiKit
import AnkiBackend
import AnkiProto
import AnkiClients
import Dependencies

struct BrowseView: View {
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.ankiBackend) var backend

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
    @State private var quickFilter: BrowseQuickFilter = .all
    @State private var sortField: BrowseSortField = .noteModified
    @State private var sortReverse = true
    @State private var notetypeNamesByID: [Int64: String] = [:]
    @AppStorage("browse_show_notetype_subtitle") private var showNotetypeSubtitle = true
    @State private var isLoading = false
    @State private var hasMorePages = true
    @State private var showAddNote = false
    @State private var showAddImageOcclusion = false
    @State private var editIOItem: IONoteEditItem?
    @State private var selectedNoteForDelete: NoteRecord?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showTagsManager = false
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
    @State private var batchProgressDone = 0
    @State private var batchProgressTotal = 0
    @State private var showExportOptions = false
    @State private var showExportShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var exportDraft = ExportPackageDraft(kind: .selectedNotesPackage)
    @State private var isExportingSelection = false
    @State private var activeSearchTask: Task<Void, Never>?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var hasLoadedInitialData = false
    @State private var showAllTagsSheet = false

    private let preselectedDeck: DeckInfo?
    private let isActive: Bool
    private let pageSize = 50

    init(preselectedDeck: DeckInfo? = nil, isActive: Bool = true) {
        self.preselectedDeck = preselectedDeck
        self.isActive = isActive
        if let deck = preselectedDeck {
            _activeDeck = State(initialValue: deck)
            _parentDeck = State(initialValue: deck)
        }
    }

    var body: some View {
        Group {
            if isLoading && notes.isEmpty {
                // 初始加载中：居中显示转圈动画
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
                noteListContent
            }

            if isBatchWorking {
                batchProgressOverlay
            }

            if isExportingSelection {
                exportProgressOverlay
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                // MARK: Multi-select toolbar
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("browse_select_all")) {
                        selectAllFilteredNotes()
                    }
                    .amgiToolbarTextButton()
                    .disabled(allNoteIDs.isEmpty)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button(L("browse_select_invert")) {
                        invertSelection()
                    }
                    .amgiToolbarTextButton(tone: .neutral)
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
                    Button(L("common_done")) {
                        withAnimation {
                            selectedNoteIDs.removeAll()
                            isMultiSelecting = false
                        }
                    }
                    .amgiToolbarTextButton()
                }

            } else {
                // MARK: Normal toolbar
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
                            showTagsManager = true
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
                        } label: {
                            Label(L("browse_sort_menu_title"), systemImage: "arrow.up.arrow.down.circle")
                        }

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

                        Divider()

                        Toggle(L("browse_display_note_type_subtitle"), isOn: $showNotetypeSubtitle)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L("browse_more_accessibility"))
                }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView {
                scheduleSearch()
            }
        }
        .sheet(isPresented: $showTagsManager, onDismiss: {
            activeSearchTask?.cancel()
            activeSearchTask = nil
            activeSearchTask = Task {
                await loadTags()
                await performSearch()
            }
        }) {
            TagsView(targetNoteIDs: Array(selectedNoteIDs), noteMode: tagsNoteMode)
        }
        .confirmationDialog(
            L("browse_batch_manage_tags"),
            isPresented: $showTagsActionSheet,
            titleVisibility: .visible
        ) {
            Button(L("browse_batch_tags_add")) {
                tagsNoteMode = .addToNotes
                showTagsManager = true
            }
            Button(L("browse_batch_tags_remove"), role: .destructive) {
                tagsNoteMode = .removeFromNotes
                showTagsManager = true
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
        .sheet(isPresented: $showAllTagsSheet) {
            NavigationStack {
                BrowseAllTagsSheet(tags: allTags, activeTag: activeTag) { selectedTag in
                    activeTag = selectedTag
                }
            }
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
        .safeAreaInset(edge: .top) {
            if !allDecks.isEmpty || !allTags.isEmpty {
                deckFilterBar
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                batchBottomBar
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L("browse_search_placeholder"))
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
        .onChange(of: quickFilter) {
            scheduleSearch()
        }
        .onChange(of: showNotetypeSubtitle) { _, isEnabled in
            Task {
                if isEnabled {
                    await loadNotetypeNames()
                } else {
                    notetypeNamesByID = [:]
                }
            }
        }
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
        .task(id: isActive) {
            guard isActive, !hasLoadedInitialData else { return }
            hasLoadedInitialData = true
            async let decksLoad: Void = loadDecks()
            async let tagsLoad: Void = loadTags()
            async let notetypesLoad: Void = loadNotetypeNames()
            _ = await (decksLoad, tagsLoad, notetypesLoad)
            await performSearch()
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
        .toolbar(isEditing ? .hidden : .visible, for: .tabBar)
    }

    // MARK: - Extracted Sub-Views

    private var noteListContent: some View {
        List(selection: $selectedNoteIDs) {
            ForEach(notes, id: \.id) { note in
                if isEditing {
                    NoteRowView(note: note, notetypeName: showNotetypeSubtitle ? notetypeNamesByID[note.mid] : nil)
                        .listRowBackground(selectedNoteIDs.contains(note.id) ? Color.accentColor.opacity(0.10) : Color.clear)
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
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(L("browse_filter_accessibility"))
    }

    private var batchBottomBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                batchActionButton(systemImage: "rectangle.stack.badge.plus", title: L("browse_batch_move_deck_short")) {
                    showMoveToDeck = true
                }

                batchActionButton(systemImage: "doc.badge.gearshape", title: L("browse_batch_change_notetype_short")) {
                    showChangeNotetype = true
                }

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
                    batchActionLabel(systemImage: "flag.fill", title: L("browse_batch_flag_label"))
                }
                .buttonStyle(.plain)
                .disabled(selectedNoteIDs.isEmpty || isBatchWorking)

                batchActionButton(systemImage: "tag", title: L("browse_batch_manage_tags_short")) {
                    showTagsActionSheet = true
                }

                batchActionButton(systemImage: "square.and.arrow.up", title: L("browse_batch_export_short")) {
                    presentSelectedNotesExportOptions()
                }

                batchActionButton(systemImage: "pause.circle", title: L("browse_batch_suspend_toggle")) {
                    showSuspendConfirm = true
                }

                batchActionButton(systemImage: "arrow.counterclockwise", title: L("browse_batch_reset_new")) {
                    showResetNewConfirm = true
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func batchActionButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AmgiSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.amgiSurface, in: Circle())
                Text(title)
                    .amgiFont(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(selectedNoteIDs.isEmpty || isBatchWorking ? Color.amgiTextTertiary : Color.amgiTextPrimary)
        }
        .buttonStyle(.plain)
        .disabled(selectedNoteIDs.isEmpty || isBatchWorking)
    }

    private func batchActionLabel(systemImage: String, title: String) -> some View {
        VStack(spacing: AmgiSpacing.xs) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Color.amgiSurface, in: Circle())
            Text(title)
                .amgiFont(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
            .foregroundStyle(selectedNoteIDs.isEmpty || isBatchWorking ? Color.amgiTextTertiary : Color.amgiTextPrimary)
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

    private var deckFilterBar: some View {
        VStack(spacing: 0) {
            // Top-level deck chips
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chipButton(label: L("browse_filter_all"), isSelected: activeDeck == nil) {
                            parentDeck = nil
                            activeDeck = nil
                        }
                        .id(deckChipID(nil))
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
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    scrollToDeckChip(proxy: proxy, animated: false)
                }
                .onChange(of: activeDeck?.id) { _, _ in
                    scrollToDeckChip(proxy: proxy)
                }
            }

            // Subdeck row — stays visible as long as a parent with children is selected
            if !childDecks.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chipButton(
                                label: L("browse_filter_all"),
                                isSelected: activeDeck?.id == parentDeck?.id,
                                small: true
                            ) {
                                if activeDeck?.id == parentDeck?.id {
                                    parentDeck = nil
                                    activeDeck = nil
                                } else {
                                    activeDeck = parentDeck
                                }
                            }
                            .id(childDeckChipID(nil))
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
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .onAppear {
                        scrollToChildDeckChip(proxy: proxy, animated: false)
                    }
                    .onChange(of: activeDeck?.id) { _, _ in
                        scrollToChildDeckChip(proxy: proxy)
                    }
                }
            }

            // Tag row
            if !allTags.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
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
                            .id(tagChipID(nil))

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
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .onAppear {
                        scrollToTagChip(proxy: proxy, animated: false)
                    }
                    .onChange(of: activeTag) { _, _ in
                        scrollToTagChip(proxy: proxy)
                    }
                }
            }
        }
        .background(.bar)
    }

    private func chipButton(
        label: String,
        isSelected: Bool,
        small: Bool = false,
        onLongPress: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(small ? AmgiFont.caption.font : AmgiFont.body.font)
                .padding(.horizontal, small ? 10 : 12)
                .padding(.vertical, small ? 4 : 6)
                .background(isSelected ? Color.amgiAccent : Color.amgiSurface)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.amgiTextPrimary))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            onLongPress?()
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

    private func scrollToDeckChip(proxy: ScrollViewProxy, animated: Bool = true) {
        let target = deckChipID(activeDeck?.id)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func scrollToChildDeckChip(proxy: ScrollViewProxy, animated: Bool = true) {
        let target = childDeckChipID(activeDeck?.id == parentDeck?.id ? nil : activeDeck?.id)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func scrollToTagChip(proxy: ScrollViewProxy, animated: Bool = true) {
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

        isExportingSelection = true
        let backend = self.backend
        Task {
            defer { isExportingSelection = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try ImportHelper.exportPackage(backend: backend, configuration: configuration)
                }.value
                exportedFileURL = url
                showExportShareSheet = true
            } catch {
                batchErrorMessage = error.localizedDescription
                showBatchError = true
            }
        }
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

    /// Cancel any in-flight search and start a new one.
    /// Pass `debounce: true` to delay 300 ms (for live search-text typing).
    private func scheduleSearch(debounce: Bool = false) {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        activeSearchTask?.cancel()
        activeSearchTask = nil
        if debounce {
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await performSearch()
            }
        } else {
            activeSearchTask = Task { await performSearch() }
        }
    }

    private func performSearch() async {
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
            allNoteIDs = ids
            if isEditing {
                let visibleIDs = Set(allNoteIDs)
                selectedNoteIDs = selectedNoteIDs.intersection(visibleIDs)
            }
            let firstBatch = try await Task.detached(priority: .userInitiated) {
                try client.fetchBatch(Array(ids.prefix(pageSize)))
            }.value
            try Task.checkCancellation()
            notes = orderedNotes(firstBatch, matching: Array(ids.prefix(pageSize)))
            hasMorePages = ids.count > pageSize
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            allNoteIDs = []
            notes = []
            hasMorePages = false
        }
        isLoading = false
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

    private func loadNotetypeNames() async {
        guard showNotetypeSubtitle else {
            notetypeNamesByID = [:]
            return
        }
        do {
            let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )
            notetypeNamesByID = Dictionary(uniqueKeysWithValues: response.entries.map { ($0.id, $0.name) })
        } catch {
            notetypeNamesByID = [:]
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

    private func batchBury() async {
        await performBatchAction { cardId in
            try cardClient.bury(cardId)
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

private struct BrowseAllTagsSheet: View {
    let tags: [String]
    let activeTag: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                tagButton(title: L("browse_filter_all"), isSelected: activeTag == nil) {
                    onSelect(nil)
                    dismiss()
                }

                ForEach(tags, id: \.self) { tag in
                    tagButton(title: shortTagName(tag), isSelected: activeTag == tag) {
                        onSelect(tag)
                        dismiss()
                    }
                }
            }
            .padding()
        }
        .background(Color.amgiBackground)
        .navigationTitle(L("browse_filter_by_tag"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L("common_cancel")) { dismiss() }
                    .amgiToolbarTextButton(tone: .neutral)
            }
        }
    }

    private func tagButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
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

    private func shortTagName(_ tag: String) -> String {
        String(tag.split(separator: "::").last ?? Substring(tag))
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

    static var primaryCases: [BrowseQuickFilter] {
        [.all, .addedToday, .studiedToday, .newCards, .review, .due]
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

enum BrowseSortField: CaseIterable {
    case due
    case cardModified
    case cardTemplate
    case reviews
    case tags
    case addedDate
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
        case .deck: "square.stack"
        case .noteModified: "note.text.badge.plus"
        case .notetype: "doc.text"
        case .ease: "gauge.with.dots.needle.50percent"
        case .lapses: "exclamationmark.arrow.trianglehead.counterclockwise"
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
                        .amgiToolbarTextButton(tone: .neutral)
                }
            }
        }
    }
}

// MARK: - ChangeNotetypeSheet

struct ChangeNotetypeSheet: View {
    let noteIDs: [Int64]
    let onComplete: () -> Void

    @Dependency(\.ankiBackend) var backend
    @Environment(\.dismiss) private var dismiss

    @State private var notetypeNames: [(id: Int64, name: String)] = []
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List(notetypeNames, id: \.id) { notetype in
                        Button {
                            Task { await applyChangeNotetype(newNotetypeId: notetype.id) }
                        } label: {
                            HStack {
                                Text(notetype.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isWorking {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isWorking)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L("browse_batch_change_notetype"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                        .amgiToolbarTextButton(tone: .neutral)
                }
            }
            .alert(L("browse_batch_failed_title"), isPresented: $showError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .task { await loadNotetypes() }
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

    private func applyChangeNotetype(newNotetypeId: Int64) async {
        isWorking = true
        defer { isWorking = false }

        do {
            // Group note IDs by their current notetype (each note has only one notetype)
            // For each distinct old notetype, get change info and apply
            var notesByOldNotetype: [Int64: [Int64]] = [:]
            for noteId in noteIDs {
                var req = Anki_Notes_NoteId()
                req.nid = noteId
                if let note: Anki_Notes_Note = try? backend.invoke(
                    service: AnkiBackend.Service.notes,
                    method: AnkiBackend.NotesMethod.getNote,
                    request: req
                ) {
                    notesByOldNotetype[note.notetypeID, default: []].append(noteId)
                }
            }

            for (oldNotetypeId, groupedNoteIDs) in notesByOldNotetype {
                if oldNotetypeId == newNotetypeId { continue }

                // Get change info (default field/template mapping)
                var infoReq = Anki_Notetypes_GetChangeNotetypeInfoRequest()
                infoReq.oldNotetypeID = oldNotetypeId
                infoReq.newNotetypeID = newNotetypeId
                let info: Anki_Notetypes_ChangeNotetypeInfo = try backend.invoke(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.getChangeNotetypeInfo,
                    request: infoReq
                )

                // Build change request using the default mapping from info.input
                var changeReq = info.input
                changeReq.noteIds = groupedNoteIDs
                try backend.callVoid(
                    service: AnkiBackend.Service.notetypes,
                    method: AnkiBackend.NotetypesMethod.changeNotetype,
                    request: changeReq
                )
            }

            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - IONoteEditItem

struct IONoteEditItem: Identifiable {
    let id = UUID()
    let noteId: Int64
}
