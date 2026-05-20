import Foundation
import AnkiSync

enum AppCollectionEvents {
    static let didOpenNotification = Notification.Name("amgi.collection.did-open")
    static let didResetNotification = Notification.Name("amgi.collection.did-reset")
    static let openDeckListNotification = Notification.Name("amgi.collection.open-deck-list")
    static let openBrowseSearchNotification = Notification.Name("amgi.collection.open-browse-search")
    static let browseSearchQueryUserInfoKey = "query"

    @MainActor
    private static var pendingBrowseSearchQuery: String?

    @MainActor
    static func postOpenBrowseSearch(query: String) {
        pendingBrowseSearchQuery = query
        NotificationCenter.default.post(
            name: openBrowseSearchNotification,
            object: nil,
            userInfo: [browseSearchQueryUserInfoKey: query]
        )
    }

    @MainActor
    static func consumePendingBrowseSearchQuery() -> String? {
        defer { pendingBrowseSearchQuery = nil }
        return pendingBrowseSearchQuery
    }
}

enum AppSyncAuthEvents {
    static let didChangeNotification = Notification.Name("amgi.sync-auth.did-change")

    static func clearCredentials() {
        KeychainHelper.deleteHostKey()
        KeychainHelper.deleteUsername()
        KeychainHelper.deleteCurrentEndpoint()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
