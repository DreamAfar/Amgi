import SwiftUI
import AnkiSync
import AnkiClients
import AnkiBackend
import AnkiKit
import AnkiProto
import AmgiReader
import AmgiTheme
import Dependencies
import Foundation
import OSLog
import UIKit
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "amgi", category: "startup")

struct ContentView: View {
    @Binding var incomingImportURL: URL?
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var deckNoticeMessage: String?
    @State private var showDeckNotice = false
    @State private var exportNoticeMessage: String?
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
    @State private var pendingSyncAlert: AppPendingSyncAlert?
    @State private var showPendingSyncAlert = false
    @State private var isAutomaticSyncCheckRunning = false
    @State private var lastAutomaticSyncCheckAt = Date.distantPast
    @State private var exportDecks: [DeckInfo] = []
    @State private var exportDraft = ExportPackageDraft()
    @State private var importDraft = ImportPackageDraft()
    @State private var selectedTab: RootTab = .decks
    @State private var isReaderTabEnabled = false

    private var isImportExportInProgress: Bool {
        importExportOperation != nil
    }

    private var shouldUseSearchRoleForBrowseTab: Bool {
        UIDevice.current.userInterfaceIdiom != .pad
    }

    private var usesIPadTabOrdering: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        let rootContent = contentRootView
        let presentationContent = contentPresentationShell(rootContent)
        let observerContent = contentObserverShell(presentationContent)
        return contentAlertShell(observerContent)
    }

    private var contentRootView: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            rootTabView
                .disabled(isImportExportInProgress)

            if let importExportOperation {
                importExportOverlay(for: importExportOperation)
            }
        }
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
        }
    }

    // MARK: - Tabs
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

    // MARK: - Stats Tab
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
    // MARK: - Settings Tab
    private var settingsTab: some TabContent<RootTab> {
        Tab(L("tab_settings"), systemImage: "gearshape", value: RootTab.settings) {
            SettingsView()
                .id(refreshID)
        }
    }

    @TabContentBuilder<RootTab>
    private var rootTabs: some TabContent<RootTab> {
        if usesIPadTabOrdering {
            decksTab
            statsTab
            readerTab
            browseTab
            settingsTab
        } else {
            decksTab
            browseTab
            statsTab
            readerTab
            settingsTab
        }
    }

    // The root TabView with sidebar style for iPad and default style for iPhone.
    private var rootTabView: some View {
        TabView(selection: $selectedTab) {
            rootTabs
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    private func contentObserverShell<Content: View>(_ content: Content) -> some View {
        content
            .task {
                reloadReaderTabPreference()
                updateSyncBadge()
                consumePendingSyncAlertIfNeeded()
                if collectionState.isReady {
                    consumePendingIncomingImportURLIfNeeded()
                    runCheckDatabaseIfReady()
                    runAutomaticSyncCheckIfReady()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didOpenNotification)) { _ in
                updateSyncBadge()
                consumePendingSyncAlertIfNeeded()
                consumePendingIncomingImportURLIfNeeded()
                runCheckDatabaseIfReady()
                runAutomaticSyncCheckIfReady()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didResetNotification)) { _ in
                Task { await reopenCurrentCollectionAfterReset() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.openDeckListNotification)) { _ in
                selectedTab = .decks
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.openBrowseSearchNotification)) { _ in
                selectedTab = .browse
            }
            .onReceive(NotificationCenter.default.publisher(for: AppSyncAuthEvents.didChangeNotification)) { _ in
                updateSyncBadge()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                reloadReaderTabPreference()
            }
            .onReceive(syncCoordinator.$state) { _ in
                updateSyncBadge()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                consumePendingSyncAlertIfNeeded()
            }
            .onChange(of: collectionState.isReady) { _, isReady in
                guard isReady else { return }
                consumePendingIncomingImportURLIfNeeded()
                runCheckDatabaseIfReady()
                updateSyncBadge()
                consumePendingSyncAlertIfNeeded()
                runAutomaticSyncCheckIfReady()
            }
            .onChange(of: isReaderTabEnabled) { _, isEnabled in
                if !isEnabled, selectedTab == .reader {
                    selectedTab = .settings
                }
            }
    }

    private func contentAlertShell<Content: View>(_ content: Content) -> some View {
        content
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
                NavigationStack {
                    if let pendingImportURL {
                        ImportOptionsView(
                            fileName: pendingImportURL.lastPathComponent,
                            fileExtension: pendingImportURL.pathExtension,
                            draft: $importDraft,
                            onCancel: {
                                cancelPendingImport()
                            },
                            onImport: {
                                showImportOptions = false
                                startImport(from: pendingImportURL, configuration: importDraft.configuration)
                            }
                        )
                    } else {
                        EmptyView()
                    }
                }
            }
            .sheet(isPresented: $showExportShareSheet) {
                if let exportedFileURL {
                    ShareSheet(items: [exportedFileURL])
                }
            }
            .fileImporter(
                isPresented: $showImport,
                allowedContentTypes: [
                    UTType(filenameExtension: "apkg") ?? .data,
                    UTType(filenameExtension: "colpkg") ?? .data
                ]
            ) { result in
                handleImport(result)
            }
            .alert(L("alert_new_deck_title"), isPresented: $showAddDeckPrompt) {
                TextField(L("alert_new_deck_title"), text: $newDeckName)
                    .autocorrectionDisabled()
                Button(L("btn_cancel"), role: .cancel) {}
                Button(L("btn_save")) {
                    Task { await createDeck() }
                }
            } message: {
                Text(L("alert_new_deck_message"))
            }
            .alert(L("alert_import_title"), isPresented: $showImportAlert) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(importMessage ?? L("common_unknown_error"))
            }
            .alert(L("alert_new_deck_title"), isPresented: $showDeckNotice) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(deckNoticeMessage ?? L("common_unknown_error"))
            }
            .alert(L("menu_export_deck"), isPresented: $showExportNotice) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(exportNoticeMessage ?? L("common_unknown_error"))
            }
            .alert(L("common_error"), isPresented: $showUserSwitchError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(userSwitchError ?? L("common_unknown_error"))
            }
            .alert(
                L("sync_background_alert_title"),
                isPresented: $showPendingSyncAlert,
                presenting: pendingSyncAlert
            ) { _ in
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("sync_background_alert_open")) {
                    showSync = true
                }
            } message: { alert in
                Text(syncAlertMessage(for: alert))
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
                    .foregroundStyle(palette.textPrimary)
                Text(L("import_export_progress_detail"))
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 300)
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(palette.border.opacity(0.22), lineWidth: 1)
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
                    .foregroundStyle(palette.textSecondary)
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
                        .foregroundStyle(palette.textPrimary)
                }
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .padding(.top, 3)
                        .padding(.trailing, 3)
                    if showSyncBadge {
                        Circle()
                            .fill(palette.danger)  // red badge
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

        if pendingSyncAlert != nil {
            showSyncBadge = true
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

    private func consumePendingSyncAlertIfNeeded() {
        guard let alert = AppBackgroundSyncManager.consumePendingAlert() else {
            return
        }

        pendingSyncAlert = alert
        showPendingSyncAlert = true
        showSyncBadge = true
    }

    private func runAutomaticSyncCheckIfReady() {
        guard collectionState.isReady else { return }
        guard KeychainHelper.loadHostKey() != nil else { return }
        guard isAutomaticSyncCheckRunning == false else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAutomaticSyncCheckAt) > 5 else { return }
        lastAutomaticSyncCheckAt = now
        isAutomaticSyncCheckRunning = true

        Task {
            defer {
                Task { @MainActor in
                    isAutomaticSyncCheckRunning = false
                }
            }

            do {
                let status = try await syncClient.syncStatus()
                await MainActor.run {
                    if let alert = AppBackgroundSyncManager.automaticForegroundAlert(for: status) {
                        pendingSyncAlert = alert
                        showPendingSyncAlert = true
                        showSyncBadge = true
                    } else if status.hasChanges {
                        showSyncBadge = true
                    } else {
                        updateSyncBadge()
                    }
                }
            } catch {
                logger.debug("Foreground sync status check failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncAlertMessage(for alert: AppPendingSyncAlert) -> String {
        let body: String
        switch alert.kind {
        case .fullSyncRequired:
            body = L("sync_background_alert_full_sync")
        case .fullDownloadRequired:
            body = L("sync_background_alert_full_download")
        case .fullUploadRequired:
            body = L("sync_background_alert_full_upload")
        case .conflict:
            body = L("sync_background_alert_conflict")
        }

        guard let serverMessage = alert.serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              serverMessage.isEmpty == false else {
            return body
        }
        return body + "\n\n" + serverMessage
    }

    private func createDeck() async {
        guard collectionState.isReady else { return }
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try deckClient.create(name)
            refreshID = UUID()
            deckNoticeMessage = name
            showDeckNotice = true
            newDeckName = ""
        } catch {
            deckNoticeMessage = L("alert_new_deck_failed", error.localizedDescription)
            showDeckNotice = true
        }
    }

    private func switchUser(to user: String) async {
        guard user != selectedUser, !isSwitchingUser else { return }

        isSwitchingUser = true
        defer { isSwitchingUser = false }

        do {
            collectionState.markOpening()
            try await reopenCollection(for: user)

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
            try await reopenCollection(for: selectedUser)
            refreshID = UUID()
            collectionState.markReady()
        } catch {
            collectionState.markFailed(error.localizedDescription)
            userSwitchError = error.localizedDescription
            showUserSwitchError = true
        }
    }

    private func reopenCollection(for user: String) async throws {
        _ = try await AppBackendRuntime.shared.reopenCollection(
            preferredLangs: AppCollectionBootstrap.preferredBackendLangsFromDefaults(),
            username: user
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
                        exportNoticeMessage = L("review_no_decks_available")
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
                    exportNoticeMessage = L("common_unknown_error")
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
                    exportNoticeMessage = L("debug_export_error", error.localizedDescription)
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
                url.stopAccessingSecurityScopedResource()
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
                    try await reopenCollection(for: selectedUser)
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

// MARK: - CollectionPreparingView

private struct CollectionPreparingView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ContentUnavailableView(
            L("deck_list_nav_title"),
            systemImage: "externaldrive",
            description: Text(L("collection_preparing"))
        )
        .background(palette.background)
    }
}
