import AnkiBackend
import AnkiProto
import Dependencies
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
    static func importPackage(from url: URL) throws -> String {
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

        var req = Anki_ImportExport_ImportAnkiPackageRequest()
        req.packagePath = tempFile.path

        @Dependency(\.ankiBackend) var backend
        let response: Anki_ImportExport_ImportResponse = try backend.invoke(
            service: AnkiBackend.Service.importExport,
            method: AnkiBackend.ImportExportMethod.importAnkiPackage,
            request: req
        )

        let log = response.log
        return "Imported: \(log.new.count) new, \(log.updated.count) updated, \(log.duplicate.count) duplicates"
    }

    static func exportCollection(to filename: String = "collection.colpkg") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outPath = tempDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: outPath)

        var req = Anki_ImportExport_ExportCollectionPackageRequest()
        req.outPath = outPath.path
        req.includeMedia = true
        req.legacy = false

        @Dependency(\.ankiBackend) var backend
        try backend.callVoid(
            service: AnkiBackend.Service.importExport,
            method: AnkiBackend.ImportExportMethod.exportCollectionPackage,
            request: req
        )

        return outPath
    }
}
