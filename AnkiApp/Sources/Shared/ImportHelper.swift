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
    /// Import an .apkg or .colpkg file, preserving scheduling information.
    static func importPackage(from url: URL, backend: AnkiBackend) throws -> String {
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

            return "Collection restored from backup. All cards and progress imported."
        } else {
            // .apkg = deck package — import notes/cards into the current collection.
            // Set with_scheduling = true to preserve review history and card states.
            var options = Anki_ImportExport_ImportAnkiPackageOptions()
            options.withScheduling = true
            options.withDeckConfigs = true
            options.mergeNotetypes = true
            // updateNotes and updateNotetypes default to .ifNewer — no change needed

            var req = Anki_ImportExport_ImportAnkiPackageRequest()
            req.packagePath = tempFile.path
            req.options = options

            let response: Anki_ImportExport_ImportResponse = try backend.invoke(
                service: AnkiBackend.Service.importExport,
                method: AnkiBackend.ImportExportMethod.importAnkiPackage,
                request: req
            )

            let log = response.log
            return "Imported: \(log.new.count) new, \(log.updated.count) updated, \(log.duplicate.count) duplicates"
        }
    }

    static func exportCollection(backend: AnkiBackend, to filename: String = "collection.colpkg") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outPath = tempDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outPath)

        var req = Anki_ImportExport_ExportCollectionPackageRequest()
        req.outPath = outPath.path
        req.includeMedia = true
        req.legacy = false

        try backend.callVoid(
            service: AnkiBackend.Service.importExport,
            method: AnkiBackend.ImportExportMethod.exportCollectionPackage,
            request: req
        )

        return outPath
    }
}
