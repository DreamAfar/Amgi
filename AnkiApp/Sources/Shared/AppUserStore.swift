import Foundation

enum AppUserStore {
    private static let usersKey = "amgi.users"
    private static let selectedUserKey = "amgi.selectedUser"

    static func loadUsers() -> [String] {
        if let users = UserDefaults.standard.array(forKey: usersKey) as? [String], !users.isEmpty {
            return users
        }
        return ["用户1", "用户2", "用户3"]
    }

    static func saveUsers(_ users: [String]) {
        UserDefaults.standard.set(users, forKey: usersKey)
        if let selected = UserDefaults.standard.string(forKey: selectedUserKey), !users.contains(selected) {
            UserDefaults.standard.set(users.first ?? "用户1", forKey: selectedUserKey)
        }
    }

    static func loadSelectedUser() -> String {
        if let selected = UserDefaults.standard.string(forKey: selectedUserKey) {
            return selected
        }
        let fallback = loadUsers().first ?? "用户1"
        UserDefaults.standard.set(fallback, forKey: selectedUserKey)
        return fallback
    }

    static func setSelectedUser(_ user: String) {
        UserDefaults.standard.set(user, forKey: selectedUserKey)
    }
}
