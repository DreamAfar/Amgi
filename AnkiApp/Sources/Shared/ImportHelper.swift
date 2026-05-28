import AnkiBackend
import AnkiClients
import AnkiKit
import Dependencies
import Foundation

// MARK: - Re-export Client types for backward compatibility

enum ImportHelper {

    typealias ImportUpdateStrategy = AnkiClients.ImportUpdateStrategy
    typealias ImportPackageConfiguration = AnkiClients.ImportPackageConfiguration
    typealias ExportPackageConfiguration = AnkiClients.ExportPackageConfiguration

    // MARK: - Import

    static func importPackage(
        from url: URL,
        backend: AnkiBackend,
        configuration: ImportPackageConfiguration? = nil
    ) throws -> String {
        @Dependency(\.importExportClient) var client
        @Dependency(\.ankiBackend) var bk

        let config = configuration ?? .default

        let collectionPaths: @Sendable () throws -> CollectionPaths = {
            let selectedUser = AppUserStore.loadSelectedUser()
            let urls = AppUserStore.collectionURLs(for: selectedUser)
            return CollectionPaths(
                collectionPath: urls.collection.path,
                mediaFolderPath: urls.mediaDirectory.path,
                mediaDbPath: urls.mediaDB.path
            )
        }

        return try client.importPackage(url, config, collectionPaths)
    }

    // MARK: - Export

    static func exportCollection(
        backend: AnkiBackend,
        to filename: String = "collection.colpkg"
    ) throws -> URL {
        @Dependency(\.importExportClient) var client
        return try client.exportCollection(filename)
    }

    static func exportPackage(
        backend: AnkiBackend,
        configuration: ExportPackageConfiguration,
        filenameOverride: String? = nil
    ) throws -> URL {
        @Dependency(\.importExportClient) var client
        return try client.exportPackage(configuration, filenameOverride)
    }
}
