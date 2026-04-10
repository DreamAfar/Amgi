import SwiftUI
import AnkiSync
import AnkiClients
import AnkiBackend
import Dependencies
import Foundation

struct ContentView: View {
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

    var body: some View {
        TabView {
            Tab(L("tab_decks"), systemImage: "rectangle.stack") {
                NavigationStack {
                    DeckListView {
                        refreshID = UUID()
                    }
                        .id(refreshID)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Menu {
                                    ForEach(users, id: \.self) { user in
                                        Button {
                                            Task { await switchUser(to: user) }
                                        } label: {
                                            if selectedUser == user {
                                                Label(user, systemImage: "checkmark")
                                            } else {
                                                Text(user)
                                            }
                                        }
                                        .disabled(isSwitchingUser)
                                    }
                                    Divider()
                                    Button(L("menu_user_settings")) {
                                        showUserManager = true
                                    }
                                } label: {
                                    Label(selectedUser, systemImage: isSwitchingUser ? "arrow.triangle.2.circlepath.circle" : "person.crop.circle")
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
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
                                        Image(systemName: "square.and.arrow.up.on.square")
                                    }
                                }
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
        .sheet(isPresented: $showSync) {
            refreshID = UUID()
        } content: {
            SyncSheet(isPresented: $showSync)
        }
        .sheet(isPresented: $showUserManager, onDismiss: reloadUsers) {
            UserManagementView()
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

    private func reloadUsers() {
        users = AppUserStore.loadUsers()
        selectedUser = AppUserStore.loadSelectedUser()
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
                service: AnkiBackend.Service.checkDatabase,
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
        do {
            let url = try ImportHelper.exportCollection()
            exportedFileURL = url
            showExportShareSheet = true
        } catch {
            importMessage = L("debug_export_error", error.localizedDescription)
            showExportNotice = true
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
            do {
                let summary = try ImportHelper.importPackage(from: url)
                importMessage = summary
                refreshID = UUID()
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
            showImportAlert = true
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }
}
