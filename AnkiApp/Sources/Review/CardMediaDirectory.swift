import Foundation

enum CardMediaDirectory {
    private static let cacheLock = NSLock()
    private static var cachedUser: String?
    private static var cachedMediaDirectoryURL: URL?

    /// Mirrors AppUserStore.collectionURLs(for:) exactly so paths always match.
    static func currentMediaDirectoryURL() -> URL? {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "用户1"

        cacheLock.lock()
        if cachedUser == selectedUser {
            let cachedURL = cachedMediaDirectoryURL
            cacheLock.unlock()
            return cachedURL
        }
        cacheLock.unlock()

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }

        let userFolder = sanitizedFolderName(selectedUser)
        let mediaURL = appSupport
            .appendingPathComponent("AnkiCollection", isDirectory: true)
            .appendingPathComponent(userFolder, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)

        cacheLock.lock()
        cachedUser = selectedUser
        cachedMediaDirectoryURL = mediaURL
        cacheLock.unlock()

        return mediaURL
    }

    /// Must match AppUserStore.sanitizedUserFolderName exactly (including underscore trimming).
    private static func sanitizedFolderName(_ user: String) -> String {
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