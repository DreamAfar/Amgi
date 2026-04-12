import SwiftUI
import AnkiSync
import AnkiClients
import AnkiBackend
import Dependencies
import Foundation

struct ContentView: View {
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

    @State private var showSync = false
    @State private var showImport = false
    @State private var refreshID = UUID()
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showExportNotice = false
    @State private var exportedFileURL: URL?
    @State private var showExportShareSheet = false
    @State private var importExportOperation: ImportExportOperation?
    @State private var showAddDeckPrompt = false
    @State private var newDeckName = ""
    @State private var showUserManager = false
    @State private var users: [String] = AppUserStore.loadUsers()
    @State private var selectedUser: String = AppUserStore.loadSelectedUser()
    @State private var isSwitchingUser = false
    @State private var userSwitchError: String?
    @State private var showUserSwitchError = false

    private var isLocalMode: Bool {
        UserDefaults.standard.string(forKey: "syncMode") == "local"
    }

    private var isImportExportInProgress: Bool {
        importExportOperation != nil
    }

    var body: some View {
        ZStack {
            TabView {
                Tab(L("tab_decks"), systemImage: "rectangle.stack") {
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
                Tab(role: .search) {
                    NavigationStack {
                        BrowseView()
                            .id(refreshID)
                    }
                }
                Tab(L("tab_stats"), systemImage: "chart.bar") {
                    NavigationStack {
                        StatsDashboardView()
                            .id(refreshID)
                    }
                }
                Tab(L("tab_settings"), systemImage: "gearshape") {
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
            refreshID = UUID()
        } content: {
            SyncSheet(isPresented: $showSync)
        }
        .sheet(isPresented: $showUserManager, onDismiss: reloadUsers) {
            UserManagementView()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppUserStore.didChangeNotification)) { _ in
            reloadUsers()
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
                    .font(.headline)
                Text(L("import_export_progress_detail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
        }
        .transition(.opacity)
    }

    private var userMenu: some View {
        Button {
            showUserManager = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSwitchingUser ? "arrow.triangle.2.circlepath.circle" : "person.crop.circle")
                Text(selectedUser)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSwitchingUser)
    }

    private var trailingActions: some View {
        HStack(spacing: 14) {
            Button {
                showSync = true
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }

            Menu {
                Button(L("menu_add_deck")) {
                    showAddDeckPrompt = true
                }
                Button(L("menu_export_deck")) {
                    exportCollection()
                }
                if isLocalMode {
                    Divider()
                    Button(L("menu_import_apkg")) {
                        showImport = true
                    }
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
            importMessage = "Create deck failed: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func switchUser(to user: String) async {
        guard user != selectedUser, !isSwitchingUser else { return }

        isSwitchingUser = true
        defer { isSwitchingUser = false }

        do {
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

            selectedUser = user
            AppUserStore.setSelectedUser(user)
            refreshID = UUID()
        } catch {
            userSwitchError = error.localizedDescription
            showUserSwitchError = true
        }
    }

    private func exportCollection() {
        guard !isImportExportInProgress else { return }

        importExportOperation = .exporting
        Task {
            defer { importExportOperation = nil }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try ImportHelper.exportCollection(backend: backend)
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
            startImport(from: url)
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func startImport(from url: URL) {
        guard !isImportExportInProgress else { return }

        importExportOperation = .importing
        Task {
            defer {
                importExportOperation = nil
                showImportAlert = true
            }

            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try ImportHelper.importPackage(from: url, backend: backend)
                }.value
                importMessage = summary
                refreshID = UUID()
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}
