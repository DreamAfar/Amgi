import Foundation

enum SchemaChangeFullSyncGuard {
    static func needsFullUpload() -> Bool {
        UserDefaults.standard.bool(forKey: SyncPreferences.Keys.schemaPendingFullUploadForCurrentUser())
    }

    static func markPendingFullUpload() {
        UserDefaults.standard.set(true, forKey: SyncPreferences.Keys.schemaPendingFullUploadForCurrentUser())
    }

    static func clearPendingFullUpload() {
        UserDefaults.standard.removeObject(forKey: SyncPreferences.Keys.schemaPendingFullUploadForCurrentUser())
    }
}
