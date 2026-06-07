import AnkiBackend
import AnkiClients
import AmgiReader
import AmgiReaderDictionary
import Foundation

enum AppCollectionBootstrap {
    static func preferredBackendLangsFromDefaults() -> [String] {
        let raw = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.system.rawValue
        return (AppLanguage(rawValue: raw) ?? .system).preferredBackendLangs
    }

    static func openCollection(using backend: AnkiBackend, username: String) throws {
        let urls = AppUserStore.collectionURLs(for: username)

        try FileManager.default.createDirectory(
            at: urls.directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: urls.mediaDirectory,
            withIntermediateDirectories: true
        )

        try backend.openCollection(
            collectionPath: urls.collection.path,
            mediaFolderPath: urls.mediaDirectory.path,
            mediaDbPath: urls.mediaDB.path
        )

        ReaderProgressStore.migrateLegacyMediaIfNeeded()
        // FIXME(diag): 临时注释以排查 108↑ 重复同步根因
        // try? DictionaryLookupConfigMigration.migrateLegacyMirroredConfigIfNeeded(backend: backend)
    }

    static func ensureCollectionOpen(using backend: AnkiBackend, username: String) throws {
        guard isCollectionOpen(using: backend) == false else {
            return
        }
        try openCollection(using: backend, username: username)
    }

    private static func isCollectionOpen(using backend: AnkiBackend) -> Bool {
        (try? backend.call(
            service: AnkiBackend.Service.collection,
            method: AnkiBackend.CollectionMethod.latestProgress
        )) != nil
    }
}

actor AppBackendRuntime {
    static let shared = AppBackendRuntime()

    private var backend: AnkiBackend?
    private var currentUser: String?

    func prepareBackend(preferredLangs: [String]) async throws -> AnkiBackend {
        if let backend {
            return backend
        }

        let backend = try await Task.detached(priority: .userInitiated) {
            try AnkiBackend(preferredLangs: preferredLangs)
        }.value
        self.backend = backend
        return backend
    }

    func ensureCollectionOpen(
        preferredLangs: [String],
        username: String
    ) async throws -> AnkiBackend {
        let backend = try await prepareBackend(preferredLangs: preferredLangs)

        if currentUser != username {
            if currentUser != nil {
                try? backend.closeCollection()
            }
            try AppCollectionBootstrap.openCollection(using: backend, username: username)
            currentUser = username
            return backend
        }

        try AppCollectionBootstrap.ensureCollectionOpen(using: backend, username: username)
        return backend
    }

    func reopenCollection(
        preferredLangs: [String],
        username: String
    ) async throws -> AnkiBackend {
        let backend = try await prepareBackend(preferredLangs: preferredLangs)
        try? backend.closeCollection()
        try AppCollectionBootstrap.openCollection(using: backend, username: username)
        currentUser = username
        return backend
    }
}