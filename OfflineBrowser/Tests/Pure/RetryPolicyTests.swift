import XCTest
@testable import OfflineBrowser

final class RetryPolicyTests: XCTestCase {

    // MARK: - delay(for:) Tests

    func testDelay_retryCount0_returnsBaseDelay() {
        let delay = RetryPolicy.delay(for: 0)
        XCTAssertEqual(delay, 1.0, accuracy: 0.001)
    }

    func testDelay_retryCount1_returns2Seconds() {
        let delay = RetryPolicy.delay(for: 1)
        XCTAssertEqual(delay, 2.0, accuracy: 0.001)
    }

    func testDelay_retryCount2_returns4Seconds() {
        let delay = RetryPolicy.delay(for: 2)
        XCTAssertEqual(delay, 4.0, accuracy: 0.001)
    }

    func testDelay_retryCount3_returns8Seconds() {
        let delay = RetryPolicy.delay(for: 3)
        XCTAssertEqual(delay, 8.0, accuracy: 0.001)
    }

    func testDelay_retryCount4_returns16Seconds() {
        let delay = RetryPolicy.delay(for: 4)
        XCTAssertEqual(delay, 16.0, accuracy: 0.001)
    }

    func testDelay_retryCount5_returns32Seconds() {
        let delay = RetryPolicy.delay(for: 5)
        XCTAssertEqual(delay, 32.0, accuracy: 0.001)
    }

    func testDelay_retryCount6_capsAtMaxDelay() {
        // 2^6 = 64, but max is 60
        let delay = RetryPolicy.delay(for: 6)
        XCTAssertEqual(delay, 60.0, accuracy: 0.001)
    }

    func testDelay_retryCount10_capsAtMaxDelay() {
        // 2^10 = 1024, but max is 60
        let delay = RetryPolicy.delay(for: 10)
        XCTAssertEqual(delay, 60.0, accuracy: 0.001)
    }

    func testDelay_veryHighRetryCount_capsAtMaxDelay() {
        let delay = RetryPolicy.delay(for: 100)
        XCTAssertEqual(delay, 60.0, accuracy: 0.001)
    }

    // MARK: - shouldRetry(retryCount:) Tests

    func testShouldRetry_retryCount0_returnsTrue() {
        XCTAssertTrue(RetryPolicy.shouldRetry(retryCount: 0))
    }

    func testShouldRetry_retryCount1_returnsTrue() {
        XCTAssertTrue(RetryPolicy.shouldRetry(retryCount: 1))
    }

    func testShouldRetry_retryCount4_returnsTrue() {
        XCTAssertTrue(RetryPolicy.shouldRetry(retryCount: 4))
    }

    func testShouldRetry_retryCount5_returnsFalse() {
        // maxRetries is 5, so retryCount of 5 means we've already retried 5 times
        XCTAssertFalse(RetryPolicy.shouldRetry(retryCount: 5))
    }

    func testShouldRetry_retryCount6_returnsFalse() {
        XCTAssertFalse(RetryPolicy.shouldRetry(retryCount: 6))
    }

    func testShouldRetry_highRetryCount_returnsFalse() {
        XCTAssertFalse(RetryPolicy.shouldRetry(retryCount: 100))
    }

    // MARK: - delayWithJitter(for:) Tests

    func testDelayWithJitter_retryCount0_returnsValueInExpectedRange() {
        // Base delay is 1.0, jitter adds 0-30% (0 to 0.3)
        // So expected range is 1.0 to 1.3
        for _ in 0..<10 {
            let delay = RetryPolicy.delayWithJitter(for: 0)
            XCTAssertGreaterThanOrEqual(delay, 1.0)
            XCTAssertLessThanOrEqual(delay, 1.3)
        }
    }

    func testDelayWithJitter_retryCount2_returnsValueInExpectedRange() {
        // Base delay is 4.0, jitter adds 0-30% (0 to 1.2)
        // So expected range is 4.0 to 5.2
        for _ in 0..<10 {
            let delay = RetryPolicy.delayWithJitter(for: 2)
            XCTAssertGreaterThanOrEqual(delay, 4.0)
            XCTAssertLessThanOrEqual(delay, 5.2)
        }
    }

    func testDelayWithJitter_atMaxDelay_returnsValueInExpectedRange() {
        // Base delay is 60.0 (capped), jitter adds 0-30% (0 to 18)
        // So expected range is 60.0 to 78.0
        for _ in 0..<10 {
            let delay = RetryPolicy.delayWithJitter(for: 10)
            XCTAssertGreaterThanOrEqual(delay, 60.0)
            XCTAssertLessThanOrEqual(delay, 78.0)
        }
    }

    func testDelayWithJitter_producesVariation() {
        // Run multiple times and check that we get different values
        var delays: Set<Double> = []
        for _ in 0..<20 {
            let delay = RetryPolicy.delayWithJitter(for: 2)
            delays.insert(delay)
        }
        // With jitter, we should get multiple distinct values
        XCTAssertGreaterThan(delays.count, 1, "Jitter should produce variation")
    }

    // MARK: - Constants Tests

    func testMaxRetries_isFive() {
        XCTAssertEqual(RetryPolicy.maxRetries, 5)
    }

    func testBaseDelay_isOne() {
        XCTAssertEqual(RetryPolicy.baseDelay, 1.0, accuracy: 0.001)
    }

    func testMaxDelay_isSixty() {
        XCTAssertEqual(RetryPolicy.maxDelay, 60.0, accuracy: 0.001)
    }
}
