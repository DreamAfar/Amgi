import Foundation
import AnkiSync

enum AppCollectionEvents {
    static let didOpenNotification = Notification.Name("amgi.collection.did-open")
    static let didResetNotification = Notification.Name("amgi.collection.did-reset")
    static let openDeckListNotification = Notification.Name("amgi.collection.open-deck-list")
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
