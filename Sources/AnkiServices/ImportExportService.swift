import AnkiBackend
import AnkiProto
public import Dependencies
import DependenciesMacros
public import Foundation

// MARK: - Service

@DependencyClient
public struct ImportExportService: Sendable {
    /// Import an .apkg deck package, returning a human-readable summary.
    public var importAnkiPackage: @Sendable (
        _ path: String,
        _ mergeNotetypes: Bool,
        _ updateNotes: UpdateCondition,
        _ updateNotetypes: UpdateCondition,
        _ includeScheduling: Bool,
        _ includeDeckConfigs: Bool
    ) throws -> String

    /// Import a .colpkg full collection backup (replaces all local data).
    /// Collection must be closed before calling; caller must reopen afterwards.
    public var importCollectionPackage: @Sendable (
        _ colPath: String,
        _ backupPath: String,
        _ mediaFolder: String,
        _ mediaDb: String
    ) throws -> Void

    /// Export full collection as .colpkg.
    public var exportCollectionPackage: @Sendable (
        _ outPath: String,
        _ includeMedia: Bool,
        _ legacy: Bool
    ) throws -> Void

    /// Export cards as .apkg (by deck ID or note IDs).
    public var exportAnkiPackage: @Sendable (
        _ outPath: String,
        _ withScheduling: Bool,
        _ withDeckConfigs: Bool,
        _ withMedia: Bool,
        _ legacy: Bool,
        _ limit: ExportLimit
    ) throws -> UInt32
}

// MARK: - Supporting Types

public enum UpdateCondition: String, Sendable, CaseIterable {
    case ifNewer
    case always
    case never

    var protoValue: Anki_ImportExport_ImportAnkiPackageUpdateCondition {
        switch self {
        case .ifNewer: return .ifNewer
        case .always:  return .always
        case .never:   return .never
        }
    }
}

public enum ExportLimit: Sendable {
    case deckID(Int64)
    case noteIDs([Int64])
}

// MARK: - Live Implementation

extension ImportExportService: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        return Self(
            importAnkiPackage: { path, mergeNotetypes, updateNotes, updateNotetypes, includeScheduling, includeDeckConfigs in
                var options = Anki_ImportExport_ImportAnkiPackageOptions()
                options.mergeNotetypes = mergeNotetypes
                options.updateNotes = updateNotes.protoValue
                options.updateNotetypes = updateNotetypes.protoValue
                options.withScheduling = includeScheduling
                options.withDeckConfigs = includeDeckConfigs

                var req = Anki_ImportExport_ImportAnkiPackageRequest()
                req.packagePath = path
                req.options = options

                let response: Anki_ImportExport_ImportResponse = try backend.invoke(
                    service: AnkiBackend.Service.importExport,
                    method: AnkiBackend.ImportExportMethod.importAnkiPackage,
                    request: req
                )
                let log = response.log
                return "Imported: \(log.new.count) new, \(log.updated.count) updated, \(log.duplicate.count) duplicates"
            },

            importCollectionPackage: { colPath, backupPath, mediaFolder, mediaDb in
                var req = Anki_ImportExport_ImportCollectionPackageRequest()
                req.colPath = colPath
                req.backupPath = backupPath
                req.mediaFolder = mediaFolder
                req.mediaDb = mediaDb
                try backend.callVoid(
                    service: AnkiBackend.Service.importExport,
                    method: AnkiBackend.ImportExportMethod.importCollectionPackage,
                    request: req
                )
            },

            exportCollectionPackage: { outPath, includeMedia, legacy in
                var req = Anki_ImportExport_ExportCollectionPackageRequest()
                req.outPath = outPath
                req.includeMedia = includeMedia
                req.legacy = legacy
                try backend.callVoid(
                    service: AnkiBackend.Service.importExport,
                    method: AnkiBackend.ImportExportMethod.exportCollectionPackage,
                    request: req
                )
            },

            exportAnkiPackage: { outPath, withScheduling, withDeckConfigs, withMedia, legacy, limit in
                var options = Anki_ImportExport_ExportAnkiPackageOptions()
                options.withScheduling = withScheduling
                options.withDeckConfigs = withDeckConfigs
                options.withMedia = withMedia
                options.legacy = legacy

                var exportLimit = Anki_ImportExport_ExportLimit()
                switch limit {
                case .deckID(let id):
                    exportLimit.deckID = id
                case .noteIDs(let ids):
                    var noteIDs = Anki_Notes_NoteIds()
                    noteIDs.noteIds = ids
                    exportLimit.noteIds = noteIDs
                }

                var req = Anki_ImportExport_ExportAnkiPackageRequest()
                req.outPath = outPath
                req.options = options
                req.limit = exportLimit

                let response: Anki_Generic_UInt32 = try backend.invoke(
                    service: AnkiBackend.Service.importExport,
                    method: AnkiBackend.ImportExportMethod.exportAnkiPackage,
                    request: req
                )
                return response.val
            }
        )
    }()
}

// MARK: - Dependency Registration

extension ImportExportService: TestDependencyKey {
    public static let testValue = ImportExportService()
}

extension DependencyValues {
    public var importExportService: ImportExportService {
        get { self[ImportExportService.self] }
        set { self[ImportExportService.self] = newValue }
    }
}
