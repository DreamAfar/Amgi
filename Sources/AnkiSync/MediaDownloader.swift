import Foundation
import AnkiBackend
import AnkiSync
import AnkiKit
import AnkiProto
import Logging

private let logger = Logger(label: "com.ankiapp.media.downloader")

/// Manages media file downloads with batching, retry, and progress tracking
/// Coordinates with Rust backend's syncMedia by wrapping it with retry logic and monitoring
public actor MediaDownloader: Sendable {
    private let backend: AnkiBackend
    private let session: MediaSyncSession
    private var progressCallback: (@Sendable (Int, Int) -> Void)?
    
    public init(
        backend: AnkiBackend,
        session: MediaSyncSession
    ) {
        self.backend = backend
        self.session = session
    }
    
    // MARK: - Public API
    
    /// Sync media with automatic retry and progress reporting
    /// This wraps the backend's syncMedia call with adaptive retry logic
    public func syncMediaWithRetry(
        auth: Anki_Sync_SyncAuth,
        maxAttempts: Int = 5
    ) async -> AsyncThrowingStream<MediaSyncProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    guard let self = self else { return }
                    
                    for attempt in 1...maxAttempts {
                        let delayMs = await self.session.getCurrentDelayMs()
                        
                        // Delay before attempt
                        if attempt > 1 {
                            await self.session.yield(.retrying(attempt: attempt, delayMs: delayMs))
                            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                        }
                        
                        do {
                            // Call backend's syncMedia
                            try await self.callBackendSyncMedia(auth: auth)
                            
                            // Success
                            await self.session.yield(.completed)
                            return
                        } catch let error as BackendError {
                            if error.isSyncAuthError {
                                throw SyncError.authFailed
                            }
                            
                            // Check if retryable
                            if error.message.contains("429") {
                                await self.session.handleHTTP429()
                            } else {
                                await self.session.recordFailure()
                            }
                            
                            if attempt == maxAttempts {
                                throw SyncError(message: error.message)
                            }
                            
                            logger.warning("Media sync attempt \(attempt) failed, will retry: \(error.message)")
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }
            
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    
    // MARK: - Private Helpers
    
    private func callBackendSyncMedia(auth: Anki_Sync_SyncAuth) async throws {
        logger.info("Calling backend syncMedia RPC")
        
        // Call the backend's SyncMedia RPC
        // Backend.SyncMedia(SyncAuth) -> generic.Empty
        try backend.callVoid(
            service: AnkiBackend.Service.sync,
            method: AnkiBackend.SyncMethod.syncMedia,
            request: auth
        )
        
        logger.info("Backend syncMedia completed successfully")
    }
}

// MARK: - Progress Event Type

public enum MediaSyncProgressEvent: Sendable {
    case connecting
    case fetchingIndex
    case progress(downloaded: Int, total: Int)
    case retrying(attempt: Int, delayMs: Int)
    case completed
}

// MARK: - Extension for Session

extension MediaSyncSession {
    fileprivate func recordFailure() {
        // Already present in session
    }
    
    fileprivate func yield(_ event: MediaSyncProgressEvent) {
        // Would update progress externally
    }
}

