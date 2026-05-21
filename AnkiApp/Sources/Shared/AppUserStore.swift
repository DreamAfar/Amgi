import Foundation
import AnkiSync

enum AppUserStore {
    static let didChangeNotification = Notification.Name("amgi.app-user-store.did-change")

    private static let usersKey = "amgi.users"
    private static let selectedUserKey = "amgi.selectedUser"
    private static var defaultUsers: [String] {
        [NSLocalizedString("user_mgmt_default_user", comment: "")]
    }

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
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
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
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func collectionURLs(for user: String) -> (directory: URL, collection: URL, mediaDirectory: URL, mediaDB: URL) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let userFolder = profileID(for: user)
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

    static func deleteUserData(for user: String) throws {
        let defaults = UserDefaults.standard
        let profileID = profileID(for: user)
        let urls = collectionURLs(for: user)

        if FileManager.default.fileExists(atPath: urls.directory.path) {
            try FileManager.default.removeItem(at: urls.directory)
        }

        for key in syncPreferenceKeys(for: user) {
            defaults.removeObject(forKey: key)
        }
        for key in readerPreferenceKeys(for: user) {
            defaults.removeObject(forKey: key)
        }

        DeckListHeatmapCache.clear(for: user)
        DeckTreeCache.clear(for: user)

        KeychainHelper.deleteHostKey(for: user)
        KeychainHelper.deleteUsername(for: user)
        KeychainHelper.deleteEndpoint(for: user)
        KeychainHelper.deleteCurrentEndpoint(for: user)

        for key in defaults.dictionaryRepresentation().keys where shouldRemoveUserScopedKey(key, profileID: profileID) {
            defaults.removeObject(forKey: key)
        }
    }

    static func deleteAllAppData() throws {
        let defaults = UserDefaults.standard
        let users = loadUsers()
        let fileManager = FileManager.default

        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first

        for user in users {
            try? deleteUserData(for: user)
        }

        let appSupportDirectories = [
            appSupport.appendingPathComponent("AnkiCollection", isDirectory: true),
            appSupport.appendingPathComponent("ReaderDictionaries", isDirectory: true),
        ]
        for directory in appSupportDirectories where fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }

        if let documents {
            let booksDirectory = documents.appendingPathComponent("Books", isDirectory: true)
            if fileManager.fileExists(atPath: booksDirectory.path) {
                try fileManager.removeItem(at: booksDirectory)
            }

            let backupDirectories = (try? fileManager.contentsOfDirectory(
                at: documents,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in backupDirectories where url.lastPathComponent.hasPrefix("Backups for ") {
                try? fileManager.removeItem(at: url)
            }
        }

        KeychainHelper.deleteAllSyncCredentials()

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        } else {
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
        }
    }

    static func renameUserData(from oldUser: String, to newUser: String) throws {
        let oldProfileID = profileID(for: oldUser)
        let newProfileID = profileID(for: newUser)
        guard oldProfileID != newProfileID else { return }

        let oldURLs = collectionURLs(for: oldUser)
        let newURLs = collectionURLs(for: newUser)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: newURLs.directory.path) {
            throw AppUserStoreError.targetDataAlreadyExists
        }

        if fileManager.fileExists(atPath: oldURLs.directory.path) {
            try fileManager.moveItem(at: oldURLs.directory, to: newURLs.directory)
        }

        migrateScopedDefaults(from: oldProfileID, to: newProfileID)
        try migrateScopedCredentials(from: oldUser, to: newUser)
    }

    static func profileID(for user: String) -> String {
        sanitizedUserFolderName(user)
    }

    static func hasScopeConflict(for user: String, existingUsers: [String], excluding excludedUser: String? = nil) -> Bool {
        let targetProfileID = profileID(for: user)
        return existingUsers.contains { existingUser in
            guard existingUser != excludedUser else { return false }
            return profileID(for: existingUser) == targetProfileID
        }
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

    private static func syncPreferenceKeys(for user: String) -> [String] {
        let profileID = profileID(for: user)
        return [
            SyncPreferences.Keys.modeBase,
            SyncPreferences.Keys.syncMediaBase,
            SyncPreferences.Keys.ioTimeoutSecsBase,
            SyncPreferences.Keys.mediaLastLogBase,
            SyncPreferences.Keys.mediaLastSyncedAtBase,
            SyncPreferences.Keys.lastCollectionSyncedAtBase,
            SyncPreferences.Keys.schemaPendingFullUploadBase,
        ].map { "\($0).\(profileID)" }
    }

    private static func migrateScopedDefaults(from oldProfileID: String, to newProfileID: String) {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys

        for oldKey in keys {
            guard let newKey = migratedScopedKey(oldKey, from: oldProfileID, to: newProfileID),
                  let value = defaults.object(forKey: oldKey) else {
                continue
            }
            defaults.set(value, forKey: newKey)
            defaults.removeObject(forKey: oldKey)
        }
    }

    private static func migrateScopedCredentials(from oldUser: String, to newUser: String) throws {
        if let hostKey = KeychainHelper.loadHostKey(for: oldUser) {
            try KeychainHelper.saveHostKey(hostKey, for: newUser)
            KeychainHelper.deleteHostKey(for: oldUser)
        }
        if let username = KeychainHelper.loadUsername(for: oldUser) {
            try KeychainHelper.saveUsername(username, for: newUser)
            KeychainHelper.deleteUsername(for: oldUser)
        }
        if let endpoint = KeychainHelper.loadEndpoint(for: oldUser) {
            try KeychainHelper.saveEndpoint(endpoint, for: newUser)
            KeychainHelper.deleteEndpoint(for: oldUser)
        }
        if let currentEndpoint = KeychainHelper.loadCurrentEndpoint(for: oldUser) {
            try KeychainHelper.saveCurrentEndpoint(currentEndpoint, for: newUser)
            KeychainHelper.deleteCurrentEndpoint(for: oldUser)
        }
    }

    private static func migratedScopedKey(_ key: String, from oldProfileID: String, to newProfileID: String) -> String? {
        let exactKeyMap = [
            "deck_list_heatmap_cache.\(oldProfileID)": "deck_list_heatmap_cache.\(newProfileID)",
            "deck_list_tree_cache.\(oldProfileID)": "deck_list_tree_cache.\(newProfileID)",
            "sync.media.queue.\(oldProfileID)": "sync.media.queue.\(newProfileID)",
            "sync.media.downloaded.\(oldProfileID)": "sync.media.downloaded.\(newProfileID)",
            "sync.media.failed.\(oldProfileID)": "sync.media.failed.\(newProfileID)",
            "incremental_sync_\(oldProfileID)": "incremental_sync_\(newProfileID)",
        ]
        if let mapped = exactKeyMap[key] {
            return mapped
        }

        let scopedBases = [
            SyncPreferences.Keys.modeBase,
            SyncPreferences.Keys.syncMediaBase,
            SyncPreferences.Keys.ioTimeoutSecsBase,
            SyncPreferences.Keys.mediaLastLogBase,
            SyncPreferences.Keys.mediaLastSyncedAtBase,
            SyncPreferences.Keys.lastCollectionSyncedAtBase,
            SyncPreferences.Keys.schemaPendingFullUploadBase,
        ]
        for base in scopedBases {
            let oldKey = "\(base).\(oldProfileID)"
            if key == oldKey {
                return "\(base).\(newProfileID)"
            }
        }

        let readerScopedBases = ReaderPreferences.Keys.allBases + [ReaderPreferences.legacyMigrationMarkerBase]
        for base in readerScopedBases {
            let oldKey = ReaderPreferences.scopedKey(for: base, profileID: oldProfileID)
            if key == oldKey {
                return ReaderPreferences.scopedKey(for: base, profileID: newProfileID)
            }
        }

        let readerPrefix = "reader.progress.\(oldProfileID)."
        if key.hasPrefix(readerPrefix) {
            return "reader.progress.\(newProfileID)." + String(key.dropFirst(readerPrefix.count))
        }

        return nil
    }

    private static func shouldRemoveUserScopedKey(_ key: String, profileID: String) -> Bool {
        let prefixes = [
            "reader.progress.\(profileID).",
            "sync.media.queue.\(profileID)",
            "sync.media.downloaded.\(profileID)",
            "sync.media.failed.\(profileID)",
            "incremental_sync_\(profileID)",
        ]
        return prefixes.contains { key.hasPrefix($0) }
    }

    private static func readerPreferenceKeys(for user: String) -> [String] {
        let profileID = profileID(for: user)
        return (ReaderPreferences.Keys.allBases + [ReaderPreferences.legacyMigrationMarkerBase]).map {
            ReaderPreferences.scopedKey(for: $0, profileID: profileID)
        }
    }
}

enum AppUserStoreError: LocalizedError {
    case targetDataAlreadyExists

    var errorDescription: String? {
        switch self {
        case .targetDataAlreadyExists:
            return NSLocalizedString("user_mgmt_rename_target_exists", comment: "")
        }
    }
}
