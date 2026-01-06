import XCTest
@testable import OfflineBrowser

final class VideoComputedPropertiesTests: XCTestCase {

    // MARK: - formattedDuration Tests

    func testFormattedDuration_zeroSeconds_formats0_00() {
        let video = TestFixtures.makeVideo(duration: 0)
        XCTAssertEqual(video.formattedDuration, "0:00")
    }

    func testFormattedDuration_30seconds_formats0_30() {
        let video = TestFixtures.makeVideo(duration: 30)
        XCTAssertEqual(video.formattedDuration, "0:30")
    }

    func testFormattedDuration_59seconds_formats0_59() {
        let video = TestFixtures.makeVideo(duration: 59)
        XCTAssertEqual(video.formattedDuration, "0:59")
    }

    func testFormattedDuration_60seconds_formats1_00() {
        let video = TestFixtures.makeVideo(duration: 60)
        XCTAssertEqual(video.formattedDuration, "1:00")
    }

    func testFormattedDuration_90seconds_formats1_30() {
        let video = TestFixtures.makeVideo(duration: 90)
        XCTAssertEqual(video.formattedDuration, "1:30")
    }

    func testFormattedDuration_5minutes_formats5_00() {
        let video = TestFixtures.makeVideo(duration: 300)
        XCTAssertEqual(video.formattedDuration, "5:00")
    }

    func testFormattedDuration_10minutes30seconds_formats10_30() {
        let video = TestFixtures.makeVideo(duration: 630)
        XCTAssertEqual(video.formattedDuration, "10:30")
    }

    func testFormattedDuration_59minutes59seconds_formats59_59() {
        let video = TestFixtures.makeVideo(duration: 3599)
        XCTAssertEqual(video.formattedDuration, "59:59")
    }

    func testFormattedDuration_1hour_formats1_00_00() {
        let video = TestFixtures.makeVideo(duration: 3600)
        XCTAssertEqual(video.formattedDuration, "1:00:00")
    }

    func testFormattedDuration_1hour1minute1second_formats1_01_01() {
        let video = TestFixtures.makeVideo(duration: 3661)
        XCTAssertEqual(video.formattedDuration, "1:01:01")
    }

    func testFormattedDuration_2hours30minutes45seconds_formats2_30_45() {
        let video = TestFixtures.makeVideo(duration: 9045)
        XCTAssertEqual(video.formattedDuration, "2:30:45")
    }

    func testFormattedDuration_10hours_formats10_00_00() {
        let video = TestFixtures.makeVideo(duration: 36000)
        XCTAssertEqual(video.formattedDuration, "10:00:00")
    }

    func testFormattedDuration_singleDigitSeconds_padsWithZero() {
        let video = TestFixtures.makeVideo(duration: 65) // 1:05
        XCTAssertEqual(video.formattedDuration, "1:05")
    }

    func testFormattedDuration_singleDigitMinutesWithHours_padsWithZero() {
        let video = TestFixtures.makeVideo(duration: 3665) // 1:01:05
        XCTAssertEqual(video.formattedDuration, "1:01:05")
    }

    // MARK: - formattedFileSize Tests

    func testFormattedFileSize_zeroBytes_formatsCorrectly() {
        let video = TestFixtures.makeVideo(fileSize: 0)
        XCTAssertEqual(video.formattedFileSize, "Zero KB")
    }

    func testFormattedFileSize_1KB_formatsCorrectly() {
        let video = TestFixtures.makeVideo(fileSize: 1024)
        XCTAssertEqual(video.formattedFileSize, "1 KB")
    }

    func testFormattedFileSize_1MB_formatsCorrectly() {
        let video = TestFixtures.makeVideo(fileSize: 1_048_576)
        XCTAssertEqual(video.formattedFileSize, "1 MB")
    }

    func testFormattedFileSize_1GB_formatsCorrectly() {
        // ByteCountFormatter with .file style uses decimal (1000-based) counting
        let video = TestFixtures.makeVideo(fileSize: 1_000_000_000)
        XCTAssertEqual(video.formattedFileSize, "1 GB")
    }

    func testFormattedFileSize_1point5GB_formatsCorrectly() {
        let video = TestFixtures.makeVideo(fileSize: 1_500_000_000)
        // ByteCountFormatter uses decimal (1000-based) for .file style
        XCTAssertTrue(video.formattedFileSize.contains("GB") || video.formattedFileSize.contains("MB"))
    }

    func testFormattedFileSize_500MB_formatsCorrectly() {
        let video = TestFixtures.makeVideo(fileSize: 500_000_000)
        XCTAssertTrue(video.formattedFileSize.contains("MB"))
    }

    func testFormattedFileSize_largeFile_formatsCorrectly() {
        let video = TestFixtures.makeVideo(fileSize: 10_000_000_000) // ~10 GB
        XCTAssertTrue(video.formattedFileSize.contains("GB"))
    }
}
