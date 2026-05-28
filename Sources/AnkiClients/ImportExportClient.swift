public import Dependencies
import DependenciesMacros
public import Foundation

// MARK: - Client Types

public enum ImportUpdateStrategy: String, CaseIterable, Identifiable, Sendable {
    case ifNewer
    case always
    case never

    public var id: String { rawValue }
}

public enum ImportPackageConfiguration: Sendable {
    case collection
    case ankiPackage(
        mergeNotetypes: Bool,
        updateNotes: ImportUpdateStrategy,
        updateNotetypes: ImportUpdateStrategy,
        includeScheduling: Bool,
        includeDeckConfigs: Bool
    )

    public static let `default` = ImportPackageConfiguration.ankiPackage(
        mergeNotetypes: true,
        updateNotes: .ifNewer,
        updateNotetypes: .ifNewer,
        includeScheduling: true,
        includeDeckConfigs: true
    )
}

public enum ExportPackageConfiguration: Sendable {
    case collection(includeMedia: Bool, legacy: Bool)
    case deck(
        deckID: Int64,
        deckName: String,
        includeScheduling: Bool,
        includeDeckConfigs: Bool,
        includeMedia: Bool,
        legacy: Bool
    )
    case noteIDs(
        noteIDs: [Int64],
        filenameStem: String,
        includeScheduling: Bool,
        includeDeckConfigs: Bool,
        includeMedia: Bool,
        legacy: Bool
    )
}

// MARK: - Client

@DependencyClient
public struct ImportExportClient: Sendable {
    /// Import an .apkg or .colpkg file from a URL.
    /// Handles security-scoped resource access and temp file management.
    public var importPackage: @Sendable (
        _ url: URL,
        _ configuration: ImportPackageConfiguration,
        _ collectionPaths: @escaping @Sendable () throws -> CollectionPaths
    ) throws -> String

    /// Export to a temporary file, returning the file URL.
    public var exportPackage: @Sendable (
        _ configuration: ExportPackageConfiguration,
        _ filenameOverride: String?
    ) throws -> URL

    /// Export full collection (convenience).
    public var exportCollection: @Sendable (_ filename: String?) throws -> URL
}

public struct CollectionPaths: Sendable {
    public let collectionPath: String
    public let mediaFolderPath: String
    public let mediaDbPath: String

    public init(collectionPath: String, mediaFolderPath: String, mediaDbPath: String) {
        self.collectionPath = collectionPath
        self.mediaFolderPath = mediaFolderPath
        self.mediaDbPath = mediaDbPath
    }
}

// MARK: - Dependency Registration

extension ImportExportClient: TestDependencyKey {
    public static let testValue = ImportExportClient()
}

extension DependencyValues {
    public var importExportClient: ImportExportClient {
        get { self[ImportExportClient.self] }
        set { self[ImportExportClient.self] = newValue }
    }
}
