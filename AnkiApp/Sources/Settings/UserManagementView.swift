import SwiftUI

struct UserManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var users: [String] = AppUserStore.loadUsers()
    @State private var selectedUser: String = AppUserStore.loadSelectedUser()
    @State private var showAddPrompt = false
    @State private var newUserName = ""

    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var showRenamePrompt = false

    @State private var deleteTarget: String?
    @State private var showDeleteConfirmStep1 = false
    @State private var showDeleteConfirmStep2 = false

    var body: some View {
        NavigationStack {
            List {
                Section("已登录账户") {
                    ForEach(users, id: \.self) { user in
                        HStack {
                            Text(user)
                            Spacer()
                            if selectedUser == user {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedUser = user
                            AppUserStore.setSelectedUser(user)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                renameTarget = user
                                renameText = user
                                showRenamePrompt = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                deleteTarget = user
                                showDeleteConfirmStep1 = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("用户管理")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newUserName = ""
                        showAddPrompt = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("添加用户", isPresented: $showAddPrompt) {
            TextField("用户名", text: $newUserName)
            Button("取消", role: .cancel) {}
            Button("添加") {
                let trimmed = newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if !users.contains(trimmed) {
                    users.append(trimmed)
                    AppUserStore.saveUsers(users)
                }
                selectedUser = trimmed
                AppUserStore.setSelectedUser(trimmed)
            }
        }
        .alert("重命名用户", isPresented: $showRenamePrompt) {
            TextField("新用户名", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                guard let old = renameTarget else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let idx = users.firstIndex(of: old) {
                    users[idx] = trimmed
                    AppUserStore.saveUsers(users)
                }
                if selectedUser == old {
                    selectedUser = trimmed
                    AppUserStore.setSelectedUser(trimmed)
                }
            }
        }
        .alert("删除用户（第1次确认）", isPresented: $showDeleteConfirmStep1) {
            Button("取消", role: .cancel) {}
            Button("继续") {
                showDeleteConfirmStep2 = true
            }
        } message: {
            Text("即将删除用户，请再次确认。")
        }
        .alert("删除用户（第2次确认）", isPresented: $showDeleteConfirmStep2) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                guard let target = deleteTarget else { return }
                users.removeAll { $0 == target }
                if users.isEmpty {
                    users = ["用户1"]
                }
                AppUserStore.saveUsers(users)
                if selectedUser == target {
                    selectedUser = users[0]
                    AppUserStore.setSelectedUser(users[0])
                }
            }
        } message: {
            Text("删除后不可恢复。")
        }
    }
}
