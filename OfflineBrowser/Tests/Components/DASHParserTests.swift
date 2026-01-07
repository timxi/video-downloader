import XCTest
@testable import OfflineBrowser

final class DASHParserTests: XCTestCase {

    var parser: DASHParser!
    var mockSession: MockURLSession!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        parser = DASHParser(urlSession: mockSession)
    }

    override func tearDown() {
        parser = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - VOD Manifest Tests

    func testParseVODManifest_extractsQualities() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/video/manifest.mpd")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertEqual(info.qualities.count, 2)
                // Sorted by bandwidth descending
                XCTAssertEqual(info.qualities[0].resolution, "1080p")
                XCTAssertEqual(info.qualities[0].bandwidth, 5_000_000)
                XCTAssertEqual(info.qualities[1].resolution, "720p")
                XCTAssertEqual(info.qualities[1].bandwidth, 2_500_000)
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseVODManifest_extractsDuration() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // PT1H30M0S = 5400 seconds
                XCTAssertEqual(info.totalDuration, 5400)
                XCTAssertFalse(info.isLive)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseVODManifest_extractsCodecs() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertEqual(info.qualities[0].codecs, "avc1.640028")
                XCTAssertEqual(info.qualities[1].codecs, "avc1.64001f")
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseVODManifest_extractsMinBufferTime() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // PT2S = 2 seconds
                XCTAssertEqual(info.minBufferTime, 2.0)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Live Stream Tests

    func testParseLiveManifest_detectsLive() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashLiveManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertTrue(info.isLive)
                XCTAssertNil(info.totalDuration) // Live streams don't have fixed duration
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - DRM Detection Tests

    func testParseDRMManifest_detectsContentProtection() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashDRMManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertTrue(info.isDRMProtected)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseDRMManifest_extractsDuration() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashDRMManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // PT30M0S = 1800 seconds
                XCTAssertEqual(info.totalDuration, 1800)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Subtitle Detection Tests

    func testParseManifestWithSubtitles_detectsSubtitles() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashWithSubtitlesManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertTrue(info.hasSubtitles)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Audio Track Tests

    func testParseMultiAudioManifest_extractsAudioTracks() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashMultiAudioManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertNotNil(info.audioTracks)
                XCTAssertEqual(info.audioTracks?.count, 2)

                let languages = info.audioTracks?.compactMap { $0.language } ?? []
                XCTAssertTrue(languages.contains("en"))
                XCTAssertTrue(languages.contains("es"))

                let labels = info.audioTracks?.compactMap { $0.label } ?? []
                XCTAssertTrue(labels.contains("English"))
                XCTAssertTrue(labels.contains("Spanish"))
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - ISO 8601 Duration Tests

    func testParseISO8601Duration_hoursMinutesSeconds() {
        // PT2H15M30S = 2*3600 + 15*60 + 30 = 8130 seconds
        let duration = DASHParser.parseISO8601Duration("PT2H15M30S")
        XCTAssertEqual(duration, 8130)
    }

    func testParseISO8601Duration_fractionalSeconds() {
        // PT45.5S = 45.5 seconds
        let duration = DASHParser.parseISO8601Duration("PT45.5S")
        XCTAssertEqual(duration, 45.5)
    }

    func testParseISO8601Duration_hoursOnly() {
        // PT2H = 7200 seconds
        let duration = DASHParser.parseISO8601Duration("PT2H")
        XCTAssertEqual(duration, 7200)
    }

    func testParseISO8601Duration_minutesOnly() {
        // PT30M = 1800 seconds
        let duration = DASHParser.parseISO8601Duration("PT30M")
        XCTAssertEqual(duration, 1800)
    }

    func testParseISO8601Duration_secondsOnly() {
        // PT120S = 120 seconds
        let duration = DASHParser.parseISO8601Duration("PT120S")
        XCTAssertEqual(duration, 120)
    }

    func testParseISO8601Duration_complex() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashMinimalManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // PT2H15M30.5S = 2*3600 + 15*60 + 30.5 = 8130.5 seconds
                XCTAssertEqual(info.totalDuration, 8130.5)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseISO8601Duration_invalidFormat_returnsNil() {
        let duration = DASHParser.parseISO8601Duration("invalid")
        XCTAssertNil(duration)
    }

    func testParseISO8601Duration_empty_returnsNil() {
        let duration = DASHParser.parseISO8601Duration("")
        XCTAssertNil(duration)
    }

    // MARK: - URL Resolution Tests

    func testParseManifest_resolvesRelativeBaseURL() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://cdn.example.com/content/movie/manifest.mpd")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // URLs should contain the base path
                for quality in info.qualities {
                    XCTAssertTrue(quality.url.hasPrefix("https://cdn.example.com/content/movie/"))
                }
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - SegmentList Tests

    func testParseSegmentListManifest_extractsQualities() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashSegmentListManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertEqual(info.qualities.count, 1)
                XCTAssertEqual(info.qualities[0].resolution, "720p")
                // Duration from mediaPresentationDuration
                XCTAssertEqual(info.totalDuration, 600) // PT10M0S
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Error Handling Tests

    func testParseInvalidXML_returnsError() {
        let exp = expectation(description: "Parse completes")
        let invalidXML = "This is not XML at all"

        parser.parseManifest(content: invalidXML, baseURL: URL(string: "https://example.com/")!) { result in
            if case .failure(.invalidManifest) = result {
                // Expected - no MPD tag
            } else {
                XCTFail("Expected invalidManifest error, got: \(result)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseEmptyManifest_returnsError() {
        let exp = expectation(description: "Parse completes")

        parser.parseManifest(content: "", baseURL: URL(string: "https://example.com/")!) { result in
            if case .failure(.noContent) = result {
                // Expected
            } else {
                XCTFail("Expected noContent error, got: \(result)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseMalformedXML_returnsError() {
        let exp = expectation(description: "Parse completes")
        let malformedXML = """
            <?xml version="1.0"?>
            <MPD xmlns="urn:mpeg:dash:schema:mpd:2011">
              <Period>
                <AdaptationSet>
                  <Representation id="test" unclosed attribute
                </AdaptationSet>
            </MPD>
            """

        parser.parseManifest(content: malformedXML, baseURL: URL(string: "https://example.com/")!) { result in
            if case .failure(.xmlParsingError) = result {
                // Expected
            } else {
                XCTFail("Expected xmlParsingError, got: \(result)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Network Tests

    func testParseURL_fetchesAndParses() {
        let exp = expectation(description: "Parse completes")
        let url = URL(string: "https://example.com/video/manifest.mpd")!

        mockSession.dataResponseHandler = { request in
            let data = TestFixtures.dashVODManifest.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response, nil)
        }

        parser.parse(url: url) { result in
            if case .success(let info) = result {
                XCTAssertEqual(info.qualities.count, 2)
                XCTAssertEqual(info.totalDuration, 5400)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseURL_networkError_returnsError() {
        let exp = expectation(description: "Parse completes")
        let url = URL(string: "https://example.com/video/manifest.mpd")!

        mockSession.dataResponseHandler = { _ in
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            return (nil, nil, error)
        }

        parser.parse(url: url) { result in
            if case .failure(.networkError) = result {
                // Expected
            } else {
                XCTFail("Expected network error, got: \(result)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseURL_emptyResponse_returnsError() {
        let exp = expectation(description: "Parse completes")
        let url = URL(string: "https://example.com/video/manifest.mpd")!

        mockSession.dataResponseHandler = { request in
            let data = Data()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response, nil)
        }

        parser.parse(url: url) { result in
            if case .failure(.noContent) = result {
                // Expected
            } else {
                XCTFail("Expected noContent error, got: \(result)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Quality Sorting Tests

    func testParseManifest_sortsByBandwidthDescending() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // Should be sorted highest to lowest
                for i in 0..<(info.qualities.count - 1) {
                    XCTAssertGreaterThanOrEqual(
                        info.qualities[i].bandwidth,
                        info.qualities[i + 1].bandwidth,
                        "Qualities should be sorted by bandwidth descending"
                    )
                }
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Non-DRM Manifest Tests

    func testParseVODManifest_noDRM() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertFalse(info.isDRMProtected)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testParseVODManifest_noSubtitles() {
        let exp = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertFalse(info.hasSubtitles)
            } else {
                XCTFail("Expected success")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }
}
