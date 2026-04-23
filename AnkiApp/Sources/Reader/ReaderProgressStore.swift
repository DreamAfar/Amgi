import AnkiBackend
import Dependencies
import Foundation

struct ReaderSavedProgress: Codable, Equatable {
    let chapterID: Int64
    let progress: Double
    let updatedAt: Date
}

private struct ReaderProgressManifest: Codable {
    var version = 1
    var entries: [String: ReaderSavedProgress] = [:]
}

private struct ReaderLocalProgress {
    let key: String
    let payload: ReaderSavedProgress
}

enum ReaderProgressStore {
    private static let keyPrefix = "reader.progress."
    private static let collectionConfigKey = "amgi.reader.progress"
    private static let mediaFileName = "amgi_reader_progress.json"
    private static let collectionWriteProgressStep = 0.01
    private static let collectionWriteInterval: TimeInterval = 10

    private static var cachedManifestPath: String?
    private static var cachedManifestModifiedAt: Date?
    private static var cachedManifest: ReaderProgressManifest?
    private static var cachedCollectionManifest: ReaderProgressManifest?
    private static var didLoadCollectionManifest = false

    static func load(bookID: String) -> ReaderSavedProgress? {
        let local = loadLocal(bookID: bookID)
        let collectionManifest = loadCollectionManifest()
        let collection = collectionManifest?.entries[bookID]
        let legacyMediaManifest = loadLegacyMediaManifest()
        let legacyMedia = legacyMediaManifest?.entries[bookID]

        let resolved = latestProgress(
            local: local?.payload,
            collection: collection,
            legacyMedia: legacyMedia
        )

        guard let resolved else {
            return nil
        }

        let currentKey = currentStorageKey(for: bookID)
        if local?.key != currentKey || local?.payload != resolved {
            saveLocal(bookID: bookID, payload: resolved)
        }

        if shouldPersistToCollection(existing: collection, payload: resolved) {
            updateCollectionManifest(bookID: bookID, payload: resolved, manifest: collectionManifest)
        }

        if legacyMedia != nil {
            removeLegacyMediaManifest()
        }

        return resolved
    }

    static func save(bookID: String, chapterID: Int64, progress: Double) {
        let clampedProgress = min(max(progress, 0), 1)
        let payload = ReaderSavedProgress(
            chapterID: chapterID,
            progress: clampedProgress,
            updatedAt: .now
        )

        saveLocal(bookID: bookID, payload: payload)

        let collectionManifest = loadCollectionManifest()
        if shouldPersistToCollection(existing: collectionManifest?.entries[bookID], payload: payload) {
            updateCollectionManifest(bookID: bookID, payload: payload, manifest: collectionManifest)
        }

        removeLegacyMediaManifest()
    }

    static func migrateLegacyMediaIfNeeded() {
        let legacyManifest = loadLegacyMediaManifest()
        guard let legacyManifest, legacyManifest.entries.isEmpty == false else {
            return
        }

        var mergedManifest = loadCollectionManifest() ?? ReaderProgressManifest()
        for (bookID, payload) in legacyManifest.entries {
            let existing = mergedManifest.entries[bookID]
            if let existing, existing.updatedAt >= payload.updatedAt {
                continue
            }

            mergedManifest.entries[bookID] = payload
            saveLocal(bookID: bookID, payload: payload)
        }

        saveCollectionManifest(mergedManifest)
        removeLegacyMediaManifest()
    }

    static func resetCollectionCache() {
        didLoadCollectionManifest = false
        cachedCollectionManifest = nil
    }

    private static func loadLocal(bookID: String) -> ReaderLocalProgress? {
        for key in storageKeys(for: bookID) {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let payload = try? JSONDecoder().decode(ReaderSavedProgress.self, from: data) else {
                continue
            }
            return ReaderLocalProgress(key: key, payload: payload)
        }
        return nil
    }

    private static func saveLocal(bookID: String, payload: ReaderSavedProgress) {
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        UserDefaults.standard.set(data, forKey: currentStorageKey(for: bookID))
    }

    private static func latestProgress(
        local: ReaderSavedProgress?,
        collection: ReaderSavedProgress?,
        legacyMedia: ReaderSavedProgress?
    ) -> ReaderSavedProgress? {
        [local, collection, legacyMedia]
            .compactMap { $0 }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }

    private static func shouldPersistToCollection(
        existing: ReaderSavedProgress?,
        payload: ReaderSavedProgress
    ) -> Bool {
        guard let existing else {
            return true
        }
        if existing.chapterID != payload.chapterID {
            return true
        }
        if abs(existing.progress - payload.progress) >= collectionWriteProgressStep {
            return true
        }
        if payload.progress >= 0.999, existing.progress < 0.999 {
            return true
        }
        return payload.updatedAt.timeIntervalSince(existing.updatedAt) >= collectionWriteInterval
    }

    private static func updateCollectionManifest(
        bookID: String,
        payload: ReaderSavedProgress,
        manifest: ReaderProgressManifest?
    ) {
        var manifest = manifest ?? ReaderProgressManifest()
        manifest.entries[bookID] = payload
        saveCollectionManifest(manifest)
    }

    private static func loadCollectionManifest() -> ReaderProgressManifest? {
        if didLoadCollectionManifest {
            return cachedCollectionManifest
        }

        @Dependency(\.ankiBackend) var backend
        cachedCollectionManifest = try? backend.getConfigJSONValue(for: collectionConfigKey)
        didLoadCollectionManifest = true
        return cachedCollectionManifest
    }

    private static func saveCollectionManifest(_ manifest: ReaderProgressManifest) {
        @Dependency(\.ankiBackend) var backend

        try? backend.setConfigJSONValue(manifest, for: collectionConfigKey)
        cachedCollectionManifest = manifest
        didLoadCollectionManifest = true
    }

    private static func loadLegacyMediaManifest() -> ReaderProgressManifest? {
        guard let url = manifestURL() else {
            cachedManifestPath = nil
            cachedManifestModifiedAt = nil
            cachedManifest = nil
            return nil
        }

        let path = url.path(percentEncoded: false)
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        if cachedManifestPath == path,
           cachedManifestModifiedAt == modifiedAt {
            return cachedManifest
        }

        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ReaderProgressManifest.self, from: data) else {
            cachedManifestPath = path
            cachedManifestModifiedAt = modifiedAt
            cachedManifest = nil
            return nil
        }

        cachedManifestPath = path
        cachedManifestModifiedAt = modifiedAt
        cachedManifest = manifest
        return manifest
    }

    private static func removeLegacyMediaManifest() {
        guard let url = manifestURL() else {
            cachedManifestPath = nil
            cachedManifestModifiedAt = nil
            cachedManifest = nil
            return
        }

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: url)
        }

        cachedManifestPath = nil
        cachedManifestModifiedAt = nil
        cachedManifest = nil
    }

    private static func manifestURL() -> URL? {
        CardMediaDirectory.currentMediaDirectoryURL()?
            .appendingPathComponent(mediaFileName, isDirectory: false)
    }

    private static func storageKeys(for bookID: String) -> [String] {
        let current = currentStorageKey(for: bookID)
        let legacy = legacyStorageKey(for: bookID)
        return current == legacy ? [current] : [current, legacy]
    }

    private static func currentStorageKey(for bookID: String) -> String {
        keyPrefix + currentProfileKey() + "." + sanitizedBookID(bookID)
    }

    private static func legacyStorageKey(for bookID: String) -> String {
        keyPrefix + sanitizedBookID(bookID)
    }

    private static func sanitizedBookID(_ bookID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = String(bookID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        })
        return sanitized
    }

    private static func currentProfileKey() -> String {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "default"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = selectedUser.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let profile = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return profile.isEmpty ? "default" : profile
    }
}