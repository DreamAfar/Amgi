import SwiftUI
import AnkiBackend
import Dependencies

struct UserManagementView: View {
    @Dependency(\.ankiBackend) var backend
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
    @State private var operationError: String?

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
                                Label(L("common_selected"), systemImage: "checkmark.circle.fill")
                                    .labelStyle(.iconOnly)
                                    .amgiStatusBadge(.positive)
                            }
                        }
                        .listRowBackground(Color.amgiSurfaceElevated)
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
                do {
                    try addUser()
                } catch {
                    operationError = error.localizedDescription
                }
            }
        }
        .alert(L("user_mgmt_rename_title"), isPresented: $showRenamePrompt) {
            TextField(L("user_mgmt_new_username_placeholder"), text: $renameText)
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_save")) {
                do {
                    try renameSelectedUser()
                } catch {
                    operationError = error.localizedDescription
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
                do {
                    try deleteSelectedUser()
                } catch {
                    operationError = error.localizedDescription
                }
            }
        } message: {
            Text(L("user_mgmt_delete_confirm2_msg"))
        }
        .alert(L("common_error"), isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(operationError ?? L("common_none"))
        }
    }

    private func deleteSelectedUser() throws {
        guard let target = deleteTarget else { return }

        let deletingCurrentUser = selectedUser == target
        var updatedUsers = users.filter { $0 != target }
        if updatedUsers.isEmpty {
            updatedUsers = [L("user_mgmt_default_user")]
        }
        let replacementUser = updatedUsers[0]

        if deletingCurrentUser {
            try? backend.closeCollection()
        }

        try AppUserStore.deleteUserData(for: target)

        users = updatedUsers
        AppUserStore.saveUsers(updatedUsers)

        if deletingCurrentUser {
            selectedUser = replacementUser
            AppUserStore.setSelectedUser(replacementUser)
            NotificationCenter.default.post(name: AppCollectionEvents.didResetNotification, object: nil)
        }

        deleteTarget = nil
    }

    private func addUser() throws {
        let trimmed = newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !users.contains(trimmed) else {
            throw UserManagementError.nameExists
        }
        guard !AppUserStore.hasScopeConflict(for: trimmed, existingUsers: users) else {
            throw UserManagementError.scopeConflict
        }

        users.append(trimmed)
        AppUserStore.saveUsers(users)
        selectedUser = trimmed
        AppUserStore.setSelectedUser(trimmed)
    }

    private func renameSelectedUser() throws {
        guard let old = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != old else { return }
        guard !users.contains(trimmed) else {
            throw UserManagementError.nameExists
        }
        guard !AppUserStore.hasScopeConflict(for: trimmed, existingUsers: users, excluding: old) else {
            throw UserManagementError.scopeConflict
        }

        let renamingCurrentUser = selectedUser == old
        let profileChanged = AppUserStore.profileID(for: old) != AppUserStore.profileID(for: trimmed)

        if renamingCurrentUser && profileChanged {
            try? backend.closeCollection()
        }

        try AppUserStore.renameUserData(from: old, to: trimmed)

        if let idx = users.firstIndex(of: old) {
            users[idx] = trimmed
            AppUserStore.saveUsers(users)
        }
        if renamingCurrentUser {
            selectedUser = trimmed
            AppUserStore.setSelectedUser(trimmed)
            if profileChanged {
                NotificationCenter.default.post(name: AppCollectionEvents.didResetNotification, object: nil)
            }
        }

        renameTarget = nil
    }
}

private enum UserManagementError: LocalizedError {
    case nameExists
    case scopeConflict

    var errorDescription: String? {
        switch self {
        case .nameExists:
            return L("user_mgmt_name_exists")
        case .scopeConflict:
            return L("user_mgmt_scope_conflict")
        }
    }
}
