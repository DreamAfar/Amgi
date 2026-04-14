import Foundation
import AnkiKit

/// Adapts request rate based on failure patterns and server responses.
public actor AdaptiveRateLimiter: Sendable {
    private var currentDelayMs: Int
    private var batchSize: Int
    private var successCount: Int = 0
    private var failureCount: Int = 0
    private var http429Count: Int = 0
    
    private let minDelayMs: Int
    private let maxDelayMs: Int = 30000  // 30 seconds max
    private let config: AdaptiveThrottleConfig
    
    public init(config: AdaptiveThrottleConfig = AdaptiveThrottleConfig()) {
        self.config = config
        self.minDelayMs = Int(config.minDelaySecs * 1000)
        self.currentDelayMs = self.minDelayMs
        self.batchSize = config.initialBatchSize
    }
    
    // MARK: - Public API
    
    /// Get current delay in milliseconds before next request
    public func getCurrentDelayMs() -> Int {
        return currentDelayMs
    }
    
    /// Get current batch size
    public func getCurrentBatchSize() -> Int {
        return batchSize
    }
    
    /// Record successful operation
    public func recordSuccess() {
        successCount += 1
        
        // After 10 consecutive successes, gradually reduce delay
        if successCount >= 10 {
            let newDelay = max(minDelayMs, Int(Double(currentDelayMs) * 0.8))
            currentDelayMs = newDelay
            successCount = 0
        }
        
        // Increase batch size after multiple successes
        if successCount >= 5 && batchSize < config.initialBatchSize * 2 {
            batchSize = min(config.initialBatchSize * 2, batchSize + 10)
        }
    }
    
    /// Record failed operation
    public func recordFailure() {
        failureCount += 1
        successCount = 0  // Reset success counter
        
        // Exponential backoff on failures
        let newDelay = min(
            maxDelayMs,
            Int(Double(currentDelayMs) * config.backoffMultiplier)
        )
        currentDelayMs = newDelay
        
        // Reduce batch size on failures
        batchSize = max(1, batchSize - 5)
    }
    
    /// Record HTTP 429 (rate limited) response
    public func recordHTTP429() {
        http429Count += 1
        failureCount += 1
        successCount = 0
        
        // Aggressive backoff for rate limiting
        let newDelay = min(
            maxDelayMs,
            Int(Double(currentDelayMs) * config.backoffMultiplier * 2)
        )
        currentDelayMs = newDelay
        
        // Significantly reduce batch size
        batchSize = max(1, Int(Double(batchSize) * 0.5))
    }
    
    /// Get current failure rate
    public func getFailureRate() -> Double {
        let total = successCount + failureCount
        guard total > 0 else { return 0.0 }
        return Double(failureCount) / Double(total)
    }
    
    /// Check if should trigger aggressive backoff
    public func shouldAggressiveBackoff() -> Bool {
        return getFailureRate() >= config.failureRateThreshold
    }
    
    /// Reset statistics
    public func resetStats() {
        successCount = 0
        failureCount = 0
        http429Count = 0
        currentDelayMs = minDelayMs
        batchSize = config.initialBatchSize
    }
    
    // MARK: - Diagnostic Info
    
    public struct DiagnosticInfo {
        let delayMs: Int
        let batchSize: Int
        let failureRate: Double
        let successCount: Int
        let failureCount: Int
        let http429Count: Int
    }
    
    public func getDiagnostics() -> DiagnosticInfo {
        return DiagnosticInfo(
            delayMs: currentDelayMs,
            batchSize: batchSize,
            failureRate: getFailureRate(),
            successCount: successCount,
            failureCount: failureCount,
            http429Count: http429Count
        )
    }
}
