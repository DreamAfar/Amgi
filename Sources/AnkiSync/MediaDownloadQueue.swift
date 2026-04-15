import Foundation
public import AnkiKit

/// Manages a queue of media files to download, supporting persistence and batch operations.
public actor MediaDownloadQueue: Sendable {
    private var pendingFiles: [MediaFileInfo] = []
    private var downloadedHashes: Set<String> = []
    private var failedFiles: [MediaFileInfo: Int] = [:]  // file -> retry count
    private let userProfileID: String
    private let persistenceQueue = DispatchQueue(label: "com.ankiapp.media-dl-queue", attributes: .concurrent)
    
    private let queueKey: String
    private let downloadedKey: String
    private let failedKey: String
    
    public init(userProfileID: String) {
        self.userProfileID = userProfileID
        self.queueKey = "sync.media.queue.\(userProfileID)"
        self.downloadedKey = "sync.media.downloaded.\(userProfileID)"
        self.failedKey = "sync.media.failed.\(userProfileID)"
        
        let loaded = Self.loadFromPersistence(
            queueKey: "sync.media.queue.\(userProfileID)",
            downloadedKey: "sync.media.downloaded.\(userProfileID)",
            failedKey: "sync.media.failed.\(userProfileID)"
        )
        self.pendingFiles = loaded.pendingFiles
        self.downloadedHashes = loaded.downloadedHashes
        self.failedFiles = loaded.failedFiles
    }
    
    // MARK: - Public API
    
    /// Initialize queue with files to download
    public func initialize(with files: [MediaFileInfo]) {
        pendingFiles = files.filter { !downloadedHashes.contains($0.checksum) }
    }
    
    /// Get next batch of files to download
    public func nextBatch(size: Int) -> [MediaFileInfo] {
        guard !pendingFiles.isEmpty else { return [] }
        let batch = Array(pendingFiles.prefix(size))
        pendingFiles.removeFirst(batch.count)
        persistQueueState()
        return batch
    }
    
    /// Mark files as successfully downloaded
    public func markDownloaded(_ files: [MediaFileInfo]) {
        for file in files {
            downloadedHashes.insert(file.checksum)
            failedFiles.removeValue(forKey: file)
        }
        persistDownloadedState()
    }
    
    /// Mark file as failed, return true if should retry
    public func markFailed(_ file: MediaFileInfo) -> Bool {
        let retryCount = (failedFiles[file] ?? 0) + 1
        failedFiles[file] = retryCount
        
        if retryCount <= 5 {  // Max 5 retries
            pendingFiles.append(file)
            persistQueueState()
            return true
        }
        
        persistFailedState()
        return false
    }
    
    /// Get current progress
    public func getProgress() -> (total: Int, downloaded: Int) {
        let total = pendingFiles.count + downloadedHashes.count + failedFiles.count
        let downloaded = downloadedHashes.count
        return (total, downloaded)
    }
    
    /// Check if all files downloaded
    public func isComplete() -> Bool {
        return pendingFiles.isEmpty
    }
    
    /// Get failed files for reporting
    public func getFailedFiles() -> [String] {
        return failedFiles.keys.map { $0.filename }
    }
    
    /// Clear all state
    public func clear() {
        pendingFiles.removeAll()
        downloadedHashes.removeAll()
        failedFiles.removeAll()
        clearPersistence()
    }
    
    // MARK: - Persistence
    
    private func persistQueueState() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(pendingFiles) {
            UserDefaults.standard.set(encoded, forKey: queueKey)
        }
    }
    
    private func persistDownloadedState() {
        let encoder = JSONEncoder()
        let downloaded = Array(downloadedHashes)
        if let encoded = try? encoder.encode(downloaded) {
            UserDefaults.standard.set(encoded, forKey: downloadedKey)
        }
    }
    
    private func persistFailedState() {
        let encoder = JSONEncoder()
        let failed = Array(failedFiles.keys)
        if let encoded = try? encoder.encode(failed) {
            UserDefaults.standard.set(encoded, forKey: failedKey)
        }
    }
    
    private static func loadFromPersistence(
        queueKey: String,
        downloadedKey: String,
        failedKey: String
    ) -> (pendingFiles: [MediaFileInfo], downloadedHashes: Set<String>, failedFiles: [MediaFileInfo: Int]) {
        let decoder = JSONDecoder()
        
        var pendingFiles: [MediaFileInfo] = []
        var downloadedHashes: Set<String> = []
        var failedFiles: [MediaFileInfo: Int] = [:]
        
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let decoded = try? decoder.decode([MediaFileInfo].self, from: data) {
            pendingFiles = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: downloadedKey),
           let decoded = try? decoder.decode([String].self, from: data) {
            downloadedHashes = Set(decoded)
        }
        
        if let data = UserDefaults.standard.data(forKey: failedKey),
           let decoded = try? decoder.decode([MediaFileInfo].self, from: data) {
            for file in decoded {
                failedFiles[file] = 0
            }
        }
        
        return (pendingFiles, downloadedHashes, failedFiles)
    }
    
    private func clearPersistence() {
        UserDefaults.standard.removeObject(forKey: queueKey)
        UserDefaults.standard.removeObject(forKey: downloadedKey)
        UserDefaults.standard.removeObject(forKey: failedKey)
    }
}
