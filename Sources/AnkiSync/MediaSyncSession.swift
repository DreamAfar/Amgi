import Foundation
public import AnkiKit

/// Manages a single media sync session with retry and progress tracking.
public actor MediaSyncSession: Sendable {
    private let queue: MediaDownloadQueue
    private let limiter: AdaptiveRateLimiter
    private var totalFiles: Int = 0
    private var processedFiles: Int = 0
    private var retryDelays: [MediaFileInfo: [Int]] = [:]  // file -> retry delays
    
    public init(
        queue: MediaDownloadQueue,
        limiter: AdaptiveRateLimiter = AdaptiveRateLimiter()
    ) {
        self.queue = queue
        self.limiter = limiter
    }
    
    // MARK: - Session Management
    
    public func start() {
        limiter.resetStats()
        queue.clear()
    }
    
    public func initializeWithFiles(_ files: [MediaFileInfo]) {
        totalFiles = files.count
        queue.initialize(with: files)
    }
    
    // MARK: - Batch Operations
    
    /// Get next batch of files to download
    public func getNextBatch() -> [MediaFileInfo]? {
        let batchSize = limiter.getCurrentBatchSize()
        let batch = queue.nextBatch(size: batchSize)
        return batch.isEmpty ? nil : batch
    }
    
    /// Mark batch as successfully downloaded
    public func markBatchDownloaded(_ files: [MediaFileInfo]) {
        queue.markDownloaded(files)
        processedFiles += files.count
        files.forEach { limiter.recordSuccess() }
    }
    
    /// Handle failed file, returns retry delay in milliseconds (0 if should not retry)
    public func handleFailedFile(_ file: MediaFileInfo) -> Int {
        let shouldRetry = queue.markFailed(file)
        limiter.recordFailure()
        
        if shouldRetry {
            let retryAttempt = (retryDelays[file]?.count ?? 0) + 1
            let delayMs = exponentialBackoff(attempt: retryAttempt)
            
            var delays = retryDelays[file] ?? []
            delays.append(delayMs)
            retryDelays[file] = delays
            
            return delayMs
        }
        
        return 0
    }
    
    /// Handle HTTP 429 response (server rate limiting)
    public func handleHTTP429() {
        limiter.recordHTTP429()
    }
    
    /// Get current progress
    public func getProgress() -> (total: Int, downloaded: Int) {
        return queue.getProgress()
    }
    
    /// Check if session is complete
    public func isComplete() -> Bool {
        return queue.isComplete()
    }
    
    /// Get failed files for final report
    public func getFailedFiles() -> [String] {
        return queue.getFailedFiles()
    }
    
    /// Get current delay (includes backoff)
    public func getCurrentDelayMs() -> Int {
        var baseDelay = limiter.getCurrentDelayMs()
        
        // Additional delay if aggressive backoff triggered
        if limiter.shouldAggressiveBackoff() {
            baseDelay = Int(Double(baseDelay) * 1.5)
        }
        
        return baseDelay
    }
    
    /// Get diagnostic information
    public func getDiagnostics() -> String {
        let info = limiter.getDiagnostics()
        let progress = queue.getProgress()
        return """
        Media Sync Diagnostics:
        - Progress: \(progress.downloaded)/\(progress.total)
        - Batch Size: \(info.batchSize)
        - Delay: \(info.delayMs)ms
        - Failure Rate: \(String(format: "%.1f", info.failureRate * 100))%
        - Successes: \(info.successCount), Failures: \(info.failureCount)
        - HTTP 429 Count: \(info.http429Count)
        """
    }
    
    // MARK: - Private Helpers
    
    private func exponentialBackoff(attempt: Int) -> Int {
        let baseDelay = 1000  // 1 second
        let maxDelay = 32000  // 32 seconds
        let delayMs = min(maxDelay, baseDelay * Int(pow(2.0, Double(attempt - 1))))
        
        // Add jitter (±10%)
        let jitter = Double(delayMs) * 0.1 * Double.random(in: -1...1)
        return Int(Double(delayMs) + jitter)
    }
}
