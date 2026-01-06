import XCTest
@testable import OfflineBrowser

final class StreamQualityExtensionsTests: XCTestCase {

    // MARK: - formattedBandwidth Tests

    func testFormattedBandwidth_5Mbps_formatsCorrectly() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 5_000_000)
        XCTAssertEqual(quality.formattedBandwidth, "5.0 Mbps")
    }

    func testFormattedBandwidth_2500Kbps_formatsCorrectly() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 2_500_000)
        XCTAssertEqual(quality.formattedBandwidth, "2.5 Mbps")
    }

    func testFormattedBandwidth_500Kbps_formatsCorrectly() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 500_000)
        XCTAssertEqual(quality.formattedBandwidth, "0.5 Mbps")
    }

    func testFormattedBandwidth_zeroBandwidth_formatsCorrectly() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 0)
        XCTAssertEqual(quality.formattedBandwidth, "0.0 Mbps")
    }

    func testFormattedBandwidth_1234567bps_formatsCorrectly() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 1_234_567)
        XCTAssertEqual(quality.formattedBandwidth, "1.2 Mbps")
    }

    // MARK: - sortedByQuality Tests

    func testSortedByQuality_sortsDescendingByBandwidth() {
        let qualities = TestFixtures.makeQualities().shuffled()
        let sorted = qualities.sortedByQuality

        XCTAssertEqual(sorted.count, 4)
        XCTAssertEqual(sorted[0].bandwidth, 5_000_000)
        XCTAssertEqual(sorted[1].bandwidth, 2_500_000)
        XCTAssertEqual(sorted[2].bandwidth, 1_000_000)
        XCTAssertEqual(sorted[3].bandwidth, 500_000)
    }

    func testSortedByQuality_emptyArray_returnsEmpty() {
        let qualities: [StreamQuality] = []
        XCTAssertTrue(qualities.sortedByQuality.isEmpty)
    }

    func testSortedByQuality_singleElement_returnsSameElement() {
        let quality = TestFixtures.makeStreamQuality()
        let sorted = [quality].sortedByQuality

        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted[0].id, quality.id)
    }

    // MARK: - highest Tests

    func testHighest_returnsHighestBandwidth() {
        let qualities = TestFixtures.makeQualities()
        let highest = qualities.highest

        XCTAssertNotNil(highest)
        XCTAssertEqual(highest?.bandwidth, 5_000_000)
        XCTAssertEqual(highest?.resolution, "1080p")
    }

    func testHighest_emptyArray_returnsNil() {
        let qualities: [StreamQuality] = []
        XCTAssertNil(qualities.highest)
    }

    func testHighest_singleElement_returnsThatElement() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 1_000_000)
        let highest = [quality].highest

        XCTAssertNotNil(highest)
        XCTAssertEqual(highest?.id, quality.id)
    }

    func testHighest_shuffledArray_stillReturnsHighest() {
        let qualities = TestFixtures.makeQualities().shuffled()
        let highest = qualities.highest

        XCTAssertNotNil(highest)
        XCTAssertEqual(highest?.bandwidth, 5_000_000)
    }

    // MARK: - lowest Tests

    func testLowest_returnsLowestBandwidth() {
        let qualities = TestFixtures.makeQualities()
        let lowest = qualities.lowest

        XCTAssertNotNil(lowest)
        XCTAssertEqual(lowest?.bandwidth, 500_000)
        XCTAssertEqual(lowest?.resolution, "360p")
    }

    func testLowest_emptyArray_returnsNil() {
        let qualities: [StreamQuality] = []
        XCTAssertNil(qualities.lowest)
    }

    func testLowest_singleElement_returnsThatElement() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 1_000_000)
        let lowest = [quality].lowest

        XCTAssertNotNil(lowest)
        XCTAssertEqual(lowest?.id, quality.id)
    }

    func testLowest_shuffledArray_stillReturnsLowest() {
        let qualities = TestFixtures.makeQualities().shuffled()
        let lowest = qualities.lowest

        XCTAssertNotNil(lowest)
        XCTAssertEqual(lowest?.bandwidth, 500_000)
    }

    // MARK: - quality(matching:) Tests

    func testQualityMatching_highest_returnsHighestBandwidth() {
        let qualities = TestFixtures.makeQualities()
        let matched = qualities.quality(matching: "highest")

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.bandwidth, 5_000_000)
    }

    func testQualityMatching_lowest_returnsLowestBandwidth() {
        let qualities = TestFixtures.makeQualities()
        let matched = qualities.quality(matching: "lowest")

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.bandwidth, 500_000)
    }

    func testQualityMatching_720p_returns720pVariant() {
        let qualities = TestFixtures.makeQualities()
        let matched = qualities.quality(matching: "720p")

        XCTAssertNotNil(matched)
        XCTAssertTrue(matched?.resolution.contains("720") ?? false)
        XCTAssertEqual(matched?.bandwidth, 2_500_000)
    }

    func testQualityMatching_1080p_returns1080pVariant() {
        let qualities = TestFixtures.makeQualities()
        let matched = qualities.quality(matching: "1080p")

        XCTAssertNotNil(matched)
        XCTAssertTrue(matched?.resolution.contains("1080") ?? false)
        XCTAssertEqual(matched?.bandwidth, 5_000_000)
    }

    func testQualityMatching_720p_notAvailable_fallsBackToHighest() {
        // Create qualities without 720p
        let qualities = [
            TestFixtures.makeStreamQuality(resolution: "1080p", bandwidth: 5_000_000),
            TestFixtures.makeStreamQuality(resolution: "480p", bandwidth: 1_000_000)
        ]
        let matched = qualities.quality(matching: "720p")

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.bandwidth, 5_000_000) // Falls back to highest
    }

    func testQualityMatching_1080p_notAvailable_fallsBackToHighest() {
        // Create qualities without 1080p
        let qualities = [
            TestFixtures.makeStreamQuality(resolution: "720p", bandwidth: 2_500_000),
            TestFixtures.makeStreamQuality(resolution: "480p", bandwidth: 1_000_000)
        ]
        let matched = qualities.quality(matching: "1080p")

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.bandwidth, 2_500_000) // Falls back to highest
    }

    func testQualityMatching_unknownPreference_fallsBackToHighest() {
        let qualities = TestFixtures.makeQualities()
        let matched = qualities.quality(matching: "unknown")

        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.bandwidth, 5_000_000) // Falls back to highest
    }

    func testQualityMatching_emptyArray_returnsNil() {
        let qualities: [StreamQuality] = []

        XCTAssertNil(qualities.quality(matching: "highest"))
        XCTAssertNil(qualities.quality(matching: "lowest"))
        XCTAssertNil(qualities.quality(matching: "720p"))
    }

    // MARK: - estimatedFileSize Tests

    func testEstimatedFileSize_validBandwidth_returnsFormattedSize() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 5_000_000)
        let estimated = quality.estimatedFileSize

        // 5 Mbps = 625 KB/s, 5 minutes = 187.5 MB
        XCTAssertNotNil(estimated)
        XCTAssertTrue(estimated?.contains("MB") ?? false)
    }

    func testEstimatedFileSize_zeroBandwidth_returnsNil() {
        let quality = TestFixtures.makeStreamQuality(bandwidth: 0)
        XCTAssertNil(quality.estimatedFileSize)
    }
}
