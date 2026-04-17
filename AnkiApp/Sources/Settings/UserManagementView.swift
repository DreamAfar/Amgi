import SwiftUI

struct UserManagementView: View {
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
                Section(L("user_mgmt_section_accounts")) {
                    ForEach(users, id: \.self) { user in
                        HStack {
                            Text(user)
                                .amgiFont(.body)
                                .foregroundStyle(Color.amgiTextPrimary)
                            Spacer()
                            if selectedUser == user {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.amgiPositive)
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
                                Label(L("user_mgmt_rename"), systemImage: "pencil")
                            }
                            .tint(Color.amgiAccent)

                            Button(role: .destructive) {
                                deleteTarget = user
                                showDeleteConfirmStep1 = true
                            } label: {
                                Label(L("common_delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(L("user_mgmt_title"))
            .toolbar {
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
        .alert(L("user_mgmt_add_title"), isPresented: $showAddPrompt) {
            TextField(L("user_mgmt_username_placeholder"), text: $newUserName)
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("user_mgmt_add_button")) {
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
        .alert(L("user_mgmt_rename_title"), isPresented: $showRenamePrompt) {
            TextField(L("user_mgmt_new_username_placeholder"), text: $renameText)
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_save")) {
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
        .alert(L("user_mgmt_delete_confirm1_title"), isPresented: $showDeleteConfirmStep1) {
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("user_mgmt_delete_continue")) {
                showDeleteConfirmStep2 = true
            }
        } message: {
            Text(L("user_mgmt_delete_confirm1_msg"))
        }
        .alert(L("user_mgmt_delete_confirm2_title"), isPresented: $showDeleteConfirmStep2) {
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("user_mgmt_delete_confirm_button"), role: .destructive) {
                guard let target = deleteTarget else { return }
                users.removeAll { $0 == target }
                if users.isEmpty {
                    users = [L("user_mgmt_default_user")]
                }
                AppUserStore.saveUsers(users)
                if selectedUser == target {
                    selectedUser = users[0]
                    AppUserStore.setSelectedUser(users[0])
                }
            }
        } message: {
            Text(L("user_mgmt_delete_confirm2_msg"))
        }
    }
}
