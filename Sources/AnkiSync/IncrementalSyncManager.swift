public import Foundation
import CryptoKit
import Logging
public import AnkiKit

private let logger = Logger(label: "com.ankiapp.sync.incremental")

/// Manages incremental sync state, detecting new and modified files
/// Enables skipping already-verified files in subsequent syncs
public actor IncrementalSyncManager: Sendable {
    private let userProfileID: String
    
    /// Maps SHA256 hash → (filename, lastSyncTime)
    private var syncedFilesHashMap: [String: (filename: String, timestamp: TimeInterval)] = [:]
    
    /// Persistent storage key
    private var storageKey: String { "incremental_sync_\(userProfileID)" }
    
    public init(userProfileID: String) {
        self.userProfileID = userProfileID
        self.syncedFilesHashMap = Self.loadFromStorage(key: storageKey)
        logger.info("Incremental sync manager initialized with \(self.syncedFilesHashMap.count) known files")
    }
    
    // MARK: - Public API
    
    /// Records a successfully synced file (SHA256-based)
    public func recordSyncedFile(_ filename: String, contentHash: String) {
        syncedFilesHashMap[contentHash] = (filename: filename, timestamp: Date().timeIntervalSince1970)
        persistToDisk()
        logger.debug("Recorded synced file: \(filename)")
    }
    
    /// Records multiple synced files in batch
    public func recordSyncedFiles(_ files: [(filename: String, hash: String)]) {
        let now = Date().timeIntervalSince1970
        for (filename, hash) in files {
            syncedFilesHashMap[hash] = (filename: filename, timestamp: now)
        }
        persistToDisk()
        logger.info("Recorded \(files.count) synced files")
    }
    
    /// Checks if a file with given hash was already successfully synced
    public func wasFileSynced(hash: String) -> Bool {
        syncedFilesHashMap[hash] != nil
    }
    
    /// Filters media list to only files that need syncing (new or modified)
    /// Returns: (filesToSync: [...], skippedCount: Int)
    public func filterNewAndModifiedFiles(
        _ allFiles: [MediaFileInfo]
    ) -> (toSync: [MediaFileInfo], skipped: Int) {
        var toSync = [MediaFileInfo]()
        var skipped = 0
        
        for file in allFiles {
            // For efficiency, compute hash only if needed
            if wasFileSynced(hash: file.sha256) {
                skipped += 1
                // Could additionally verify hash hasn't changed on server
                // For now, trust server hasn't re-served same hash with different content
            } else {
                toSync.append(file)
            }
        }
        
        logger.info("""
            Incremental sync filter: \(allFiles.count) total, \
            \(toSync.count) to sync, \(skipped) skipped
            """)
        return (toSync, skipped)
    }
    
    /// Cleanups old sync record (>30 days) to prevent unbounded growth
    public func cleanupOldRecords(retentionDays: Int = 30) {
        let cutoffTime = Date().timeIntervalSince1970 - Double(retentionDays * 86400)
        let beforeCount = syncedFilesHashMap.count
        
        syncedFilesHashMap = syncedFilesHashMap.filter { _, value in
            value.timestamp > cutoffTime
        }
        
        persistToDisk()
        let removed = beforeCount - syncedFilesHashMap.count
        logger.info("Cleaned up \(removed) old sync records (>\(retentionDays) days)")
    }
    
    /// Get sync statistics
    public func getSyncStats() -> IncrementalSyncStats {
        let oldestRecord = syncedFilesHashMap.values.min(by: { $0.timestamp < $1.timestamp })
        let newestRecord = syncedFilesHashMap.values.max(by: { $0.timestamp < $1.timestamp })
        
        return IncrementalSyncStats(
            knownFileCount: syncedFilesHashMap.count,
            oldestSyncTime: oldestRecord?.timestamp,
            newestSyncTime: newestRecord?.timestamp
        )
    }
    
    /// Clear all sync history (for testing or manual reset)
    public func clearAll() {
        logger.warning("Clearing all incremental sync history")
        syncedFilesHashMap.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    // MARK: - Persistence
    
    private func persistToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        
        let dict = syncedFilesHashMap.mapValues { file in
            SerializableFileRecord(filename: file.filename, timestamp: file.timestamp)
        }
        
        do {
            let data = try encoder.encode(dict)
            UserDefaults.standard.set(data, forKey: storageKey)
            logger.debug("Persisted \(dict.count) incremental sync records")
        } catch {
            logger.error("Failed to persist incremental sync state: \(error)")
        }
    }
    
    private static func loadFromStorage(key: String) -> [String: (filename: String, timestamp: TimeInterval)] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return [:]
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            let dict = try decoder.decode([String: SerializableFileRecord].self, from: data)
            return dict.mapValues { record in
                (filename: record.filename, timestamp: record.timestamp)
            }
        } catch {
            logger.error("Failed to load incremental sync state: \(error)")
            return [:]
        }
    }
}

// MARK: - Data Structures

public struct IncrementalSyncStats: Sendable {
    public let knownFileCount: Int
    public let oldestSyncTime: TimeInterval?
    public let newestSyncTime: TimeInterval?
    
    public var daysSinceLastSync: Int? {
        guard let newestSyncTime = newestSyncTime else { return nil }
        return Int(Date().timeIntervalSince1970 - newestSyncTime) / 86400
    }
    
    public var syncedFileAgeRange: String {
        guard let oldest = oldestSyncTime, let newest = newestSyncTime else {
            return "No records"
        }
        let oldestDate = Date(timeIntervalSince1970: oldest)
        let newestDate = Date(timeIntervalSince1970: newest)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: oldestDate)) to \(formatter.string(from: newestDate))"
    }
}

// MARK: - Serialization

private struct SerializableFileRecord: Codable, Sendable {
    let filename: String
    let timestamp: TimeInterval
}

// MARK: - Integration with MediaDownloadQueue

extension MediaDownloadQueue {
    /// Apply incremental sync filtering
    /// Returns: count of files skipped (already synced)
    public func applyIncrementalFilter(
        manager: IncrementalSyncManager,
        files: [MediaFileInfo]
    ) async -> (filtered: [MediaFileInfo], skipped: Int) {
        let (toSync, skipped) = await manager.filterNewAndModifiedFiles(files)
        return (toSync, skipped)
    }
    
    /// Record synced batch
    public func recordSyncedBatch(
        manager: IncrementalSyncManager,
        files: [MediaFileInfo]
    ) async {
        let records = files.map { file in
            (filename: file.filename, hash: file.checksum)
        }
        await manager.recordSyncedFiles(records)
    }
}

// MARK: - Logging and Diagnostics

extension IncrementalSyncManager {
    /// Get detailed sync history for logging
    public func getDetailedStats() -> String {
        let stats = getSyncStats()
        let skipEstimate = stats.knownFileCount
        return """
            Incremental Sync Status:
            - Known files: \(stats.knownFileCount)
            - Age range: \(stats.syncedFileAgeRange)
            - Days since last: \(stats.daysSinceLastSync ?? -1)
            - Skip estimate: \(skipEstimate) files on next sync
            """
    }
}
