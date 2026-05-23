import SwiftUI
import AnkiSync
import AnkiClients
import AnkiBackend
import AnkiKit
import AnkiProto
import AnkiReader
import Dependencies
import Foundation
import OSLog
import UIKit

private let logger = Logger(subsystem: "amgi", category: "startup")

private enum SplitRootSection: String, CaseIterable, Identifiable {
    case decks
    case stats
    case reader
    case browse
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decks:
            return L("tab_decks")
        case .stats:
            return L("tab_stats")
        case .reader:
            return L("tab_reader")
        case .browse:
            return L("tab_browse")
        case .settings:
            return L("tab_settings")
        }
    }

    var icon: String {
        switch self {
        case .decks:
            return "rectangle.stack"
        case .stats:
            return "chart.bar"
        case .reader:
            return "books.vertical"
        case .browse:
            return "magnifyingglass"
        case .settings:
            return "gearshape"
        }
    }
}

private struct SettingsSidebarState {
    var selectedItem: SettingsSidebarItem = .account
    var collapsedGroups: Set<SettingsSidebarGroup> = []
}

private struct DecksSidebarState {
    var expandedDeckIDs: Set<Int64> = []
    var selectedDeckID: Int64?
}

private struct StatsSidebarState {
    var selectedDeckID: Int64?
    var selectedGroup: StatsGroup = .overview
    var selectedRevlogRange: RevlogRange = .year
}

private struct ReaderSidebarState {
    var sortOption: ReaderBookSortOption = .recent
    var bookshelfColumns = 3
    var selectedBookID: String?
    var settingsRoute: ReaderLibrarySettingsRoute?
}

private struct BrowseSidebarState {
    var selectedDeckID: Int64?
    var selectedTag: String?
    var selectedNotetypeID: Int64?
    var selectedFlag: Int?
}

private struct SplitShellState {
    var selectedSection: SplitRootSection = .decks
    var decks = DecksSidebarState()
    var stats = StatsSidebarState()
    var reader = ReaderSidebarState()
    var browse = BrowseSidebarState()
    var settings = SettingsSidebarState()
    var collapsedContextSectionIDs: Set<String> = []
}

private struct ReaderSidebarBookSummary: Identifiable {
    enum Source {
        case ankiNotes
        case epub

        var title: String {
            switch self {
            case .ankiNotes:
                return L("reader_library_source_badge_anki")
            case .epub:
                return L("reader_library_source_badge_epub")
            }
        }

        var icon: String {
            switch self {
            case .ankiNotes:
                return "square.stack"
            case .epub:
                return "book.closed"
            }
        }
    }

    let id: String
    let title: String
    let source: Source
    let lastAccess: Date
}

private struct BrowseSidebarNotetypeOption: Identifiable {
    let id: Int64
    let name: String
}

struct ContentView: View {
    @Binding var incomingImportURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private enum RootTab: Hashable {
        case decks
        case browse
        case stats
        case reader
        case settings
    }

    private enum ImportExportOperation {
        case importing
        case exporting

        var titleKey: String {
            switch self {
            case .importing:
                return "import_export_progress_importing"
            case .exporting:
                return "import_export_progress_exporting"
            }
        }
    }

    @Dependency(\.deckClient) var deckClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.readerBookClient) var readerBookClient
    @Dependency(\.readerEpubLibraryClient) var readerEpubLibraryClient
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.syncClient) var syncClient
    @ObservedObject private var syncCoordinator = AppSyncCoordinator.shared
    @ObservedObject private var collectionState = AppCollectionState.shared

    @State private var showSync = false
    @State private var showImport = false
    @State private var showImportOptions = false
    @State private var refreshID = UUID()
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showExportNotice = false
    @State private var exportedFileURL: URL?
    @State private var pendingImportURL: URL?
    @State private var pendingImportNeedsSecurityScope = false
    @State private var showExportShareSheet = false
    @State private var showExportOptions = false
    @State private var importExportOperation: ImportExportOperation?
    @State private var showAddDeckPrompt = false
    @State private var newDeckName = ""
    @State private var showUserManager = false
    @State private var users: [String] = AppUserStore.loadUsers()
    @State private var selectedUser: String = AppUserStore.loadSelectedUser()
    @State private var isSwitchingUser = false
    @State private var userSwitchError: String?
    @State private var showUserSwitchError = false
    @State private var showSyncBadge = false
    @State private var exportDecks: [DeckInfo] = []
    @State private var exportDraft = ExportPackageDraft()
    @State private var importDraft = ImportPackageDraft()
    @State private var selectedTab: RootTab = .decks
    @State private var isReaderTabEnabled = false
    @State private var splitShell = SplitShellState()
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var splitDeckTree: [DeckTreeNode] = DeckTreeCache.load()
    @State private var splitDeckOptions: [DeckInfo] = []
    @State private var splitBrowseTags: [String] = []
    @State private var splitBrowseNotetypes: [BrowseSidebarNotetypeOption] = []
    @State private var splitReaderRecentBooks: [ReaderSidebarBookSummary] = []

    private var isImportExportInProgress: Bool {
        importExportOperation != nil
    }

    private var shouldUseSearchRoleForBrowseTab: Bool {
        UIDevice.current.userInterfaceIdiom != .pad
    }

    var body: some View {
        let rootContent = contentRootView
        let presentationContent = contentPresentationShell(rootContent)
        let observerContent = contentObserverShell(presentationContent)
        return contentAlertShell(observerContent)
    }

    private var contentRootView: AnyView {
        AnyView(
            GeometryReader { proxy in
                ZStack {
                    adaptiveRootContainer(for: proxy.size)
                        .disabled(isImportExportInProgress)

                    if let importExportOperation {
                        importExportOverlay(for: importExportOperation)
                    }
                }
            }
        )
    }

    private func contentPresentationShell<Content: View>(_ content: Content) -> some View {
        content
        .sheet(isPresented: $showSync) {
            updateSyncBadge()
            refreshID = UUID()
        } content: {
            SyncSheet(isPresented: $showSync)
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showUserManager, onDismiss: reloadUsers) {
            UserManagementView()
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExportOptions) {
            NavigationStack {
                ExportOptionsView(
                    draft: $exportDraft,
                    availableKinds: [.collectionPackage, .deckPackage],
                    decks: exportDecks,
                    selectedNotesCount: nil,
                    onCancel: { showExportOptions = false },
                    onExport: {
                        showExportOptions = false
                        startExport(using: exportDraft)
                    }
                )
            }
        }
        .sheet(isPresented: $showImportOptions) {
            if let pendingImportURL {
                NavigationStack {
                    ImportOptionsView(
                        fileName: pendingImportURL.lastPathComponent,
                        fileExtension: pendingImportURL.pathExtension,
                        draft: $importDraft,
                        onCancel: {
                            cancelPendingImport()
                        },
                        onImport: {
                            let url = pendingImportURL
                            self.pendingImportURL = nil
                            showImportOptions = false
                            startImport(
                                from: url,
                                configuration: url.pathExtension.lowercased() == "colpkg"
                                    ? .collection
                                    : importDraft.configuration
                            )
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showExportShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
    }

    private func contentObserverShell<Content: View>(_ content: Content) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: AppUserStore.didChangeNotification)) { _ in
            reloadUsers()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            reloadReaderTabPreference()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didResetNotification)) { _ in
            Task { await reopenCurrentCollectionAfterReset() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSyncAuthEvents.didChangeNotification)) { _ in
            updateSyncBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.openDeckListNotification)) { _ in
            selectSplitSection(.decks)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.openBrowseSearchNotification)) { _ in
            selectSplitSection(.browse)
        }
        .onReceive(syncCoordinator.$state) { _ in
            updateSyncBadge()
        }
        .onChange(of: isReaderTabEnabled) {
            if isReaderTabEnabled == false, selectedTab == .reader {
                selectedTab = usesWideSplitShell(for: UIScreen.main.bounds.size) ? .decks : .settings
            }
            normalizeSplitSectionSelection()
        }
        .onChange(of: selectedTab) { _, newValue in
            syncSplitSection(from: newValue)
        }
        .onChange(of: splitShell.selectedSection) { _, _ in
            Task { await reloadSplitSidebarContext() }
        }
        .onChange(of: splitShell.browse.selectedDeckID) { _, _ in
            Task { await reloadSplitBrowseTags() }
        }
        .onChange(of: splitShell.reader.settingsRoute?.rawValue) { oldValue, newValue in
            guard oldValue != nil, newValue == nil else { return }
            Task { await reloadSplitSidebarContext() }
        }
        .task {
            reloadReaderTabPreference()
            syncSplitSection(from: selectedTab)
            updateSyncBadge()
            runCheckDatabaseIfReady()
            consumePendingIncomingImportURLIfNeeded()
            await reloadSplitSidebarContext()
        }
        .onChange(of: collectionState.isReady) { _, isReady in
            guard isReady else { return }
            runCheckDatabaseIfReady()
            consumePendingIncomingImportURLIfNeeded()
            Task { await reloadSplitSidebarContext() }
        }
        .onChange(of: incomingImportURL) { _, _ in
            consumePendingIncomingImportURLIfNeeded()
        }
    }

    private func contentAlertShell<Content: View>(_ content: Content) -> some View {
        content
        .alert(L("alert_new_deck_title"), isPresented: $showAddDeckPrompt) {
            TextField(L("alert_new_deck_placeholder"), text: $newDeckName)
            Button(L("btn_cancel"), role: .cancel) {
                newDeckName = ""
            }
            Button(L("btn_create")) {
                Task { await createDeck() }
            }
        } message: {
            Text(L("alert_new_deck_message"))
        }
        .alert(L("alert_import_title"), isPresented: $showImportAlert) {
            Button(L("btn_ok")) { }
        } message: {
            Text(importMessage ?? "")
        }
        .alert(L("alert_export_deck_title"), isPresented: $showExportNotice) {
            Button(L("btn_ok")) { }
        } message: {
            Text(importMessage ?? "")
        }
        .alert(L("deck_action_error_title"), isPresented: $showUserSwitchError) {
            Button(L("btn_ok"), role: .cancel) {}
        } message: {
            Text(userSwitchError ?? L("label_error_unknown"))
        }
    }

    @ViewBuilder
    private func adaptiveRootContainer(for size: CGSize) -> some View {
        if usesWideSplitShell(for: size) {
            splitRootView
        } else {
            rootTabView
        }
    }

    @ViewBuilder
    private var rootTabView: some View {
        TabView(selection: $selectedTab) {
            rootTabs
        }
    }

    private func usesWideSplitShell(for size: CGSize) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad
        && horizontalSizeClass == .regular
        && size.width > size.height
    }

    @TabContentBuilder<RootTab>
    private var rootTabs: some TabContent<RootTab> {
        if shouldUseSearchRoleForBrowseTab {
            decksTab
            browseTab
            statsTab
            readerTab
            settingsTab
        } else {
            decksTab
            statsTab
            readerTab
            settingsTab
            browseTab
        }
    }

    private var splitRootSections: [SplitRootSection] {
        var sections: [SplitRootSection] = [.decks, .stats]
        if isReaderTabEnabled {
            sections.append(.reader)
        }
        sections.append(.browse)
        sections.append(.settings)
        return sections
    }

    private var splitSelectionBinding: Binding<SplitRootSection?> {
        Binding(
            get: {
                splitRootSections.contains(splitShell.selectedSection) ? splitShell.selectedSection : .decks
            },
            set: { newValue in
                selectSplitSection(newValue ?? .decks)
            }
        )
    }

    private var splitRootView: some View {
        NavigationSplitView(columnVisibility: $splitColumnVisibility) {
            splitSidebarShell
            .navigationTitle("Amgi")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            splitDetailView
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            normalizeSplitSectionSelection()
            Task { await reloadSplitSidebarContext() }
        }
    }

    private var splitSidebarShell: some View {
        VStack(spacing: 0) {
            List(selection: splitSelectionBinding) {
                ForEach(splitRootSections) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .background(Color.amgiBackground)
            .frame(height: splitSidebarNavigationHeight)

            Divider()

            splitSidebarContextHeader

            splitSidebarContextPanel
        }
    }

    private var splitSidebarNavigationHeight: CGFloat {
        CGFloat(splitRootSections.count) * 48 + 18
    }

    private var splitSidebarContextHeader: some View {
        HStack(spacing: 12) {
            Text(splitShell.selectedSection.title)
                .amgiFont(.captionBold)
                .foregroundStyle(Color.amgiTextSecondary)
            Spacer()
            splitSidebarToggleButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.amgiBackground)
    }

    @ViewBuilder
    private var splitSidebarContextPanel: some View {
        if collectionState.isReady {
            List {
                splitSidebarContextSections
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
        } else {
            CollectionPreparingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.amgiBackground)
        }
    }

    @ViewBuilder
    private var splitDetailView: some View {
        switch splitShell.selectedSection {
        case .decks:
            NavigationStack {
                if let splitSelectedDeck {
                    DeckDetailView(deck: splitSelectedDeck)
                        .id("\(refreshID)-deck-\(splitSelectedDeck.id)")
                } else {
                    DeckListView {
                        refreshID = UUID()
                        Task { await reloadSplitDeckOptions() }
                    }
                    .id(refreshID)
                }
            }
            .toolbar {
                splitDetailToolbarContent()
                ToolbarItemGroup(placement: .topBarTrailing) {
                    deckManagementMenu
                }
            }
        case .stats:
            NavigationStack {
                if collectionState.isReady {
                    StatsDashboardView(
                        isActive: true,
                        externalSelectedDeck: splitStatsSelectedDeckBinding,
                        externalRevlogRange: splitStatsRevlogRangeBinding,
                        externalSelectedGroup: splitStatsSelectedGroupBinding
                    )
                        .id(refreshID)
                } else {
                    CollectionPreparingView()
                }
            }
            .toolbar {
                splitDetailToolbarContent()
            }
        case .reader:
            NavigationStack {
                if collectionState.isReady {
                    ReaderLibraryView(
                        externalSortOption: splitReaderSortOptionBinding,
                        externalBookshelfColumns: splitReaderBookshelfColumnsBinding,
                        externalSelectedBookID: splitReaderSelectedBookIDBinding,
                        externalSettingsRoute: splitReaderSettingsRouteBinding
                    )
                        .id(refreshID)
                } else {
                    CollectionPreparingView()
                }
            }
            .toolbar {
                splitDetailToolbarContent()
            }
        case .browse:
            if collectionState.isReady {
                BrowseView(
                    isActive: true,
                    usesExternalRootSidebar: true,
                    externalDeckSelection: splitBrowseSelectedDeckBinding,
                    externalTagSelection: splitBrowseSelectedTagBinding,
                    externalNotetypeSelection: splitBrowseSelectedNotetypeIDBinding,
                    externalQuickFilterSelection: splitBrowseQuickFilterBinding
                )
                    .id(refreshID)
                    .toolbar {
                        splitDetailToolbarContent()
                    }
            } else {
                CollectionPreparingView()
            }
        case .settings:
            NavigationStack {
                SettingsView(
                    usesExternalRootSidebar: true,
                    externalSelectedItem: splitSettingsSelectedItemBinding
                )
                .id(refreshID)
            }
            .toolbar {
                splitDetailToolbarContent()
            }
        }
    }

    @ToolbarContentBuilder
    private func splitDetailToolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            splitSidebarToggleButton
        }
        ToolbarItem(placement: .topBarLeading) {
            userMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            syncToolbarButton
        }
    }

    private var splitSidebarToggleButton: some View {
        Button {
            toggleSplitSidebar()
        } label: {
            Image(systemName: splitColumnVisibility == .detailOnly ? "sidebar.right" : "sidebar.left")
        }
    }

    private func toggleSplitSidebar() {
        splitColumnVisibility = splitColumnVisibility == .detailOnly ? .all : .detailOnly
    }

    private var splitSelectedDeck: DeckInfo? {
        splitDeckOptions.first { $0.id == splitShell.decks.selectedDeckID }
    }

    private var splitExpandedDeckIDsBinding: Binding<Set<Int64>> {
        Binding(
            get: { splitShell.decks.expandedDeckIDs },
            set: { splitShell.decks.expandedDeckIDs = $0 }
        )
    }

    private var splitSelectedDeckIDBinding: Binding<Int64?> {
        Binding(
            get: { splitShell.decks.selectedDeckID },
            set: { splitShell.decks.selectedDeckID = $0 }
        )
    }

    private var splitStatsSelectedDeckBinding: Binding<DeckInfo?> {
        Binding(
            get: { splitDeckOptions.first { $0.id == splitShell.stats.selectedDeckID } },
            set: { splitShell.stats.selectedDeckID = $0?.id }
        )
    }

    private var splitStatsSelectedGroupBinding: Binding<StatsGroup> {
        Binding(
            get: { splitShell.stats.selectedGroup },
            set: { splitShell.stats.selectedGroup = $0 }
        )
    }

    private var splitStatsRevlogRangeBinding: Binding<RevlogRange> {
        Binding(
            get: { splitShell.stats.selectedRevlogRange },
            set: { splitShell.stats.selectedRevlogRange = $0 }
        )
    }

    private var splitSettingsSelectedItemBinding: Binding<SettingsSidebarItem?> {
        Binding(
            get: { splitShell.settings.selectedItem },
            set: { splitShell.settings.selectedItem = $0 ?? .account }
        )
    }

    private var splitReaderSortOptionBinding: Binding<ReaderBookSortOption> {
        Binding(
            get: { splitShell.reader.sortOption },
            set: { splitShell.reader.sortOption = $0 }
        )
    }

    private var splitReaderBookshelfColumnsBinding: Binding<Int> {
        Binding(
            get: { splitShell.reader.bookshelfColumns },
            set: { splitShell.reader.bookshelfColumns = $0 }
        )
    }

    private var splitReaderSettingsRouteBinding: Binding<ReaderLibrarySettingsRoute?> {
        Binding(
            get: { splitShell.reader.settingsRoute },
            set: { splitShell.reader.settingsRoute = $0 }
        )
    }

    private var splitReaderSelectedBookIDBinding: Binding<String?> {
        Binding(
            get: { splitShell.reader.selectedBookID },
            set: { splitShell.reader.selectedBookID = $0 }
        )
    }

    private var splitBrowseSelectedDeckBinding: Binding<DeckInfo?> {
        Binding(
            get: { splitDeckOptions.first { $0.id == splitShell.browse.selectedDeckID } },
            set: { splitShell.browse.selectedDeckID = $0?.id }
        )
    }

    private var splitBrowseSelectedTagBinding: Binding<String?> {
        Binding(
            get: { splitShell.browse.selectedTag },
            set: { splitShell.browse.selectedTag = $0 }
        )
    }

    private var splitBrowseSelectedNotetypeIDBinding: Binding<Int64?> {
        Binding(
            get: { splitShell.browse.selectedNotetypeID },
            set: { splitShell.browse.selectedNotetypeID = $0 }
        )
    }

    private var splitBrowseQuickFilterBinding: Binding<BrowseQuickFilter> {
        Binding(
            get: { browseQuickFilter(for: splitShell.browse.selectedFlag) },
            set: { splitShell.browse.selectedFlag = selectedFlagNumber(for: $0) }
        )
    }

    @ViewBuilder
    private var splitSidebarContextSections: some View {
        switch splitShell.selectedSection {
        case .decks:
            if !splitDeckTree.isEmpty {
                splitSidebarCollapsibleSection(L("deck_list_nav_title"), key: "decks.list") {
                    splitSidebarDeckTreeRows
                }
            } else if !splitDeckOptions.isEmpty {
                splitSidebarCollapsibleSection(L("deck_list_nav_title"), key: "decks.list") {
                    splitSidebarDeckRows
                }
            }
        case .browse:
            if !splitDeckOptions.isEmpty {
                splitSidebarCollapsibleSection(L("browse_filter_by_deck"), key: "browse.decks") {
                    splitSidebarBrowseDeckRows
                }
            }
            if !splitBrowseTags.isEmpty {
                splitSidebarCollapsibleSection(L("browse_filter_by_tag"), key: "browse.tags") {
                    splitSidebarBrowseTagRows
                }
            }
            if !splitBrowseNotetypes.isEmpty {
                splitSidebarCollapsibleSection(L("browse_filter_by_notetype"), key: "browse.notetypes") {
                    splitSidebarBrowseNotetypeRows
                }
            }
            splitSidebarCollapsibleSection(L("browse_batch_flag_label"), key: "browse.flags") {
                splitSidebarBrowseFlagRows
            }
        case .settings:
            splitSidebarSettingsSections
        case .stats:
            splitSidebarCollapsibleSection(L("stats_nav_title"), key: "stats.groups") {
                splitSidebarStatsGroupRows
            }
            splitSidebarCollapsibleSection(L("browse_filter_by_deck"), key: "stats.decks") {
                splitSidebarStatsDeckRows
            }
            splitSidebarCollapsibleSection(L("stats_period_label"), key: "stats.range") {
                splitSidebarStatsRangeRows
            }
        case .reader:
            splitSidebarCollapsibleSection(L("reader_library_title"), key: "reader.library") {
                splitSidebarReaderLibraryRows
            }
            if !splitReaderRecentBooks.isEmpty {
                splitSidebarCollapsibleSection(L("reader_library_sort_recent"), key: "reader.recent") {
                    splitSidebarReaderRecentRows
                }
            }
            splitSidebarCollapsibleSection(L("tab_settings"), key: "reader.settings") {
                splitSidebarReaderSettingsRows
            }
        }
    }

    private func splitSidebarCollapsibleSection<Content: View>(
        _ title: String,
        key: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            if isSplitSidebarContextSectionExpanded(key) {
                content()
            }
        } header: {
            splitSidebarSectionHeader(title: title, key: key)
        }
    }

    private func splitSidebarSectionHeader(title: String, key: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .amgiFont(.captionBold)
                .foregroundStyle(Color.amgiTextSecondary)
            Spacer()
            Button {
                toggleSplitSidebarContextSection(key)
            } label: {
                Image(systemName: isSplitSidebarContextSectionExpanded(key) ? "chevron.up" : "chevron.down")
                    .foregroundStyle(Color.amgiTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
    }

    private func isSplitSidebarContextSectionExpanded(_ key: String) -> Bool {
        !splitShell.collapsedContextSectionIDs.contains(key)
    }

    private func toggleSplitSidebarContextSection(_ key: String) {
        if splitShell.collapsedContextSectionIDs.contains(key) {
            splitShell.collapsedContextSectionIDs.remove(key)
        } else {
            splitShell.collapsedContextSectionIDs.insert(key)
        }
    }

    private var splitSidebarDeckTreeRows: some View {
        ForEach(splitDeckTree) { node in
            SplitDeckSidebarTreeRow(
                node: node,
                depth: 0,
                expandedDeckIDs: splitExpandedDeckIDsBinding,
                selectedDeckID: splitSelectedDeckIDBinding,
                onSelect: selectSplitDeck
            )
        }
    }

    private var splitSidebarDeckRows: some View {
        ForEach(splitDeckOptions) { deck in
            Button {
                selectSplitDeck(deck.id)
            } label: {
                HStack(spacing: 10) {
                    Text(deck.name)
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.decks.selectedDeckID == deck.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var splitSidebarBrowseDeckRows: some View {
        Group {
            Button {
                splitShell.browse.selectedDeckID = nil
            } label: {
                HStack {
                    Text(L("browse_filter_all"))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.browse.selectedDeckID == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(splitDeckOptions) { deck in
                Button {
                    splitShell.browse.selectedDeckID = splitShell.browse.selectedDeckID == deck.id ? nil : deck.id
                } label: {
                    HStack(spacing: 10) {
                        Text(deck.name)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Spacer()
                        if splitShell.browse.selectedDeckID == deck.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var splitSidebarBrowseTagRows: some View {
        Group {
            Button {
                splitShell.browse.selectedTag = nil
            } label: {
                HStack {
                    Text(L("browse_filter_all"))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.browse.selectedTag == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(splitBrowseTags, id: \.self) { tag in
                Button {
                    splitShell.browse.selectedTag = splitShell.browse.selectedTag == tag ? nil : tag
                } label: {
                    HStack(spacing: 10) {
                        Text(tag)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Spacer()
                        if splitShell.browse.selectedTag == tag {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var splitSidebarBrowseNotetypeRows: some View {
        Group {
            Button {
                splitShell.browse.selectedNotetypeID = nil
            } label: {
                HStack {
                    Text(L("browse_filter_all"))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.browse.selectedNotetypeID == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(splitBrowseNotetypes) { notetype in
                Button {
                    splitShell.browse.selectedNotetypeID = splitShell.browse.selectedNotetypeID == notetype.id ? nil : notetype.id
                } label: {
                    HStack(spacing: 10) {
                        Text(notetype.name)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Spacer()
                        if splitShell.browse.selectedNotetypeID == notetype.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var splitSidebarBrowseFlagRows: some View {
        Group {
            Button {
                splitShell.browse.selectedFlag = nil
            } label: {
                HStack(spacing: 10) {
                    Text(L("browse_filter_all"))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.browse.selectedFlag == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(BrowseQuickFilter.flagCases, id: \.self) { filter in
                Button {
                    let flagNumber = selectedFlagNumber(for: filter)
                    splitShell.browse.selectedFlag = splitShell.browse.selectedFlag == flagNumber ? nil : flagNumber
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(splitSidebarFlagColor(for: filter))
                            .frame(width: 10, height: 10)
                        Text(filter.title)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Spacer()
                        if splitShell.browse.selectedFlag == selectedFlagNumber(for: filter) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var splitSidebarStatsDeckRows: some View {
        Group {
            Button {
                splitShell.stats.selectedDeckID = nil
            } label: {
                HStack {
                    Text(L("stats_whole_collection"))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.stats.selectedDeckID == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(splitDeckOptions.filter { !$0.name.contains("::") }) { deck in
                Button {
                    splitShell.stats.selectedDeckID = splitShell.stats.selectedDeckID == deck.id ? nil : deck.id
                } label: {
                    HStack {
                        Text(deck.name)
                            .foregroundStyle(Color.amgiTextPrimary)
                        Spacer()
                        if splitShell.stats.selectedDeckID == deck.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var splitSidebarStatsGroupRows: some View {
        ForEach(StatsGroup.allCases) { group in
            Button {
                splitShell.stats.selectedGroup = group
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: group.icon)
                        .foregroundStyle(group == splitShell.stats.selectedGroup ? Color.accentColor : Color.amgiTextSecondary)
                    Text(group.title)
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.stats.selectedGroup == group {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var splitSidebarSettingsSections: some View {
        ForEach(SettingsSidebarGroup.allCases) { group in
            Section {
                if isSplitSettingsGroupExpanded(group) {
                    splitSidebarSettingsRows(for: group)
                }
            } header: {
                splitSidebarSettingsHeader(for: group)
            }
        }
    }

    private func splitSidebarSettingsRows(for group: SettingsSidebarGroup) -> some View {
        ForEach(group.items) { item in
            Button {
                splitShell.settings.selectedItem = item
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .foregroundStyle(item == splitShell.settings.selectedItem ? Color.accentColor : Color.amgiTextSecondary)
                    Text(item.title)
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.settings.selectedItem == item {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func splitSidebarSettingsHeader(for group: SettingsSidebarGroup) -> some View {
        HStack(spacing: 12) {
            Text(group.title)
                .amgiFont(.captionBold)
                .foregroundStyle(Color.amgiTextSecondary)
            Spacer()
            Button {
                toggleSplitSettingsGroup(group)
            } label: {
                Image(systemName: isSplitSettingsGroupExpanded(group) ? "chevron.up" : "chevron.down")
                    .foregroundStyle(Color.amgiTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .textCase(nil)
    }

    private func isSplitSettingsGroupExpanded(_ group: SettingsSidebarGroup) -> Bool {
        !splitShell.settings.collapsedGroups.contains(group)
    }

    private func toggleSplitSettingsGroup(_ group: SettingsSidebarGroup) {
        if splitShell.settings.collapsedGroups.contains(group) {
            splitShell.settings.collapsedGroups.remove(group)
        } else {
            splitShell.settings.collapsedGroups.insert(group)
        }
    }

    private var splitSidebarStatsRangeRows: some View {
        ForEach(RevlogRange.allCases, id: \.self) { range in
            Button {
                splitShell.stats.selectedRevlogRange = range
            } label: {
                HStack {
                    Text(range.localizedLabel)
                        .foregroundStyle(Color.amgiTextPrimary)
                    Spacer()
                    if splitShell.stats.selectedRevlogRange == range {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var splitSidebarReaderLibraryRows: some View {
        Button {
            splitShell.reader.selectedBookID = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical")
                    .foregroundStyle(splitShell.reader.selectedBookID == nil ? Color.accentColor : Color.amgiTextSecondary)
                Text(L("browse_filter_all"))
                    .foregroundStyle(Color.amgiTextPrimary)
                Spacer()
                if splitShell.reader.selectedBookID == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var splitSidebarReaderRecentRows: some View {
        ForEach(splitReaderRecentBooks) { book in
            Button {
                splitShell.reader.selectedBookID = splitShell.reader.selectedBookID == book.id ? nil : book.id
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: book.source.icon)
                        .foregroundStyle(splitShell.reader.selectedBookID == book.id ? Color.accentColor : Color.amgiTextSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .foregroundStyle(Color.amgiTextPrimary)
                            .lineLimit(2)
                        Text("\(book.source.title) · \(splitReaderLastAccessText(for: book.lastAccess))")
                            .font(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if splitShell.reader.selectedBookID == book.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var splitSidebarReaderSettingsRows: some View {
        Group {
            splitSidebarReaderSettingsButton(
                title: L("settings_reader_section_source"),
                icon: "tray.full",
                route: .source
            )
            splitSidebarReaderSettingsButton(
                title: L("settings_reader_manage_dictionaries"),
                icon: "character.book.closed",
                route: .dictionaries
            )
            splitSidebarReaderSettingsButton(
                title: L("settings_reader_display_settings"),
                icon: "paintbrush",
                route: .display
            )
            splitSidebarReaderSettingsButton(
                title: L("settings_reader_advanced_settings"),
                icon: "gearshape.2",
                route: .advanced
            )
        }
    }

    private func splitSidebarReaderSettingsButton(
        title: String,
        icon: String,
        route: ReaderLibrarySettingsRoute
    ) -> some View {
        Button {
            splitShell.reader.settingsRoute = route
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .foregroundStyle(Color.amgiTextPrimary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func splitReaderLastAccessText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func rootTab(for section: SplitRootSection) -> RootTab {
        switch section {
        case .decks:
            return .decks
        case .stats:
            return .stats
        case .reader:
            return .reader
        case .browse:
            return .browse
        case .settings:
            return .settings
        }
    }

    private func splitSection(for tab: RootTab) -> SplitRootSection? {
        switch tab {
        case .decks:
            return .decks
        case .stats:
            return .stats
        case .reader:
            return .reader
        case .browse:
            return .browse
        case .settings:
            return .settings
        }
    }

    private func selectSplitSection(_ section: SplitRootSection) {
        splitShell.selectedSection = section
        let targetTab = rootTab(for: section)
        if selectedTab != targetTab {
            selectedTab = targetTab
        }
    }

    private func selectSplitDeck(_ deckID: Int64?) {
        splitShell.decks.selectedDeckID = splitShell.decks.selectedDeckID == deckID ? nil : deckID
        guard let selectedDeckID = splitShell.decks.selectedDeckID else { return }
        splitShell.decks.expandedDeckIDs.formUnion(ancestorDeckIDs(for: selectedDeckID, in: splitDeckTree))
    }

    private func syncSplitSection(from tab: RootTab) {
        guard let section = splitSection(for: tab) else { return }
        if !splitRootSections.contains(section) {
            splitShell.selectedSection = .decks
            return
        }
        if splitShell.selectedSection != section {
            splitShell.selectedSection = section
        }
    }

    private func normalizeSplitSectionSelection() {
        if !splitRootSections.contains(splitShell.selectedSection) {
            splitShell.selectedSection = .decks
        }
        if selectedTab == .reader && isReaderTabEnabled == false {
            selectedTab = .decks
        }
    }

    private func browseQuickFilter(for selectedFlag: Int?) -> BrowseQuickFilter {
        guard let selectedFlag else { return .all }
        switch selectedFlag {
        case 1:
            return .flag1
        case 2:
            return .flag2
        case 3:
            return .flag3
        case 4:
            return .flag4
        case 5:
            return .flag5
        case 6:
            return .flag6
        case 7:
            return .flag7
        default:
            return .all
        }
    }

    private func selectedFlagNumber(for filter: BrowseQuickFilter) -> Int? {
        switch filter {
        case .flag1:
            return 1
        case .flag2:
            return 2
        case .flag3:
            return 3
        case .flag4:
            return 4
        case .flag5:
            return 5
        case .flag6:
            return 6
        case .flag7:
            return 7
        default:
            return nil
        }
    }

    private func ancestorDeckIDs(for selectedDeckID: Int64, in nodes: [DeckTreeNode]) -> [Int64] {
        for node in nodes {
            if node.id == selectedDeckID {
                return []
            }
            let descendantPath = ancestorDeckIDs(for: selectedDeckID, in: node.children)
            if node.children.isEmpty == false, descendantPath.isEmpty == false || node.children.contains(where: { $0.id == selectedDeckID }) {
                return [node.id] + descendantPath
            }
        }
        return []
    }

    private func normalizedExpandedDeckIDs(for nodes: [DeckTreeNode]) -> Set<Int64> {
        let validDeckIDs = allDeckIDs(in: nodes)
        var expandedDeckIDs = splitShell.decks.expandedDeckIDs.intersection(validDeckIDs)
        if let selectedDeckID = splitShell.decks.selectedDeckID {
            expandedDeckIDs.formUnion(ancestorDeckIDs(for: selectedDeckID, in: nodes))
        }
        return expandedDeckIDs
    }

    private func allDeckIDs(in nodes: [DeckTreeNode]) -> Set<Int64> {
        Set(nodes.flatMap { node in
            [node.id] + Array(allDeckIDs(in: node.children))
        })
    }

    private var decksTab: some TabContent<RootTab> {
        Tab(L("tab_decks"), systemImage: "rectangle.stack", value: RootTab.decks) {
            NavigationStack {
                DeckListView {
                    refreshID = UUID()
                }
                    .id(refreshID)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            userMenu
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            trailingActions
                        }
                    }
            }
        }
    }

    @TabContentBuilder<RootTab>
    private var browseTab: some TabContent<RootTab> {
        if shouldUseSearchRoleForBrowseTab {
            Tab(value: RootTab.browse, role: .search) {
                browseTabContent
            }
        } else {
            Tab(L("tab_browse"), systemImage: "magnifyingglass", value: RootTab.browse) {
                browseTabContent
            }
        }
    }

    @ViewBuilder
    private var browseTabContent: some View {
        if collectionState.isReady {
            BrowseView(isActive: selectedTab == .browse)
                .id(refreshID)
        } else {
            CollectionPreparingView()
        }
    }

    private var statsTab: some TabContent<RootTab> {
        Tab(L("tab_stats"), systemImage: "chart.bar", value: RootTab.stats) {
            NavigationStack {
                if collectionState.isReady {
                    StatsDashboardView(isActive: selectedTab == .stats)
                        .id(refreshID)
                } else {
                    CollectionPreparingView()
                }
            }
        }
    }

    @TabContentBuilder<RootTab>
    private var readerTab: some TabContent<RootTab> {
        if isReaderTabEnabled {
            Tab(L("tab_reader"), systemImage: "books.vertical", value: RootTab.reader) {
                NavigationStack {
                    if collectionState.isReady {
                        ReaderLibraryView()
                            .id(refreshID)
                    } else {
                        CollectionPreparingView()
                    }
                }
            }
        }
    }

    private var settingsTab: some TabContent<RootTab> {
        Tab(L("tab_settings"), systemImage: "gearshape", value: RootTab.settings) {
            SettingsView()
                .id(refreshID)
        }
    }

    // MARK: - Extracted Sub-Views

    @ViewBuilder
    private func importExportOverlay(for operation: ImportExportOperation) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(L(operation.titleKey))
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(Color.amgiTextPrimary)
                Text(L("import_export_progress_detail"))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 300)
            .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.amgiBorder.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
        }
        .transition(.opacity)
    }

    private var userMenu: some View {
        Button {
            showUserManager = true
        } label: {
            HStack(spacing: 6) {
                Label(
                    currentUserDisplayName,
                    systemImage: isSwitchingUser ? "arrow.triangle.2.circlepath.circle" : "person.crop.circle"
                )
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(AmgiFont.micro.font)
                    .foregroundStyle(Color.amgiTextSecondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .amgiCapsuleControl()
        }
        .buttonStyle(.plain)
        .disabled(isSwitchingUser)
    }

    private var currentUserDisplayName: String {
        let trimmed = selectedUser.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppUserStore.loadSelectedUser() : trimmed
    }

    private var trailingActions: some View {
        HStack(spacing: 14) {
            syncToolbarButton
            deckManagementMenu
        }
    }

    private var syncToolbarButton: some View {
        Button {
            showSync = true
        } label: {
            if syncCoordinator.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("sync_syncing"))
                        .amgiFont(.captionBold)
                        .foregroundStyle(Color.amgiTextPrimary)
                }
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .padding(.top, 3)
                        .padding(.trailing, 3)
                    if showSyncBadge {
                        Circle()
                            .fill(Color.amgiDanger)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .disabled(!collectionState.isReady)
    }

    private var deckManagementMenu: some View {
        Menu {
            Button(L("menu_add_deck")) {
                showAddDeckPrompt = true
            }
            Button(L("menu_export_deck")) {
                presentExportOptions()
            }
            Divider()
            Button(L("menu_import_apkg")) {
                showImport = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(!collectionState.isReady)
    }

    private func reloadUsers() {
        let previousUser = selectedUser
        users = AppUserStore.loadUsers()
        let newUser = AppUserStore.loadSelectedUser()
        if newUser != previousUser {
            // User was switched inside UserManagementView; reopen backend collection
            Task { await switchUser(to: newUser) }
        } else {
            selectedUser = newUser
            refreshID = UUID()
        }
        updateSyncBadge()
    }

    private func updateSyncBadge() {
        guard KeychainHelper.loadHostKey() != nil else {
            showSyncBadge = false
            return
        }
        let key = SyncPreferences.Keys.lastCollectionSyncedAtForCurrentUser()
        let ts = UserDefaults.standard.double(forKey: key)
        if ts == 0 {
            showSyncBadge = true // never synced
        } else {
            let hoursSince = (Date().timeIntervalSince1970 - ts) / 3600
            showSyncBadge = hoursSince > 12
        }
    }

    private func runCheckDatabaseIfReady() {
        guard collectionState.isReady else { return }
        // CheckDatabase runs in background after UI is visible and collection is open.
        Task.detached(priority: .background) {
            @Dependency(\.ankiBackend) var backend
            let start = Date()
            do {
                let result = try backend.call(
                    service: AnkiBackend.Service.collection,
                    method: AnkiBackend.CheckDatabaseMethod.checkDatabase
                )
                let elapsed = Date().timeIntervalSince(start)
                logger.info("CheckDatabase completed in \(elapsed, format: .fixed(precision: 2))s (\(result.count) bytes)")
            } catch {
                logger.warning("CheckDatabase failed: \(error)")
            }
        }
    }

    private func createDeck() async {
        guard collectionState.isReady else { return }
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try deckClient.create(name)
            refreshID = UUID()
            importMessage = L("alert_import_title") + ": \(name)"
            showImportAlert = true
            newDeckName = ""
        } catch {
            importMessage = L("alert_new_deck_failed", error.localizedDescription)
            showImportAlert = true
        }
    }

    private func switchUser(to user: String) async {
        guard user != selectedUser, !isSwitchingUser else { return }

        isSwitchingUser = true
        defer { isSwitchingUser = false }

        do {
            collectionState.markOpening()
            try reopenCollection(for: user)

            selectedUser = user
            AppUserStore.setSelectedUser(user)
            reloadReaderTabPreference()
            refreshID = UUID()
            collectionState.markReady()
        } catch {
            collectionState.markFailed(error.localizedDescription)
            userSwitchError = error.localizedDescription
            showUserSwitchError = true
        }
    }

    @MainActor
    private func reopenCurrentCollectionAfterReset() async {
        do {
            collectionState.markOpening()
            try reopenCollection(for: selectedUser)
            refreshID = UUID()
            collectionState.markReady()
        } catch {
            collectionState.markFailed(error.localizedDescription)
            userSwitchError = error.localizedDescription
            showUserSwitchError = true
        }
    }

    private func reopenCollection(for user: String) throws {
        let urls = AppUserStore.collectionURLs(for: user)
        try? backend.closeCollection()

        try FileManager.default.createDirectory(
            at: urls.directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: urls.mediaDirectory,
            withIntermediateDirectories: true
        )

        try backend.openCollection(
            collectionPath: urls.collection.path,
            mediaFolderPath: urls.mediaDirectory.path,
            mediaDbPath: urls.mediaDB.path
        )

        NotificationCenter.default.post(name: AppCollectionEvents.didOpenNotification, object: nil)

        _ = try? backend.call(
            service: AnkiBackend.Service.collection,
            method: AnkiBackend.CheckDatabaseMethod.checkDatabase
        )
    }

    private func presentExportOptions() {
        guard collectionState.isReady, !isImportExportInProgress else { return }

        Task {
            let decks = await loadExportDeckOptions()
            await MainActor.run {
                exportDecks = decks
                if !decks.contains(where: { $0.id == exportDraft.selectedDeckID }) {
                    exportDraft.selectedDeckID = decks.first?.id
                }
                showExportOptions = true
            }
        }
    }

    private func reloadReaderTabPreference() {
        isReaderTabEnabled = UserDefaults.standard.object(forKey: ReaderPreferences.Keys.showTab) as? Bool ?? false
    }

    private func startExport(using draft: ExportPackageDraft) {
        guard collectionState.isReady, !isImportExportInProgress else { return }

        Task {
            var resolvedDraft = draft
            let resolvedDecks = exportDecks.isEmpty ? await loadExportDeckOptions() : exportDecks
            await MainActor.run {
                if exportDecks != resolvedDecks {
                    exportDecks = resolvedDecks
                }
                if !resolvedDecks.contains(where: { $0.id == exportDraft.selectedDeckID }) {
                    exportDraft.selectedDeckID = resolvedDecks.first?.id
                }
                resolvedDraft.selectedDeckID = exportDraft.selectedDeckID
            }

            let configuration: ImportHelper.ExportPackageConfiguration
            switch resolvedDraft.kind {
            case .collectionPackage:
                configuration = .collection(
                    includeMedia: resolvedDraft.includeMedia,
                    legacy: resolvedDraft.legacySupport
                )
            case .deckPackage:
                guard let deck = resolvedDecks.first(where: { $0.id == resolvedDraft.selectedDeckID }) else {
                    await MainActor.run {
                        importMessage = L("review_no_decks_available")
                        showExportNotice = true
                    }
                    return
                }
                configuration = .deck(
                    deckID: deck.id,
                    deckName: deck.name,
                    includeScheduling: resolvedDraft.includeScheduling,
                    includeDeckConfigs: resolvedDraft.includeDeckConfigs,
                    includeMedia: resolvedDraft.includeMedia,
                    legacy: resolvedDraft.legacySupport
                )
            case .selectedNotesPackage:
                await MainActor.run {
                    importMessage = L("common_unknown_error")
                    showExportNotice = true
                }
                return
            }

            await MainActor.run {
                importExportOperation = .exporting
            }

            do {
                let backend = self.backend
                let url = try await Task.detached(priority: .userInitiated) {
                    try ImportHelper.exportPackage(backend: backend, configuration: configuration)
                }.value
                await MainActor.run {
                    exportedFileURL = url
                    showExportShareSheet = true
                }
            } catch {
                await MainActor.run {
                    importMessage = L("debug_export_error", error.localizedDescription)
                    showExportNotice = true
                }
            }

            await MainActor.run {
                importExportOperation = nil
            }
        }
    }

    private func loadExportDeckOptions() async -> [DeckInfo] {
        let attempts: [() throws -> [DeckInfo]] = [
            { try deckClient.fetchNamesOnly() },
            { try deckClient.fetchAll() },
            { flattenDeckOptions(from: try deckClient.fetchTree()) },
            { flattenDeckOptions(from: DeckTreeCache.load()) }
        ]

        for pass in 0..<2 {
            for attempt in attempts {
                if let decks = try? attempt() {
                    let sortedDecks = decks.sorted { $0.name < $1.name }
                    if sortedDecks.isEmpty == false {
                        return sortedDecks
                    }
                }
            }

            if pass == 0 {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        return []
    }

    private func flattenDeckOptions(from nodes: [DeckTreeNode]) -> [DeckInfo] {
        nodes
            .flatMap { node -> [DeckInfo] in
                [
                    DeckInfo(id: node.id, name: node.fullName, counts: node.counts)
                ] + flattenDeckOptions(from: node.children)
            }
            .sorted { $0.name < $1.name }
    }

    @MainActor
    private func reloadSplitSidebarContext() async {
        guard collectionState.isReady else {
            splitDeckTree = DeckTreeCache.load()
            splitDeckOptions = []
            splitBrowseTags = []
            splitBrowseNotetypes = []
            splitReaderRecentBooks = []
            splitShell.decks.selectedDeckID = nil
            splitShell.decks.expandedDeckIDs = normalizedExpandedDeckIDs(for: splitDeckTree)
            splitShell.browse.selectedDeckID = nil
            splitShell.browse.selectedTag = nil
            splitShell.browse.selectedNotetypeID = nil
            splitShell.browse.selectedFlag = nil
            splitShell.stats.selectedDeckID = nil
            splitShell.reader.selectedBookID = nil
            return
        }

        async let decksLoad: [DeckInfo] = loadExportDeckOptions()
        async let deckTreeLoad: [DeckTreeNode] = loadSplitDeckTree()
        async let notetypesLoad: [BrowseSidebarNotetypeOption] = loadSplitBrowseNotetypes()
        let decks = await decksLoad
        let deckTree = await deckTreeLoad
        let notetypes = await notetypesLoad
        let tags = await loadSplitBrowseTagsForCurrentDeck(using: decks)
        let readerRecentBooks = isReaderTabEnabled ? loadSplitReaderRecentBooks(using: decks) : []

        splitDeckTree = deckTree
        splitDeckOptions = decks
        splitBrowseTags = tags
        splitBrowseNotetypes = notetypes
        splitReaderRecentBooks = readerRecentBooks

        if !decks.contains(where: { $0.id == splitShell.decks.selectedDeckID }) {
            splitShell.decks.selectedDeckID = nil
        }
        splitShell.decks.expandedDeckIDs = normalizedExpandedDeckIDs(for: deckTree)
        if !decks.contains(where: { $0.id == splitShell.browse.selectedDeckID }) {
            splitShell.browse.selectedDeckID = nil
        }
        if !decks.contains(where: { $0.id == splitShell.stats.selectedDeckID }) {
            splitShell.stats.selectedDeckID = nil
        }
        if let selectedTag = splitShell.browse.selectedTag, !tags.contains(selectedTag) {
            splitShell.browse.selectedTag = nil
        }
        if let selectedNotetypeID = splitShell.browse.selectedNotetypeID,
           !notetypes.contains(where: { $0.id == selectedNotetypeID }) {
            splitShell.browse.selectedNotetypeID = nil
        }
    }

    @MainActor
    private func reloadSplitBrowseTags() async {
        guard collectionState.isReady else {
            splitBrowseTags = []
            splitShell.browse.selectedTag = nil
            return
        }

        let tags = await loadSplitBrowseTagsForCurrentDeck()
        splitBrowseTags = tags
        if let selectedTag = splitShell.browse.selectedTag, !tags.contains(selectedTag) {
            splitShell.browse.selectedTag = nil
        }
    }

    @MainActor
    private func reloadSplitDeckOptions() async {
        guard collectionState.isReady else {
            splitDeckTree = DeckTreeCache.load()
            splitDeckOptions = []
            splitShell.decks.selectedDeckID = nil
            splitShell.decks.expandedDeckIDs = normalizedExpandedDeckIDs(for: splitDeckTree)
            splitShell.browse.selectedDeckID = nil
            splitShell.stats.selectedDeckID = nil
            return
        }

        async let decksLoad: [DeckInfo] = loadExportDeckOptions()
        async let deckTreeLoad: [DeckTreeNode] = loadSplitDeckTree()
        let (decks, deckTree) = await (decksLoad, deckTreeLoad)

        splitDeckTree = deckTree
        splitDeckOptions = decks

        if !decks.contains(where: { $0.id == splitShell.decks.selectedDeckID }) {
            splitShell.decks.selectedDeckID = nil
        }
        splitShell.decks.expandedDeckIDs = normalizedExpandedDeckIDs(for: deckTree)
        if !decks.contains(where: { $0.id == splitShell.browse.selectedDeckID }) {
            splitShell.browse.selectedDeckID = nil
        }
        if !decks.contains(where: { $0.id == splitShell.stats.selectedDeckID }) {
            splitShell.stats.selectedDeckID = nil
        }
    }

    private func loadSplitDeckTree() async -> [DeckTreeNode] {
        if let tree = try? deckClient.fetchTree() {
            return tree
        }
        return DeckTreeCache.load()
    }

    private func loadSplitBrowseTagsForCurrentDeck(using decks: [DeckInfo]? = nil) async -> [String] {
        do {
            let availableDecks = decks ?? splitDeckOptions
            if let selectedDeck = availableDecks.first(where: { $0.id == splitShell.browse.selectedDeckID }) {
                let noteIDs = try noteClient.searchIds("deck:\"\(selectedDeck.name)\"")
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
                return tagSet.sorted()
            }
            return try tagClient.getAllTags().sorted()
        } catch {
            return []
        }
    }

    private func loadSplitBrowseNotetypes() async -> [BrowseSidebarNotetypeOption] {
        do {
            let response: Anki_Notetypes_NotetypeNames = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetypeNames
            )
            return response.entries
                .map { BrowseSidebarNotetypeOption(id: $0.id, name: $0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            return []
        }
    }

    private func loadSplitReaderRecentBooks(using decks: [DeckInfo]) -> [ReaderSidebarBookSummary] {
        let noteBooks = loadSplitReaderNoteBooks(using: decks)
        let epubBooks = (try? readerEpubLibraryClient.loadState().books) ?? []

        let noteItems = noteBooks.map { book in
            ReaderSidebarBookSummary(
                id: "anki:\(book.id)",
                title: book.title,
                source: .ankiNotes,
                lastAccess: ReaderProgressStore.load(bookID: book.id)?.updatedAt ?? .distantPast
            )
        }
        let epubItems = epubBooks.map { book in
            let trimmedTitle = (book.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return ReaderSidebarBookSummary(
                id: "epub:\(book.id.uuidString)",
                title: trimmedTitle.isEmpty ? book.id.uuidString : trimmedTitle,
                source: .epub,
                lastAccess: book.lastAccess
            )
        }

        return Array(
            (noteItems + epubItems)
                .filter { $0.lastAccess > .distantPast }
                .sorted { lhs, rhs in
                    if lhs.lastAccess != rhs.lastAccess {
                        return lhs.lastAccess > rhs.lastAccess
                    }
                    let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    if titleComparison != .orderedSame {
                        return titleComparison == .orderedAscending
                    }
                    return lhs.id < rhs.id
                }
                .prefix(8)
        )
    }

    private func loadSplitReaderNoteBooks(using decks: [DeckInfo]) -> [ReaderBook] {
        let defaults = UserDefaults.standard
        let selectedDeckID = defaults.integer(forKey: ReaderPreferences.Keys.deckID)
        guard selectedDeckID != 0,
              let selectedDeck = decks.first(where: { Int($0.id) == selectedDeckID }) else {
            return []
        }

        let bookIDField = defaults.string(forKey: ReaderPreferences.Keys.bookIDField) ?? ""
        let bookTitleField = defaults.string(forKey: ReaderPreferences.Keys.bookTitleField) ?? ""
        let bookCoverField = defaults.string(forKey: ReaderPreferences.Keys.bookCoverField) ?? ""
        let chapterTitleField = defaults.string(forKey: ReaderPreferences.Keys.chapterTitleField) ?? ""
        let chapterOrderField = defaults.string(forKey: ReaderPreferences.Keys.chapterOrderField) ?? ""
        let contentField = defaults.string(forKey: ReaderPreferences.Keys.contentField) ?? ""
        let languageField = defaults.string(forKey: ReaderPreferences.Keys.languageField) ?? ""

        guard !bookIDField.isEmpty,
              !bookTitleField.isEmpty,
              !chapterTitleField.isEmpty,
              !chapterOrderField.isEmpty,
              !contentField.isEmpty else {
            return []
        }

        let selectedNotetypeID = defaults.integer(forKey: ReaderPreferences.Keys.notetypeID)
        let configuration = ReaderLibraryConfiguration(
            deckName: selectedDeck.name,
            notetypeID: selectedNotetypeID == 0 ? nil : Int64(selectedNotetypeID),
            fieldMapping: ReaderFieldMapping(
                bookIDField: bookIDField,
                bookTitleField: bookTitleField,
                bookCoverField: bookCoverField.isEmpty ? nil : bookCoverField,
                chapterTitleField: chapterTitleField,
                chapterOrderField: chapterOrderField,
                contentField: contentField,
                languageField: languageField.isEmpty ? nil : languageField
            )
        )
        return (try? readerBookClient.loadBooks(configuration)) ?? []
    }

    private func splitSidebarFlagColor(for filter: BrowseQuickFilter) -> Color {
        guard let index = BrowseQuickFilter.flagCases.firstIndex(of: filter) else {
            return .secondary
        }

        switch index + 1 {
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

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            prepareImport(from: url)
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func handleIncomingImportURL(_ url: URL) {
        guard url.isFileURL else { return }
        prepareImport(from: url, requiresSecurityScope: true)
    }

    private func consumePendingIncomingImportURLIfNeeded() {
        guard collectionState.isReady, let incomingImportURL else { return }
        self.incomingImportURL = nil
        handleIncomingImportURL(incomingImportURL)
    }

    private func prepareImport(from url: URL, requiresSecurityScope: Bool = false) {
        let ext = url.pathExtension.lowercased()
        guard ext == "apkg" || ext == "colpkg" else {
            if requiresSecurityScope {
                _ = url.stopAccessingSecurityScopedResource()
            }
            importMessage = "Unsupported file type. Please select an .apkg or .colpkg file."
            showImportAlert = true
            return
        }

        if pendingImportNeedsSecurityScope, let pendingImportURL {
            pendingImportURL.stopAccessingSecurityScopedResource()
            pendingImportNeedsSecurityScope = false
            self.pendingImportURL = nil
        }

        if requiresSecurityScope {
            let didStart = url.startAccessingSecurityScopedResource()
            pendingImportNeedsSecurityScope = didStart
        } else {
            pendingImportNeedsSecurityScope = false
        }

        pendingImportURL = url
        importDraft = ImportPackageDraft()
        showImportOptions = true
    }

    private func startImport(from url: URL, configuration: ImportHelper.ImportPackageConfiguration) {
        guard collectionState.isReady, !isImportExportInProgress else { return }

        importExportOperation = .importing
        let backend = self.backend
        let shouldStopSecurityScope = pendingImportNeedsSecurityScope
        pendingImportNeedsSecurityScope = false
        Task {
            defer {
                if shouldStopSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
                importExportOperation = nil
                showImportAlert = true
            }

            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try ImportHelper.importPackage(from: url, backend: backend, configuration: configuration)
                }.value

                do {
                    try reopenCollection(for: selectedUser)
                    Swift.print("[ContentView] Reopened collection after import for user=\(selectedUser)")
                } catch {
                    Swift.print("[ContentView] Failed to reopen collection after import for user=\(selectedUser): \(error)")
                }
                importMessage = summary
                refreshID = UUID()
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func cancelPendingImport() {
        if pendingImportNeedsSecurityScope, let pendingImportURL {
            pendingImportURL.stopAccessingSecurityScopedResource()
        }
        pendingImportNeedsSecurityScope = false
        pendingImportURL = nil
        showImportOptions = false
    }
}

private struct SplitDeckSidebarTreeRow: View {
    let node: DeckTreeNode
    let depth: Int
    @Binding var expandedDeckIDs: Set<Int64>
    @Binding var selectedDeckID: Int64?
    let onSelect: (Int64?) -> Void

    private var hasChildren: Bool {
        !node.children.isEmpty
    }

    private var isExpanded: Bool {
        expandedDeckIDs.contains(node.id)
    }

    private var isSelected: Bool {
        selectedDeckID == node.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if hasChildren {
                    Button {
                        if isExpanded {
                            expandedDeckIDs.remove(node.id)
                        } else {
                            expandedDeckIDs.insert(node.id)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.amgiTextSecondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 16, height: 16)
                }

                Button {
                    onSelect(node.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(node.name)
                            .foregroundStyle(Color.amgiTextPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if node.counts.total > 0 {
                            Text("\(node.counts.total)")
                                .font(.caption2)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * 14)

            if hasChildren && isExpanded {
                ForEach(node.children) { child in
                    SplitDeckSidebarTreeRow(
                        node: child,
                        depth: depth + 1,
                        expandedDeckIDs: $expandedDeckIDs,
                        selectedDeckID: $selectedDeckID,
                        onSelect: onSelect
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CollectionPreparingView: View {
    var body: some View {
        ContentUnavailableView(
            L("deck_list_nav_title"),
            systemImage: "externaldrive",
            description: Text(L("collection_preparing"))
        )
        .background(Color.amgiBackground)
    }
}
