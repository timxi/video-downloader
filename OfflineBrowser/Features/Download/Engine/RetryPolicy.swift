import Foundation

struct RetryPolicy {
    static let maxRetries = 5
    static let baseDelay: TimeInterval = 1.0
    static let maxDelay: TimeInterval = 60.0

    /// Calculate delay with exponential backoff
    static func delay(for retryCount: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(retryCount))
        return min(exponentialDelay, maxDelay)
    }

    /// Check if retry is allowed
    static func shouldRetry(retryCount: Int) -> Bool {
        retryCount < maxRetries
    }

    /// Calculate delay with jitter to avoid thundering herd
    static func delayWithJitter(for retryCount: Int) -> TimeInterval {
        let baseDelay = delay(for: retryCount)
        let jitter = Double.random(in: 0...0.3) * baseDelay
        return baseDelay + jitter
    }
}
