import AnkiServices
import AnkiBackend
public import Dependencies
import DependenciesMacros
public import Foundation

extension ImportExportClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.importExportService) var service
        @Dependency(\.ankiBackend) var backend

        return Self(
            importPackage: { url, configuration, collectionPathsProvider in
                let needsRelease = url.startAccessingSecurityScopedResource()
                defer {
                    if needsRelease { url.stopAccessingSecurityScopedResource() }
                }

                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempFile)
                do {
                    try FileManager.default.copyItem(at: url, to: tempFile)
                } catch {
                    throw ImportClientError.importFailed("Cannot copy file: \(error.localizedDescription)")
                }
                defer { try? FileManager.default.removeItem(at: tempFile) }

                let ext = url.pathExtension.lowercased()

                if ext == "colpkg" {
                    let paths = try collectionPathsProvider()
                    try backend.closeCollection()
                    defer {
                        try? backend.openCollection(
                            collectionPath: paths.collectionPath,
                            mediaFolderPath: paths.mediaFolderPath,
                            mediaDbPath: paths.mediaDbPath
                        )
                    }
                    try service.importCollectionPackage(
                        paths.collectionPath,
                        tempFile.path,
                        paths.mediaFolderPath,
                        paths.mediaDbPath
                    )
                    return "Collection restored from backup. All cards and progress imported."
                } else {
                    let config: ImportPackageConfiguration
                    switch configuration {
                    case .collection:
                        config = .default
                    case .ankiPackage:
                        config = configuration
                    }

                    guard case .ankiPackage(let merge, let updateNotes, let updateNotetypes, let sched, let configs) = config else {
                        throw ImportClientError.importFailed("Invalid configuration")
                    }

                    return try service.importAnkiPackage(
                        tempFile.path,
                        merge,
                        ImportConditionMapper.toService(updateNotes),
                        ImportConditionMapper.toService(updateNotetypes),
                        sched,
                        configs
                    )
                }
            },

            exportPackage: { configuration, filenameOverride in
                let tempDir = FileManager.default.temporaryDirectory
                let filename = filenameOverride ?? defaultExportFilename(for: configuration)
                let outPath = tempDir.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: outPath)

                switch configuration {
                case .collection(let includeMedia, let legacy):
                    try service.exportCollectionPackage(outPath.path, includeMedia, legacy)

                case .deck(let deckID, _, let sched, let configs, let media, let legacy):
                    _ = try service.exportAnkiPackage(outPath.path, sched, configs, media, legacy, .deckID(deckID))

                case .noteIDs(let noteIDs, _, let sched, let configs, let media, let legacy):
                    _ = try service.exportAnkiPackage(outPath.path, sched, configs, media, legacy, .noteIDs(noteIDs))
                }

                return outPath
            },

            exportCollection: { filename in
                try exportPackage(
                    ExportPackageConfiguration.collection(includeMedia: true, legacy: false),
                    filename
                )
            }
        )
    }()

    // Redeclared locally to break circular reference in the closure above.
    private static func exportPackage(
        _ configuration: ExportPackageConfiguration,
        _ filenameOverride: String?
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = filenameOverride ?? defaultExportFilename(for: configuration)
        let outPath = tempDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outPath)

        @Dependency(\.importExportService) var service
        switch configuration {
        case .collection(let includeMedia, let legacy):
            try service.exportCollectionPackage(outPath.path, includeMedia, legacy)
        case .deck(let deckID, _, let sched, let configs, let media, let legacy):
            _ = try service.exportAnkiPackage(outPath.path, sched, configs, media, legacy, .deckID(deckID))
        case .noteIDs(let noteIDs, _, let sched, let configs, let media, let legacy):
            _ = try service.exportAnkiPackage(outPath.path, sched, configs, media, legacy, .noteIDs(noteIDs))
        }
        return outPath
    }
}

// MARK: - Helpers

private enum ImportConditionMapper {
    static func toService(_ strategy: ImportUpdateStrategy) -> UpdateCondition {
        switch strategy {
        case .ifNewer: return .ifNewer
        case .always:  return .always
        case .never:   return .never
        }
    }
}

public enum ImportClientError: Error, LocalizedError {
    case importFailed(String)

    public var errorDescription: String? {
        switch self {
        case .importFailed(let msg): return msg
        }
    }
}

private func defaultExportFilename(for configuration: ExportPackageConfiguration) -> String {
    switch configuration {
    case .collection:
        return "collection.colpkg"
    case .deck(_, let deckName, _, _, _, _):
        return "\(sanitizedFilenameStem(deckName)).apkg"
    case .noteIDs(_, let filenameStem, _, _, _, _):
        return "\(sanitizedFilenameStem(filenameStem)).apkg"
    }
}

private func sanitizedFilenameStem(_ value: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "\\/?<>:*|\"^")
    let scalarView = value.unicodeScalars.map { scalar in
        invalidCharacters.contains(scalar) ? "_" : String(scalar)
    }
    let result = scalarView.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? "export" : result
}
