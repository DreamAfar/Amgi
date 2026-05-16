import Foundation
import AnkiBackend

struct BackupFileEntry: Identifiable, Equatable {
    let url: URL
    let date: Date

    var id: String { url.path }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var fileSize: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum BackupCreationOutcome {
    case created(BackupFileEntry?)
    case unchanged
}

enum CollectionBackupManager {
    static let defaultMinimumIntervalMins = 30
    static let defaultDailyBackups = 12
    static let defaultWeeklyBackups = 10
    static let defaultMonthlyBackups = 9
    static let periodicCheckInterval: TimeInterval = 5 * 60
    private static let legacyFolderName = "Legacy"

    static func backupsDirectory(for username: String) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let dir = docs.appendingPathComponent("Backups for \(username)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadBackups(for username: String) -> [BackupFileEntry] {
        guard let dir = backupsDirectory(for: username) else { return [] }
        migrateLegacyAnki2BackupsIfNeeded(in: dir)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )) ?? []

        return files
            .filter { $0.pathExtension.lowercased() == "colpkg" }
            .compactMap { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? Date.distantPast
                return BackupFileEntry(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    static func legacyBackupCount(for username: String) -> Int {
        guard let legacyDirectory = legacyBackupsDirectory(for: username) else { return 0 }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "anki2" }.count
    }

    static func createBackup(
        backend: AnkiBackend,
        username: String,
        force: Bool
    ) async throws -> BackupCreationOutcome {
        guard let dir = backupsDirectory(for: username) else {
            throw NSError(
                domain: "CollectionBackupManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access backup directory"]
            )
        }

        let created = try await Task.detached(priority: .utility) {
            let created = try backend.createBackup(
                backupFolder: dir.path,
                force: force,
                waitForCompletion: false
            )
            if created {
                try backend.awaitBackupCompletion()
            }
            return created
        }.value

        guard created else { return .unchanged }
        return .created(loadBackups(for: username).first)
    }

    static func runAutomaticBackupIfNeeded(backend: AnkiBackend, username: String) async {
        _ = try? await createBackup(backend: backend, username: username, force: false)
    }

    private static func legacyBackupsDirectory(for username: String) -> URL? {
        guard let dir = backupsDirectory(for: username) else { return nil }
        let legacyDir = dir.appendingPathComponent(legacyFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        return legacyDir
    }

    private static func migrateLegacyAnki2BackupsIfNeeded(in directory: URL) {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        let legacyDir = directory.appendingPathComponent(legacyFolderName, isDirectory: true)
        try? fileManager.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        for url in files where url.pathExtension.lowercased() == "anki2" {
            let destination = uniqueLegacyDestination(for: url, legacyDir: legacyDir)
            try? fileManager.moveItem(at: url, to: destination)
        }
    }

    private static func uniqueLegacyDestination(for sourceURL: URL, legacyDir: URL) -> URL {
        let fileManager = FileManager.default
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidate = legacyDir.appendingPathComponent("\(originalName).\(pathExtension)")
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = legacyDir.appendingPathComponent("\(originalName)-\(suffix).\(pathExtension)")
            suffix += 1
        }

        return candidate
    }
}
