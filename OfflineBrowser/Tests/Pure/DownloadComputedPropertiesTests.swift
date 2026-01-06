import XCTest
@testable import OfflineBrowser

final class DownloadComputedPropertiesTests: XCTestCase {

    // MARK: - formattedProgress Tests

    func testFormattedProgress_zero_formats0Percent() {
        let download = TestFixtures.makeDownload(progress: 0.0)
        XCTAssertEqual(download.formattedProgress, "0%")
    }

    func testFormattedProgress_50percent_formats50Percent() {
        let download = TestFixtures.makeDownload(progress: 0.5)
        XCTAssertEqual(download.formattedProgress, "50%")
    }

    func testFormattedProgress_100percent_formats100Percent() {
        let download = TestFixtures.makeDownload(progress: 1.0)
        XCTAssertEqual(download.formattedProgress, "100%")
    }

    func testFormattedProgress_33percent_formats33Percent() {
        let download = TestFixtures.makeDownload(progress: 0.33)
        XCTAssertEqual(download.formattedProgress, "33%")
    }

    func testFormattedProgress_roundsDown() {
        let download = TestFixtures.makeDownload(progress: 0.999)
        XCTAssertEqual(download.formattedProgress, "100%")
    }

    func testFormattedProgress_smallValue_formats1Percent() {
        let download = TestFixtures.makeDownload(progress: 0.015)
        XCTAssertEqual(download.formattedProgress, "2%")
    }

    // MARK: - isActive Tests

    func testIsActive_downloading_returnsTrue() {
        let download = TestFixtures.makeDownload(status: .downloading)
        XCTAssertTrue(download.isActive)
    }

    func testIsActive_muxing_returnsTrue() {
        let download = TestFixtures.makeDownload(status: .muxing)
        XCTAssertTrue(download.isActive)
    }

    func testIsActive_pending_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .pending)
        XCTAssertFalse(download.isActive)
    }

    func testIsActive_paused_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .paused)
        XCTAssertFalse(download.isActive)
    }

    func testIsActive_completed_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .completed)
        XCTAssertFalse(download.isActive)
    }

    func testIsActive_failed_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .failed)
        XCTAssertFalse(download.isActive)
    }

    // MARK: - canRetry Tests

    func testCanRetry_failedWithZeroRetries_returnsTrue() {
        let download = TestFixtures.makeDownload(status: .failed, retryCount: 0)
        XCTAssertTrue(download.canRetry)
    }

    func testCanRetry_failedWithFourRetries_returnsTrue() {
        let download = TestFixtures.makeDownload(status: .failed, retryCount: 4)
        XCTAssertTrue(download.canRetry)
    }

    func testCanRetry_failedWithFiveRetries_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .failed, retryCount: 5)
        XCTAssertFalse(download.canRetry)
    }

    func testCanRetry_failedWithSixRetries_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .failed, retryCount: 6)
        XCTAssertFalse(download.canRetry)
    }

    func testCanRetry_pendingStatus_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .pending, retryCount: 0)
        XCTAssertFalse(download.canRetry)
    }

    func testCanRetry_downloadingStatus_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .downloading, retryCount: 0)
        XCTAssertFalse(download.canRetry)
    }

    func testCanRetry_pausedStatus_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .paused, retryCount: 0)
        XCTAssertFalse(download.canRetry)
    }

    func testCanRetry_completedStatus_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .completed, retryCount: 0)
        XCTAssertFalse(download.canRetry)
    }

    func testCanRetry_muxingStatus_returnsFalse() {
        let download = TestFixtures.makeDownload(status: .muxing, retryCount: 0)
        XCTAssertFalse(download.canRetry)
    }

    // MARK: - incrementRetry() Tests

    func testIncrementRetry_incrementsRetryCount() {
        var download = TestFixtures.makeDownload(retryCount: 0)
        let originalUpdatedAt = download.updatedAt

        // Small delay to ensure updatedAt changes
        Thread.sleep(forTimeInterval: 0.01)

        download.incrementRetry()

        XCTAssertEqual(download.retryCount, 1)
        XCTAssertGreaterThan(download.updatedAt, originalUpdatedAt)
    }

    func testIncrementRetry_multipleIncrements() {
        var download = TestFixtures.makeDownload(retryCount: 0)

        download.incrementRetry()
        download.incrementRetry()
        download.incrementRetry()

        XCTAssertEqual(download.retryCount, 3)
    }

    func testIncrementRetry_updatesUpdatedAt() {
        var download = TestFixtures.makeDownload(retryCount: 2)
        let before = Date()

        Thread.sleep(forTimeInterval: 0.01)
        download.incrementRetry()

        XCTAssertGreaterThanOrEqual(download.updatedAt, before)
    }

    // MARK: - updateProgress(_:segmentsDownloaded:) Tests

    func testUpdateProgress_updatesProgressAndSegments() {
        var download = TestFixtures.makeDownload(progress: 0.0, segmentsDownloaded: 0)

        download.updateProgress(0.5, segmentsDownloaded: 50)

        XCTAssertEqual(download.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(download.segmentsDownloaded, 50)
    }

    func testUpdateProgress_updatesUpdatedAt() {
        var download = TestFixtures.makeDownload()
        let before = Date()

        Thread.sleep(forTimeInterval: 0.01)
        download.updateProgress(0.75, segmentsDownloaded: 75)

        XCTAssertGreaterThanOrEqual(download.updatedAt, before)
    }

    // MARK: - fail(with:) Tests

    func testFail_setsStatusToFailed() {
        var download = TestFixtures.makeDownload(status: .downloading)

        download.fail(with: "Network error")

        XCTAssertEqual(download.status, .failed)
    }

    func testFail_setsErrorMessage() {
        var download = TestFixtures.makeDownload(status: .downloading)

        download.fail(with: "Network error")

        XCTAssertEqual(download.errorMessage, "Network error")
    }

    func testFail_updatesUpdatedAt() {
        var download = TestFixtures.makeDownload(status: .downloading)
        let before = Date()

        Thread.sleep(forTimeInterval: 0.01)
        download.fail(with: "Error")

        XCTAssertGreaterThanOrEqual(download.updatedAt, before)
    }

    // MARK: - DownloadStatus Tests

    func testDownloadStatus_rawValues() {
        XCTAssertEqual(DownloadStatus.pending.rawValue, "pending")
        XCTAssertEqual(DownloadStatus.downloading.rawValue, "downloading")
        XCTAssertEqual(DownloadStatus.paused.rawValue, "paused")
        XCTAssertEqual(DownloadStatus.muxing.rawValue, "muxing")
        XCTAssertEqual(DownloadStatus.completed.rawValue, "completed")
        XCTAssertEqual(DownloadStatus.failed.rawValue, "failed")
    }
}
