import XCTest
@testable import OfflineBrowser

final class HLSParserTests: XCTestCase {

    var sut: HLSParser!
    var mockURLSession: MockURLSession!
    let baseURL = URL(string: "https://example.com/stream/manifest.m3u8")!

    override func setUp() {
        super.setUp()
        mockURLSession = MockURLSession()
        sut = HLSParser(urlSession: mockURLSession)
    }

    override func tearDown() {
        sut = nil
        mockURLSession = nil
        super.tearDown()
    }

    // MARK: - Master Playlist Tests

    func testParseMasterPlaylist_extractsQualities() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.masterPlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertEqual(info.qualities.count, 2)
                XCTAssertFalse(info.isLive)
                XCTAssertFalse(info.isDRMProtected)

                // Check first quality (1080p)
                let quality1080 = info.qualities.first { $0.resolution == "1080p" }
                XCTAssertNotNil(quality1080)
                XCTAssertEqual(quality1080?.bandwidth, 5_000_000)
                XCTAssertTrue(quality1080?.url.hasSuffix("1080p.m3u8") ?? false)

                // Check second quality (720p)
                let quality720 = info.qualities.first { $0.resolution == "720p" }
                XCTAssertNotNil(quality720)
                XCTAssertEqual(quality720?.bandwidth, 2_500_000)

            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseMasterPlaylist_detectsSubtitles() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.masterPlaylistWithSubtitles, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertTrue(info.hasSubtitles)
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseMasterPlaylist_detectsDRM() {
        let drmPlaylist = """
            #EXTM3U
            #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://license"
            #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
            1080p.m3u8
            """
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: drmPlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertTrue(info.isDRMProtected)
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Media Playlist Tests

    func testParseMediaPlaylist_extractsSegments() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.mediaPlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertEqual(info.segments?.count, 3)
                XCTAssertFalse(info.isLive)

                // Check segment durations
                XCTAssertEqual(info.segments?[0].duration, 10.0)
                XCTAssertEqual(info.segments?[1].duration, 10.0)
                XCTAssertEqual(info.segments?[2].duration, 8.5)

                // Check segment indices
                XCTAssertEqual(info.segments?[0].index, 0)
                XCTAssertEqual(info.segments?[1].index, 1)
                XCTAssertEqual(info.segments?[2].index, 2)

            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseMediaPlaylist_calculatesTotalDuration() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.mediaPlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertNotNil(info.totalDuration)
                XCTAssertEqual(info.totalDuration ?? 0, 28.5, accuracy: 0.01)
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseMediaPlaylist_detectsLiveStream() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.livePlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertTrue(info.isLive)
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseMediaPlaylist_detectsAES128Encryption() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.encryptedPlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertNotNil(info.encryptionKeyURL)
                XCTAssertTrue(info.encryptionKeyURL?.hasSuffix("key.bin") ?? false)
                XCTAssertFalse(info.isDRMProtected) // AES-128 is not DRM
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseMediaPlaylist_detectsDRM() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.drmProtectedPlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertTrue(info.isDRMProtected)
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - fMP4/CMAF Tests

    func testParseMediaPlaylist_detectsFMP4Format() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.fmp4Playlist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertTrue(info.isFMP4)
                XCTAssertNotNil(info.initSegmentURL)
                XCTAssertTrue(info.initSegmentURL?.hasSuffix("init.mp4") ?? false)
                XCTAssertEqual(info.segments?.count, 3)
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - URL Resolution Tests

    func testResolveURL_withAbsoluteURL_returnsAsIs() {
        let absoluteURL = "https://cdn.example.com/segment.ts"
        let resolved = sut.resolveURL(absoluteURL, baseURL: baseURL)
        XCTAssertEqual(resolved, absoluteURL)
    }

    func testResolveURL_withRelativePath_resolvesCorrectly() {
        let relativePath = "segment.ts"
        let resolved = sut.resolveURL(relativePath, baseURL: baseURL)
        XCTAssertEqual(resolved, "https://example.com/stream/segment.ts")
    }

    func testResolveURL_withAbsolutePath_resolvesFromRoot() {
        let absolutePath = "/videos/segment.ts"
        let resolved = sut.resolveURL(absolutePath, baseURL: baseURL)
        XCTAssertEqual(resolved, "https://example.com/videos/segment.ts")
    }

    func testResolveURL_preservesQueryParameters() {
        let pathWithQuery = "segment.ts?token=abc123"
        let resolved = sut.resolveURL(pathWithQuery, baseURL: baseURL)
        XCTAssertTrue(resolved.contains("token=abc123"))
    }

    func testResolveURL_stripsFragmentFromBase() {
        let baseWithFragment = URL(string: "https://example.com/stream/manifest.m3u8#hash")!
        let resolved = sut.resolveURL("segment.ts", baseURL: baseWithFragment)
        XCTAssertFalse(resolved.contains("#hash"))
    }

    // MARK: - Format Resolution Tests

    func testFormatResolution_with1920x1080_returns1080p() {
        let result = sut.formatResolution("1920x1080")
        XCTAssertEqual(result, "1080p")
    }

    func testFormatResolution_with1280x720_returns720p() {
        let result = sut.formatResolution("1280x720")
        XCTAssertEqual(result, "720p")
    }

    func testFormatResolution_withNil_returnsUnknown() {
        let result = sut.formatResolution(nil)
        XCTAssertEqual(result, "Unknown")
    }

    func testFormatResolution_withInvalidFormat_returnsOriginal() {
        let result = sut.formatResolution("invalid")
        XCTAssertEqual(result, "invalid")
    }

    // MARK: - Attribute Extraction Tests

    func testExtractAttribute_extractsBandwidth() {
        let line = "#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080"
        let bandwidth = sut.extractAttribute(from: line, key: "BANDWIDTH")
        XCTAssertEqual(bandwidth, "5000000")
    }

    func testExtractAttribute_extractsResolution() {
        let line = "#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080"
        let resolution = sut.extractAttribute(from: line, key: "RESOLUTION")
        XCTAssertEqual(resolution, "1920x1080")
    }

    func testExtractAttribute_extractsQuotedURI() {
        let line = "#EXT-X-KEY:METHOD=AES-128,URI=\"https://example.com/key.bin\""
        let uri = sut.extractAttribute(from: line, key: "URI")
        XCTAssertEqual(uri, "https://example.com/key.bin")
    }

    func testExtractAttribute_returnsNilForMissingKey() {
        let line = "#EXT-X-STREAM-INF:BANDWIDTH=5000000"
        let resolution = sut.extractAttribute(from: line, key: "RESOLUTION")
        XCTAssertNil(resolution)
    }

    // MARK: - Error Handling Tests

    func testParseManifest_withInvalidContent_returnsError() {
        let invalidContent = "This is not a valid HLS manifest"
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: invalidContent, baseURL: baseURL) { result in
            switch result {
            case .success:
                XCTFail("Parse should fail for invalid content")
            case .failure(let error):
                if case .invalidManifest = error {
                    // Expected error type
                } else {
                    XCTFail("Expected invalidManifest error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseURL_withNetworkError_returnsError() {
        let networkError = NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockURLSession.dataResponse = (nil, nil, networkError)

        let expectation = expectation(description: "Parse completes")

        sut.parse(url: baseURL) { result in
            switch result {
            case .success:
                XCTFail("Parse should fail with network error")
            case .failure(let error):
                if case .networkError = error {
                    // Expected
                } else {
                    XCTFail("Expected network error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseURL_withEmptyResponse_returnsNoContentError() {
        mockURLSession.dataResponse = (nil, nil, nil)

        let expectation = expectation(description: "Parse completes")

        sut.parse(url: baseURL) { result in
            switch result {
            case .success:
                XCTFail("Parse should fail with no content")
            case .failure(let error):
                if case .noContent = error {
                    // Expected error type
                } else {
                    XCTFail("Expected noContent error, got \(error)")
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Absolute URL Playlist Tests

    func testParseMediaPlaylist_withAbsoluteURLs_preservesURLs() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.absoluteURLPlaylist, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertEqual(info.segments?.count, 2)
                XCTAssertEqual(info.segments?[0].url, "https://cdn.example.com/segment_0.ts")
                XCTAssertEqual(info.segments?[1].url, "https://cdn.example.com/segment_1.ts")
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - BYTERANGE Tests (YouTube fMP4)

    func testParseMediaPlaylist_extractsByteRangeFromInitSegment() {
        let expectation = expectation(description: "Parse completes")

        sut.parseManifest(content: TestFixtures.fmp4PlaylistWithByteRange, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertTrue(info.isFMP4)
                XCTAssertNotNil(info.initSegmentURL)
                XCTAssertTrue(info.initSegmentURL?.hasSuffix("video.mp4") ?? false)
                XCTAssertEqual(info.initSegmentByteRange, "1234@0")
            case .failure(let error):
                XCTFail("Parse should succeed: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testExtractAttribute_extractsByteRange() {
        let line = "#EXT-X-MAP:URI=\"init.mp4\",BYTERANGE=\"5678@100\""
        let byterange = sut.extractAttribute(from: line, key: "BYTERANGE")
        XCTAssertEqual(byterange, "5678@100")
    }
}
