public import Foundation
public import AnkiKit
import Logging

private let logger = Logger(label: "com.ankiapp.background.sync")

/// Manages iOS background download sessions for media sync
public actor BackgroundSyncManager: Sendable {
    public static let shared = BackgroundSyncManager()
    
    private let backgroundSessionID = "com.ankiapp.media.background.session"
    private var backgroundSession: URLSession?
    private var downloadTasksInProgress: [Int: (filename: String, progress: Double)] = [:]
    
    private init() {
        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionID)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.shouldUseExtendedBackgroundIdleMode = true
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 86400
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.backgroundSession = URLSession(
            configuration: config,
            delegate: BackgroundSessionDelegate.shared,
            delegateQueue: OperationQueue()
        )
    }
    
    // MARK: - Public API
    
    /// Start a background download session
    public func startBackgroundDownload(
        url: URL,
        filename: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> URLSessionDownloadTask {
        guard let session = backgroundSession else {
            completion(.failure(SyncError(message: "Background session not available")))
            return URLSessionDownloadTask()
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3600  // 1 hour for background downloads
        
        let task = session.downloadTask(with: request)
        task.resume()
        
        logger.info("Started background download: \(filename)")
        return task
    }
    
    /// Get list of active downloads
    public func getActiveDownloads() async -> [(taskID: Int, filename: String, progress: Double)] {
        return downloadTasksInProgress.map { (taskID: $0.key, filename: $0.value.filename, progress: $0.value.progress) }
    }
    
    /// Resume interrupted downloads
    public func resumeInterruptedDownloads() async {
        logger.info("Resuming interrupted background downloads")
        if let backgroundSession = backgroundSession {
            let tasks = await backgroundSession.allTasks
            for task in tasks where task.state == .suspended {
                task.resume()
                logger.info("Resumed task: \(task.taskIdentifier)")
            }
        }
    }
    
    // MARK: - URLSession Delegate

private final class BackgroundSessionDelegate: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static let shared = BackgroundSessionDelegate()
    
    private override init() {
        super.init()
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        logger.info("Background download completed: \(downloadTask.taskIdentifier)")
        
        // Post notification for app to handle file
        NotificationCenter.default.post(
            name: NSNotification.Name("BackgroundMediaDownloadCompleted"),
            object: ["taskID": downloadTask.taskIdentifier, "location": location],
            userInfo: nil
        )
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        NotificationCenter.default.post(
            name: NSNotification.Name("BackgroundMediaDownloadProgress"),
            object: [
                "taskID": downloadTask.taskIdentifier,
                "progress": progress,
                "bytesWritten": totalBytesWritten
            ],
            userInfo: nil
        )
    }
    
    // MARK: - URLSessionDelegate
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            logger.error("Background task failed: \(task.taskIdentifier) - \(error.localizedDescription)")
            
            // Determine if retryable
            let nsError = error as NSError
            let isRetryable = nsError.code != NSURLErrorCancelled && nsError.code != NSURLErrorUnknown
            
            NotificationCenter.default.post(
                name: NSNotification.Name("BackgroundMediaDownloadFailed"),
                object: [
                    "taskID": task.taskIdentifier,
                    "error": error.localizedDescription,
                    "isRetryable": isRetryable
                ],
                userInfo: nil
            )
        } else {
            logger.info("Background task completed successfully: \(task.taskIdentifier)")
        }
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Called when all background tasks complete
        logger.info("All background download tasks completed")
        
        NotificationCenter.default.post(
            name: NSNotification.Name("BackgroundMediaDownloadSessionComplete"),
            object: nil,
            userInfo: nil
        )
    }
}

// MARK: - Notification Names Extensions

extension NSNotification.Name {
    public static let backgroundMediaDownloadCompleted = NSNotification.Name("BackgroundMediaDownloadCompleted")
    public static let backgroundMediaDownloadProgress = NSNotification.Name("BackgroundMediaDownloadProgress")
    public static let backgroundMediaDownloadFailed = NSNotification.Name("BackgroundMediaDownloadFailed")
    public static let backgroundMediaDownloadSessionComplete = NSNotification.Name("BackgroundMediaDownloadSessionComplete")
}

// MARK: - Placeholder SyncError

extension SyncError {
    // Already defined in AnkiKit
}
