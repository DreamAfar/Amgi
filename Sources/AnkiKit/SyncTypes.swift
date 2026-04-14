import Foundation

public enum SyncDirection: Sendable {
    case upload
    case download
}

public struct SyncError: Error, Sendable, Equatable {
    public let message: String
    public let isRetryable: Bool

    public init(message: String, isRetryable: Bool = true) {
        self.message = message
        self.isRetryable = isRetryable
    }

    public static let authFailed = SyncError(message: "Authentication failed", isRetryable: false)
    public static let networkUnavailable = SyncError(message: "Network unavailable", isRetryable: true)
    public static let fullSyncRequired = SyncError(message: "Full sync required", isRetryable: false)
    public static let conflictDetected = SyncError(message: "Conflict detected", isRetryable: false)
}

public struct SyncSummary: Sendable, Equatable {
    public var cardsPushed: Int
    public var cardsPulled: Int
    public var notesPushed: Int
    public var notesPulled: Int
    public var conflictsResolved: Int

    public init(
        cardsPushed: Int = 0, cardsPulled: Int = 0,
        notesPushed: Int = 0, notesPulled: Int = 0, conflictsResolved: Int = 0
    ) {
        self.cardsPushed = cardsPushed
        self.cardsPulled = cardsPulled
        self.notesPushed = notesPushed
        self.notesPulled = notesPulled
        self.conflictsResolved = conflictsResolved
    }
}

public struct MediaSyncSummary: Sendable, Equatable {
    public var filesUploaded: Int
    public var filesDownloaded: Int
    public var filesDeleted: Int

    public init(filesUploaded: Int = 0, filesDownloaded: Int = 0, filesDeleted: Int = 0) {
        self.filesUploaded = filesUploaded
        self.filesDownloaded = filesDownloaded
        self.filesDeleted = filesDeleted
    }
}

/// Events emitted by SyncClient.syncWithProgress() as sync progresses through stages.
public enum SyncProgressEvent: Sendable {
    case connecting
    case normalSync
    case fullDownloading
    case fullUploading
    case checkingDatabase
    case syncingMedia
    case noteStats(added: Int, removed: Int)
    case mediaStats(checked: String, added: String, removed: String)
    /// Media download progress: (total count, downloaded count)
    case mediaProgress(total: Int, downloaded: Int)
    /// Media download retry: (failed count, retry attempt, delay in seconds)
    case mediaRetry(failedCount: Int, attempt: Int, delaySeconds: Int)
    case completed(SyncSummary)
}

/// Configuration for adaptive media sync throttling
public struct AdaptiveThrottleConfig: Sendable {
    /// Minimum delay between requests (seconds)
    public var minDelaySecs: Double = 0.1
    /// Initial batch size for media downloads
    public var initialBatchSize: Int = 50
    /// Maximum concurrent operations
    public var maxConcurrentOps: Int = 3
    /// Failure rate threshold to trigger backoff
    public var failureRateThreshold: Double = 0.2
    /// Maximum retry attempts per file
    public var maxRetries: Int = 5
    /// Exponential backoff multiplier
    public var backoffMultiplier: Double = 2.0
    
    public init() {}
}

/// Metadata about a media file for download
public struct MediaFileInfo: Sendable, Hashable {
    public let filename: String
    public let checksum: String  // SHA-1 hash
    public let size: Int?
    
    public init(filename: String, checksum: String, size: Int? = nil) {
        self.filename = filename
        self.checksum = checksum
        self.size = size
    }
}
