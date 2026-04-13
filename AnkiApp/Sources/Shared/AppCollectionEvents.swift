import Foundation
import AnkiSync

enum AppCollectionEvents {
    static let didResetNotification = Notification.Name("amgi.collection.did-reset")
}

enum AppSyncAuthEvents {
    static let didChangeNotification = Notification.Name("amgi.sync-auth.did-change")

    static func clearCredentials() {
        KeychainHelper.deleteHostKey()
        KeychainHelper.deleteUsername()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}