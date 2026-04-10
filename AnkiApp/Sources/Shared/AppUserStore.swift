import Foundation

enum AppUserStore {
    private static let usersKey = "amgi.users"
    private static let selectedUserKey = "amgi.selectedUser"
    private static let defaultUsers = ["用户1", "用户2", "用户3"]

    static func loadUsers() -> [String] {
        if let users = UserDefaults.standard.array(forKey: usersKey) as? [String], !users.isEmpty {
            return users
        }
        return defaultUsers
    }

    static func saveUsers(_ users: [String]) {
        UserDefaults.standard.set(users, forKey: usersKey)
        if let selected = UserDefaults.standard.string(forKey: selectedUserKey), !users.contains(selected) {
            UserDefaults.standard.set(users.first ?? defaultUsers[0], forKey: selectedUserKey)
        }
    }

    static func loadSelectedUser() -> String {
        if let selected = UserDefaults.standard.string(forKey: selectedUserKey) {
            return selected
        }
        let fallback = loadUsers().first ?? defaultUsers[0]
        UserDefaults.standard.set(fallback, forKey: selectedUserKey)
        return fallback
    }

    static func setSelectedUser(_ user: String) {
        UserDefaults.standard.set(user, forKey: selectedUserKey)
    }

    static func collectionURLs(for user: String) -> (directory: URL, collection: URL, mediaDirectory: URL, mediaDB: URL) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let userFolder = sanitizedUserFolderName(user)
        let directory = appSupport
            .appendingPathComponent("AnkiCollection", isDirectory: true)
            .appendingPathComponent(userFolder, isDirectory: true)

        return (
            directory: directory,
            collection: directory.appendingPathComponent("collection.anki2"),
            mediaDirectory: directory.appendingPathComponent("media", isDirectory: true),
            mediaDB: directory.appendingPathComponent("media.db")
        )
    }

    private static func sanitizedUserFolderName(_ user: String) -> String {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default" }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let folder = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return folder.isEmpty ? "default" : folder
    }
}
