import SwiftUI
import AnkiSync
import AnkiClients
import Dependencies

struct ContentView: View {
    @Dependency(\.deckClient) var deckClient

    @State private var showSync = false
    @State private var showImport = false
    @State private var refreshID = UUID()
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showExportNotice = false
    @State private var showAddDeckPrompt = false
    @State private var newDeckName = ""
    @State private var showUserManager = false
    @State private var users: [String] = AppUserStore.loadUsers()
    @State private var selectedUser: String = AppUserStore.loadSelectedUser()

    private var isLocalMode: Bool {
        UserDefaults.standard.string(forKey: "syncMode") == "local"
    }

    var body: some View {
        TabView {
            Tab("Decks", systemImage: "rectangle.stack") {
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
                                            selectedUser = user
                                            AppUserStore.setSelectedUser(user)
                                        } label: {
                                            if selectedUser == user {
                                                Label(user, systemImage: "checkmark")
                                            } else {
                                                Text(user)
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("用户管理设置") {
                                        showUserManager = true
                                    }
                                } label: {
                                    Label(selectedUser, systemImage: "person.crop.circle")
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
                                        Button("添加牌组") {
                                            showAddDeckPrompt = true
                                        }
                                        Button("导出牌组") {
                                            showExportNotice = true
                                        }
                                        if isLocalMode {
                                            Divider()
                                            Button("导入 .apkg/.colpkg") {
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
            Tab("Stats", systemImage: "chart.bar") {
                NavigationStack {
                    StatsDashboardView()
                        .id(refreshID)
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView()
                        .id(refreshID)
                }
            }
            Tab("Browse", systemImage: "magnifyingglass") {
                NavigationStack {
                    BrowseView()
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
        .alert("新建牌组", isPresented: $showAddDeckPrompt) {
            TextField("牌组名称", text: $newDeckName)
            Button("取消", role: .cancel) {
                newDeckName = ""
            }
            Button("创建") {
                Task { await createDeck() }
            }
        } message: {
            Text("请输入新牌组名称")
        }
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK") { }
        } message: {
            Text(importMessage ?? "")
        }
        .alert("导出牌组", isPresented: $showExportNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("导出功能将在下一步完善。")
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
            importMessage = "牌组 \(name) 创建成功"
            showImportAlert = true
            newDeckName = ""
        } catch {
            importMessage = "创建牌组失败: \(error.localizedDescription)"
            showImportAlert = true
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
