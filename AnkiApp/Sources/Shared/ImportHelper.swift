import AnkiBackend
import AnkiProto
import Foundation
import SwiftProtobuf

enum ImportError: Error, LocalizedError {
    case accessDenied
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Cannot access the selected file"
        case .importFailed(let msg): return msg
        }
    }
}

enum ImportHelper {
    enum ImportUpdateStrategy: String, CaseIterable, Identifiable, Sendable {
        case ifNewer
        case always
        case never

        var id: String { rawValue }

        var protoValue: Anki_ImportExport_ImportAnkiPackageUpdateCondition {
            switch self {
            case .ifNewer:
                return .ifNewer
            case .always:
                return .always
            case .never:
                return .never
            }
        }
    }

    enum ImportPackageConfiguration: Sendable {
        case collection
        case ankiPackage(
            mergeNotetypes: Bool,
            updateNotes: ImportUpdateStrategy,
            updateNotetypes: ImportUpdateStrategy,
            includeScheduling: Bool,
            includeDeckConfigs: Bool
        )

        static let `default` = ImportPackageConfiguration.ankiPackage(
            mergeNotetypes: true,
            updateNotes: .ifNewer,
            updateNotetypes: .ifNewer,
            includeScheduling: true,
            includeDeckConfigs: true
        )
    }

    enum ExportPackageConfiguration: Sendable {
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

    /// Import an .apkg or .colpkg file, preserving scheduling information.
    static func importPackage(
        from url: URL,
        backend: AnkiBackend,
        configuration: ImportPackageConfiguration? = nil
    ) throws -> String {
        // startAccessingSecurityScopedResource can return false for local files that
        // don't need a security scope — we always attempt the call but proceed either way.
        let needsRelease = url.startAccessingSecurityScopedResource()
        defer {
            if needsRelease {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Copy to a temp location the Rust backend can access
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempFile)
        do {
            try FileManager.default.copyItem(at: url, to: tempFile)
        } catch {
            throw ImportError.importFailed("Cannot copy file: \(error.localizedDescription). Please try again.")
        }

        defer { try? FileManager.default.removeItem(at: tempFile) }

        let ext = url.pathExtension.lowercased()
        Swift.print("[ImportHelper] Starting import for \(tempFile.lastPathComponent), ext=\(ext), configuration=\(String(describing: configuration))")

        if ext == "colpkg" {
            // .colpkg = full collection backup — replaces the entire local collection.
            // Backend ImportCollectionPackage expects:
            // - colPath: destination collection path
            // - backupPath: source colpkg file path (historical field name)
            let selectedUser = AppUserStore.loadSelectedUser()
            let urls = AppUserStore.collectionURLs(for: selectedUser)

            // The backend requires the collection to be closed before importing colpkg.
            // After import it will reopen it automatically but we track paths ourselves.
            try backend.closeCollection()
            defer {
                // Always attempt to reopen the collection after import (success or failure)
                try? backend.openCollection(
                    collectionPath: urls.collection.path,
                    mediaFolderPath: urls.mediaDirectory.path,
                    mediaDbPath: urls.mediaDB.path
                )
            }

            var colpkgReq = Anki_ImportExport_ImportCollectionPackageRequest()
            colpkgReq.colPath = urls.collection.path
            colpkgReq.backupPath = tempFile.path
            colpkgReq.mediaFolder = urls.mediaDirectory.path
            colpkgReq.mediaDb = urls.mediaDB.path

            try backend.callVoid(
                service: AnkiBackend.Service.importExport,
                method: AnkiBackend.ImportExportMethod.importCollectionPackage,
                request: colpkgReq
            )

            Swift.print("[ImportHelper] Collection package import finished for user=\(selectedUser)")

            return "Collection restored from backup. All cards and progress imported."
        } else {
            // .apkg = deck package — import notes/cards into the current collection.
            let apkgConfiguration: ImportPackageConfiguration
            switch configuration {
            case .collection:
                apkgConfiguration = .default
            case .ankiPackage, nil:
                apkgConfiguration = configuration ?? .default
            }

            var options = Anki_ImportExport_ImportAnkiPackageOptions()
            if case .ankiPackage(
                let mergeNotetypes,
                let updateNotes,
                let updateNotetypes,
                let includeScheduling,
                let includeDeckConfigs
            ) = apkgConfiguration {
                Swift.print(
                    "[ImportHelper] APKG options: mergeNotetypes=\(mergeNotetypes), updateNotes=\(updateNotes.rawValue), updateNotetypes=\(updateNotetypes.rawValue), withScheduling=\(includeScheduling), withDeckConfigs=\(includeDeckConfigs)"
                )
                options.withScheduling = includeScheduling
                options.withDeckConfigs = includeDeckConfigs
                options.mergeNotetypes = mergeNotetypes
                options.updateNotes = updateNotes.protoValue
                options.updateNotetypes = updateNotetypes.protoValue
            }

            var req = Anki_ImportExport_ImportAnkiPackageRequest()
            req.packagePath = tempFile.path
            req.options = options

            let response: Anki_ImportExport_ImportResponse = try backend.invoke(
                service: AnkiBackend.Service.importExport,
                method: AnkiBackend.ImportExportMethod.importAnkiPackage,
                request: req
            )

            let log = response.log
            Swift.print(
                "[ImportHelper] APKG import finished: new=\(log.new.count), updated=\(log.updated.count), duplicate=\(log.duplicate.count), conflicting=\(log.conflicting.count), missingDeck=\(log.missingDeck.count), missingNotetype=\(log.missingNotetype.count)"
            )
            return "Imported: \(log.new.count) new, \(log.updated.count) updated, \(log.duplicate.count) duplicates"
        }
    }

    static func exportCollection(backend: AnkiBackend, to filename: String = "collection.colpkg") throws -> URL {
        try exportPackage(
            backend: backend,
            configuration: .collection(includeMedia: true, legacy: false),
            filenameOverride: filename
        )
    }

    static func exportPackage(
        backend: AnkiBackend,
        configuration: ExportPackageConfiguration,
        filenameOverride: String? = nil
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outPath = tempDir.appendingPathComponent(filenameOverride ?? defaultExportFilename(for: configuration))
        try? FileManager.default.removeItem(at: outPath)

        switch configuration {
        case .collection(let includeMedia, let legacy):
            var req = Anki_ImportExport_ExportCollectionPackageRequest()
            req.outPath = outPath.path
            req.includeMedia = includeMedia
            req.legacy = legacy

            try backend.callVoid(
                service: AnkiBackend.Service.importExport,
                method: AnkiBackend.ImportExportMethod.exportCollectionPackage,
                request: req
            )
        case .deck(
            let deckID,
            _,
            let includeScheduling,
            let includeDeckConfigs,
            let includeMedia,
            let legacy
        ):
            try exportAnkiPackage(
                backend: backend,
                outPath: outPath.path,
                exportLimit: .deckID(deckID),
                includeScheduling: includeScheduling,
                includeDeckConfigs: includeDeckConfigs,
                includeMedia: includeMedia,
                legacy: legacy
            )
        case .noteIDs(
            let noteIDs,
            _,
            let includeScheduling,
            let includeDeckConfigs,
            let includeMedia,
            let legacy
        ):
            var noteIDsMessage = Anki_Notes_NoteIds()
            noteIDsMessage.noteIds = noteIDs
            try exportAnkiPackage(
                backend: backend,
                outPath: outPath.path,
                exportLimit: .noteIds(noteIDsMessage),
                includeScheduling: includeScheduling,
                includeDeckConfigs: includeDeckConfigs,
                includeMedia: includeMedia,
                legacy: legacy
            )
        }

        return outPath
    }

    private static func exportAnkiPackage(
        backend: AnkiBackend,
        outPath: String,
        exportLimit: Anki_ImportExport_ExportLimit.OneOf_Limit,
        includeScheduling: Bool,
        includeDeckConfigs: Bool,
        includeMedia: Bool,
        legacy: Bool
    ) throws {
            var options = Anki_ImportExport_ExportAnkiPackageOptions()
            options.withScheduling = includeScheduling
            options.withDeckConfigs = includeDeckConfigs
            options.withMedia = includeMedia
            options.legacy = legacy

            var limit = Anki_ImportExport_ExportLimit()
            limit.limit = exportLimit

            var req = Anki_ImportExport_ExportAnkiPackageRequest()
            req.outPath = outPath
            req.options = options
            req.limit = limit

            let _: Anki_Generic_UInt32 = try backend.invoke(
                service: AnkiBackend.Service.importExport,
                method: AnkiBackend.ImportExportMethod.exportAnkiPackage,
                request: req
            )
    }

    private static func defaultExportFilename(for configuration: ExportPackageConfiguration) -> String {
        switch configuration {
        case .collection:
            return "collection.colpkg"
        case .deck(_, let deckName, _, _, _, _):
            return "\(sanitizedFilenameStem(deckName)).apkg"
        case .noteIDs(_, let filenameStem, _, _, _, _):
            return "\(sanitizedFilenameStem(filenameStem)).apkg"
        }
    }

    private static func sanitizedFilenameStem(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/?<>:*|\"^")
        let scalarView = value.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "_" : String(scalar)
        }
        let result = scalarView.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "export" : result
    }
}
