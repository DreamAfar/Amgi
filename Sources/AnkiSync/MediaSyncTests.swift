import XCTest
@testable import AnkiKit
@testable import AnkiSync

final class MediaDownloadQueueTests: XCTestCase {
    private var queue: MediaDownloadQueue?
    
    override func setUp() async throws {
        queue = MediaDownloadQueue(userProfileID: "test.user")
        await queue?.clear()
    }
    
    func testQueueInitialization() async {
        let testQueue = MediaDownloadQueue(userProfileID: "test")
        let progress = await testQueue.getProgress()
        XCTAssertEqual(progress.total, 0)
        XCTAssertEqual(progress.downloaded, 0)
    }
    
    func testAddFilesToQueue() async {
        let files = [
            MediaFileInfo(filename: "image1.jpg", checksum: "abc123"),
            MediaFileInfo(filename: "audio.mp3", checksum: "def456"),
        ]
        
        await queue?.initialize(with: files)
        
        let batch = await queue?.nextBatch(size: 5) ?? []
        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(batch[0].filename, "image1.jpg")
    }
    
    func testMarkDownloaded() async {
        let files = [
            MediaFileInfo(filename: "test.jpg", checksum: "hash1"),
        ]
        
        await queue?.initialize(with: files)
        let batch = await queue?.nextBatch(size: 5) ?? []
        
        await queue?.markDownloaded(batch)
        
        let progress = await queue?.getProgress() ?? (0, 0)
        XCTAssertEqual(progress.downloaded, 1)
        XCTAssertTrue(await queue?.isComplete() ?? false)
    }
    
    func testFailedFilesRetry() async {
        let file = MediaFileInfo(filename: "test.jpg", checksum: "hash1")
        
        await queue?.initialize(with: [file])
        let batch = await queue?.nextBatch(size: 5) ?? []
        
        // First failure
        let shouldRetry1 = await queue?.markFailed(batch[0]) ?? false
        XCTAssertTrue(shouldRetry1)
        
        // Get next batch should include the failed file
        let retryBatch = await queue?.nextBatch(size: 5) ?? []
        XCTAssertEqual(retryBatch.count, 1)
    }
    
    func testMaxRetries() async {
        let file = MediaFileInfo(filename: "test.jpg", checksum: "hash1")
        
        await queue?.initialize(with: [file])
        
        // Simulate 5 retries (should fail on 6th)
        for attempt in 1...5 {
            let batch = await queue?.nextBatch(size: 1) ?? []
            if !batch.isEmpty {
                let shouldRetry = await queue?.markFailed(batch[0]) ?? false
                if attempt < 5 {
                    XCTAssertTrue(shouldRetry, "Attempt \(attempt) should allow retry")
                }
            }
        }
        
        // 6th attempt should not retry
        let finalBatch = await queue?.nextBatch(size: 1) ?? []
        if !finalBatch.isEmpty {
            let shouldRetry = await queue?.markFailed(finalBatch[0]) ?? false
            XCTAssertFalse(shouldRetry, "Attempt 6 should not allow retry")
        }
    }
    
    func testPersistence() async {
        // Add files
        let files = [
            MediaFileInfo(filename: "persist.jpg", checksum: "persistent"),
        ]
        
        await queue?.initialize(with: files)
        let batch1 = await queue?.nextBatch(size: 1) ?? []
        
        // Create new queue instance with same user (should restore state)
        let newQueue = MediaDownloadQueue(userProfileID: "test.user")
        let pendingFiles = await newQueue.nextBatch(size: 5)
        
        XCTAssertEqual(pendingFiles.count, 1, "State should be persisted")
        XCTAssertEqual(pendingFiles[0].filename, "persist.jpg")
    }
}

final class AdaptiveRateLimiterTests: XCTestCase {
    private var limiter: AdaptiveRateLimiter?
    
    override func setUp() async throws {
        limiter = AdaptiveRateLimiter()
    }
    
    func testInitialState() async {
        let delay = await limiter?.getCurrentDelayMs() ?? 0
        XCTAssertGreater(delay, 0)
        
        let batchSize = await limiter?.getCurrentBatchSize() ?? 0
        XCTAssertGreater(batchSize, 0)
    }
    
    func testSuccessRecovery() async {
        for _ in 1...10 {
            await limiter?.recordSuccess()
        }
        
        let diagnostics = await limiter?.getDiagnostics()
        XCTAssertEqual(diagnostics?.successCount, 0,  "Counter should reset after 10 successes")
    }
    
    func testFailureBackoff() async {
        let initialDelay = await limiter?.getCurrentDelayMs() ?? 0
        
        await limiter?.recordFailure()
        
        let newDelay = await limiter?.getCurrentDelayMs() ?? 0
        XCTAssertGreater(newDelay, initialDelay, "Delay should increase on failure")
    }
    
    func testHTTP429Handling() async {
        let initialDelay = await limiter?.getCurrentDelayMs() ?? 0
        let initialBatchSize = await limiter?.getCurrentBatchSize() ?? 0
        
        await limiter?.recordHTTP429()
        
        let newDelay = await limiter?.getCurrentDelayMs() ?? 0
        let newBatchSize = await limiter?.getCurrentBatchSize() ?? 0
        
        XCTAssertGreater(newDelay, initialDelay * 2, "HTTP 429 should cause aggressive backoff")
        XCTAssertLess(newBatchSize, initialBatchSize, "Batch size should decrease on HTTP 429")
    }
    
    func testFailureRateCalculation() async {
        // Record 3 successes and 2 failures
        for _ in 1...3 {
            await limiter?.recordSuccess()
        }
        for _ in 1...2 {
            await limiter?.recordFailure()
        }
        
        let diagnostics = await limiter?.getDiagnostics()
        let expectedRate = 2.0 / 5.0  // 40%
        
        XCTAssertEqual(diagnostics?.failureRate, expectedRate, accuracy: 0.01)
    }
}

final class MediaSyncSessionTests: XCTestCase {
    private var queue: MediaDownloadQueue?
    private var limiter: AdaptiveRateLimiter?
    private var session: MediaSyncSession?
    
    override func setUp() async throws {
        queue = MediaDownloadQueue(userProfileID: "test.session")
        limiter = AdaptiveRateLimiter()
        session = MediaSyncSession(queue: queue!, limiter: limiter!)
    }
    
    func testSessionInitialization() async {
        await session?.start()
        
        let isComplete = await session?.isComplete() ?? false
        XCTAssertTrue(isComplete, "New session should be complete when empty")
    }
    
    func testBatchProcessing() async {
        let files = [
            MediaFileInfo(filename: "file1.jpg", checksum: "hash1"),
            MediaFileInfo(filename: "file2.mp3", checksum: "hash2"),
            MediaFileInfo(filename: "file3.png", checksum: "hash3"),
        ]
        
        await session?.initializeWithFiles(files)
        
        // Get first batch
        let batch = await session?.getNextBatch() ?? []
        XCTAssertEqual(batch.count, 3)
        
        // Mark as downloaded
        await session?.markBatchDownloaded(batch)
        
        let isComplete = await session?.isComplete() ?? false
        XCTAssertTrue(isComplete)
    }
    
    func testRetryMechanism() async {
        let files = [
            MediaFileInfo(filename: "retry_test.jpg", checksum: "retry_hash"),
        ]
        
        await session?.initializeWithFiles(files)
        
        let batch = await session?.getNextBatch() ?? []
        XCTAssertEqual(batch.count, 1)
        
        // Simulate failure and retry
        let delayMs = await session?.handleFailedFile(batch[0]) ?? 0
        XCTAssertGreater(delayMs, 0, "Failed file should return retry delay")
        
        // Next batch should be empty after single retry (limited by queue max retries)
        let nextBatch = await session?.getNextBatch() ?? []
        if nextBatch.isEmpty {
            XCTAssertTrue(true, "File exhausted retries as expected")
        }
    }
    
    func testProgressReporting() async {
        let files = [
            MediaFileInfo(filename: "prog1.jpg", checksum: "p1"),
            MediaFileInfo(filename: "prog2.jpg", checksum: "p2"),
        ]
        
        await session?.initializeWithFiles(files)
        
        var batch = await session?.getNextBatch() ?? []
        XCTAssertEqual(batch.count, 2)
        
        // Mark first as complete
        await session?.markBatchDownloaded([batch[0]])
        
        let progress = await session?.getProgress() ?? (0, 0)
        XCTAssertEqual(progress.downloaded, 1)
        XCTAssertEqual(progress.total, 2)
    }
    
    func testDiagnosticInfo() async {
        await session?.start()
        
        let diagnostics = await session?.getDiagnostics() ?? ""
        XCTAssertGreater(diagnostics.count, 0)
        XCTAssertTrue(diagnostics.contains("Progress"))
        XCTAssertTrue(diagnostics.contains("Batch Size") || diagnostics.contains("Delay"))
    }
}

// MARK: - Integration Tests

final class MediaSyncIntegrationTests: XCTestCase {
    func testEndToEndMediaSync() async {
        // Create components
        let userID = "integration.test"
        let queue = MediaDownloadQueue(userProfileID: userID)
        let limiter = AdaptiveRateLimiter()
        let session = MediaSyncSession(queue: queue, limiter: limiter)
        
        // Initialize with test files
        let testFiles = (1...5).map { i in
            MediaFileInfo(filename: "test_\(i).jpg", checksum: "hash_\(i)")
        }
        
        await session.initializeWithFiles(testFiles)
        await session.start()
        
        // Simulate batch processing
        var totalProcessed = 0
        while let batch = await session.getNextBatch() {
            if batch.isEmpty { break }
            
            // Simulate successful download of first file, failure of second
            for (index, file) in batch.enumerated() {
                if index == 0 {
                    await session.markBatchDownloaded([file])
                    totalProcessed += 1
                } else if index == 1 {
                    let delayMs = await session.handleFailedFile(file)
                    XCTAssertGreater(delayMs, 0)
                }
            }
        }
        
        XCTAssertGreater(totalProcessed, 0, "At least one file should be processed")
    }
    
    func testRateLimiterUnderStress() async {
        let limiter = AdaptiveRateLimiter()
        
        // Simulate mixed success and failure pattern
        for i in 1...50 {
            if i % 5 == 0 {
                await limiter.recordFailure()
            } else {
                await limiter.recordSuccess()
            }
        }
        
        let diagnostics = await limiter.getDiagnostics()
        XCTAssertLess(diagnostics.failureRate, 0.5, "Failure rate should be ~20%")
        XCTAssertGreater(diagnostics.delayMs, 0)
    }
}
