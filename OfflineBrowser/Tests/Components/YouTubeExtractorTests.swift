import XCTest
@testable import OfflineBrowser

final class YouTubeExtractorTests: XCTestCase {

    var sut: YouTubeExtractor!

    override func setUp() {
        super.setUp()
        sut = YouTubeExtractor()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - canExtract Tests

    func testCanExtract_withStandardWatchURL_returnsTrue() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertTrue(sut.canExtract(url: url))
    }

    func testCanExtract_withMobileWatchURL_returnsTrue() {
        let url = URL(string: "https://m.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertTrue(sut.canExtract(url: url))
    }

    func testCanExtract_withShortURL_returnsTrue() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertTrue(sut.canExtract(url: url))
    }

    func testCanExtract_withShortsURL_returnsTrue() {
        let url = URL(string: "https://www.youtube.com/shorts/abc123xyz")!
        XCTAssertTrue(sut.canExtract(url: url))
    }

    func testCanExtract_withEmbedURL_returnsTrue() {
        let url = URL(string: "https://www.youtube.com/embed/dQw4w9WgXcQ")!
        XCTAssertTrue(sut.canExtract(url: url))
    }

    func testCanExtract_withNoCookieEmbedURL_returnsTrue() {
        let url = URL(string: "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")!
        XCTAssertTrue(sut.canExtract(url: url))
    }

    func testCanExtract_withOldStyleURL_returnsTrue() {
        let url = URL(string: "https://www.youtube.com/v/dQw4w9WgXcQ")!
        XCTAssertTrue(sut.canExtract(url: url))
    }

    func testCanExtract_withNonYouTubeURL_returnsFalse() {
        let url = URL(string: "https://vimeo.com/123456")!
        XCTAssertFalse(sut.canExtract(url: url))
    }

    func testCanExtract_withYouTubeHomepage_returnsFalse() {
        let url = URL(string: "https://www.youtube.com/")!
        XCTAssertFalse(sut.canExtract(url: url))
    }

    func testCanExtract_withYouTubeChannelPage_returnsFalse() {
        let url = URL(string: "https://www.youtube.com/channel/UC123")!
        XCTAssertFalse(sut.canExtract(url: url))
    }

    // MARK: - extractVideoId Tests

    func testExtractVideoId_fromStandardWatchURL_returnsVideoId() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertEqual(sut.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoId_fromWatchURLWithExtraParams_returnsVideoId() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120&list=PLxyz")!
        XCTAssertEqual(sut.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoId_fromShortURL_returnsVideoId() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertEqual(sut.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoId_fromShortURLWithParams_returnsVideoId() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ?t=120")!
        XCTAssertEqual(sut.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoId_fromShortsURL_returnsVideoId() {
        let url = URL(string: "https://www.youtube.com/shorts/abc123xyz")!
        XCTAssertEqual(sut.extractVideoId(from: url), "abc123xyz")
    }

    func testExtractVideoId_fromShortsURLWithParams_returnsVideoId() {
        let url = URL(string: "https://www.youtube.com/shorts/abc123xyz?feature=share")!
        XCTAssertEqual(sut.extractVideoId(from: url), "abc123xyz")
    }

    func testExtractVideoId_fromEmbedURL_returnsVideoId() {
        let url = URL(string: "https://www.youtube.com/embed/dQw4w9WgXcQ")!
        XCTAssertEqual(sut.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoId_fromEmbedURLWithParams_returnsVideoId() {
        let url = URL(string: "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1")!
        XCTAssertEqual(sut.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoId_fromOldStyleURL_returnsVideoId() {
        let url = URL(string: "https://www.youtube.com/v/dQw4w9WgXcQ")!
        XCTAssertEqual(sut.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoId_fromNonYouTubeURL_returnsNil() {
        let url = URL(string: "https://vimeo.com/123456")!
        XCTAssertNil(sut.extractVideoId(from: url))
    }

    // MARK: - extractQualityFromURL Tests (Static Method)
    // YouTube uses path-based itag format: /itag/312/

    func testExtractQualityFromURL_with1080p60Itag_returns1080p60() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/312/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "1080p60")
    }

    func testExtractQualityFromURL_with720pItag_returns720p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/136/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "720p")
    }

    func testExtractQualityFromURL_with720p60Itag_returns720p60() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/302/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "720p60")
    }

    func testExtractQualityFromURL_with480pItag_returns480p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/135/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "480p")
    }

    func testExtractQualityFromURL_with360pItag_returns360p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/134/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "360p")
    }

    func testExtractQualityFromURL_with1440p60Itag_returns1440p60() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/308/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "1440p60")
    }

    func testExtractQualityFromURL_with2160p60Itag_returns2160p60() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/315/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "2160p60")
    }

    func testExtractQualityFromURL_withQueryParamItag22_returns720p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback?itag=22&source=youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "720p")
    }

    func testExtractQualityFromURL_withQueryParamItag18_returns360p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback?itag=18&source=youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "360p")
    }

    func testExtractQualityFromURL_withUnknownItag_returnsNil() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/999/source/youtube"
        XCTAssertNil(YouTubeExtractor.extractQualityFromURL(url))
    }

    func testExtractQualityFromURL_withNoItag_returnsNil() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/source/youtube"
        XCTAssertNil(YouTubeExtractor.extractQualityFromURL(url))
    }

    func testExtractQualityFromURL_withNonYouTubeURL_returnsNil() {
        let url = "https://example.com/video.mp4"
        XCTAssertNil(YouTubeExtractor.extractQualityFromURL(url))
    }

    // MARK: - AV1 Codec Itag Tests

    func testExtractQualityFromURL_withAV11080pItag_returns1080p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/399/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "1080p")
    }

    func testExtractQualityFromURL_withAV1720pItag_returns720p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/398/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "720p")
    }

    // MARK: - VP9 Codec Itag Tests

    func testExtractQualityFromURL_withVP91080pItag_returns1080p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/248/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "1080p")
    }

    func testExtractQualityFromURL_withVP9720pItag_returns720p() {
        let url = "https://rr1---sn-xxx.googlevideo.com/videoplayback/itag/247/source/youtube"
        XCTAssertEqual(YouTubeExtractor.extractQualityFromURL(url), "720p")
    }
}
