import SwiftUI
import AnkiSync
import AnkiClients
import AnkiBackend
import AnkiKit
import Dependencies
import Foundation
import OSLog

private let logger = Logger(subsystem: "amgi", category: "startup")

struct ContentView: View {
    private enum RootTab: Hashable {
        case decks
        case browse
        case stats
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

    @State private var showSync = false
    @State private var showImport = false
    @State private var showImportOptions = false
    @State private var refreshID = UUID()
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showExportNotice = false
    @State private var exportedFileURL: URL?
    @State private var pendingImportURL: URL?
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

    private var isImportExportInProgress: Bool {
        importExportOperation != nil
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
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
                Tab(role: .search, value: RootTab.browse) {
                    NavigationStack {
                        BrowseView(isActive: selectedTab == .browse)
                            .id(refreshID)
                    }
                }
                Tab(L("tab_stats"), systemImage: "chart.bar", value: RootTab.stats) {
                    NavigationStack {
                        StatsDashboardView(isActive: selectedTab == .stats)
                            .id(refreshID)
                    }
                }
                Tab(L("tab_settings"), systemImage: "gearshape", value: RootTab.settings) {
                    NavigationStack {
                        SettingsView()
                            .id(refreshID)
                    }
                }
            }
            .disabled(isImportExportInProgress)

            if let importExportOperation {
                importExportOverlay(for: importExportOperation)
            }
        }
        .sheet(isPresented: $showSync) {
            updateSyncBadge()
            refreshID = UUID()
        } content: {
            SyncSheet(isPresented: $showSync)
        }
        .sheet(isPresented: $showUserManager, onDismiss: reloadUsers) {
            UserManagementView()
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
                            self.pendingImportURL = nil
                            showImportOptions = false
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
        .onReceive(NotificationCenter.default.publisher(for: AppUserStore.didChangeNotification)) { _ in
            reloadUsers()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCollectionEvents.didResetNotification)) { _ in
            Task { await reopenCurrentCollectionAfterReset() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSyncAuthEvents.didChangeNotification)) { _ in
            updateSyncBadge()
        }
        .onReceive(syncCoordinator.$state) { _ in
            updateSyncBadge()
        }
        .task {
            updateSyncBadge()
            // CheckDatabase runs in background after UI is visible — avoids blocking cold start
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
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
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
        .sheet(isPresented: $showExportShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert(L("deck_action_error_title"), isPresented: $showUserSwitchError) {
            Button(L("btn_ok"), role: .cancel) {}
        } message: {
            Text(userSwitchError ?? L("label_error_unknown"))
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
        }
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

    private func createDeck() async {
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
            try reopenCollection(for: user)

            selectedUser = user
            AppUserStore.setSelectedUser(user)
            refreshID = UUID()
        } catch {
            userSwitchError = error.localizedDescription
            showUserSwitchError = true
        }
    }

    @MainActor
    private func reopenCurrentCollectionAfterReset() async {
        do {
            try reopenCollection(for: selectedUser)
            refreshID = UUID()
        } catch {
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

        _ = try? backend.call(
            service: AnkiBackend.Service.collection,
            method: AnkiBackend.CheckDatabaseMethod.checkDatabase
        )
    }

    private func presentExportOptions() {
        guard !isImportExportInProgress else { return }

        Task {
            let decks = ((try? deckClient.fetchAll()) ?? []).sorted { $0.name < $1.name }
            await MainActor.run {
                exportDecks = decks
                if !decks.contains(where: { $0.id == exportDraft.selectedDeckID }) {
                    exportDraft.selectedDeckID = decks.first?.id
                }
                showExportOptions = true
            }
        }
    }

    private func startExport(using draft: ExportPackageDraft) {
        guard !isImportExportInProgress else { return }

        let configuration: ImportHelper.ExportPackageConfiguration
        switch draft.kind {
        case .collectionPackage:
            configuration = .collection(
                includeMedia: draft.includeMedia,
                legacy: draft.legacySupport
            )
        case .deckPackage:
            guard let deck = exportDecks.first(where: { $0.id == draft.selectedDeckID }) else {
                importMessage = L("review_no_decks_available")
                showExportNotice = true
                return
            }
            configuration = .deck(
                deckID: deck.id,
                deckName: deck.name,
                includeScheduling: draft.includeScheduling,
                includeDeckConfigs: draft.includeDeckConfigs,
                includeMedia: draft.includeMedia,
                legacy: draft.legacySupport
            )
        case .selectedNotesPackage:
            importMessage = L("common_unknown_error")
            showExportNotice = true
            return
        }

        importExportOperation = .exporting
        let backend = self.backend
        Task {
            defer { importExportOperation = nil }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try ImportHelper.exportPackage(backend: backend, configuration: configuration)
                }.value
                exportedFileURL = url
                showExportShareSheet = true
            } catch {
                importMessage = L("debug_export_error", error.localizedDescription)
                showExportNotice = true
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let ext = url.pathExtension.lowercased()
            guard ext == "apkg" || ext == "colpkg" else {
                importMessage = "Unsupported file type. Please select an .apkg or .colpkg file."
                showImportAlert = true
                return
            }
            pendingImportURL = url
            importDraft = ImportPackageDraft()
            showImportOptions = true
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func startImport(from url: URL, configuration: ImportHelper.ImportPackageConfiguration) {
        guard !isImportExportInProgress else { return }

        importExportOperation = .importing
        let backend = self.backend
        Task {
            defer {
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
}
