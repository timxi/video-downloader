# DASH Parser Implementation Plan

## Overview

Implement MPEG-DASH (MPD) manifest parsing to complete Phase 3: Detection. This follows the existing HLSParser architecture patterns for consistency and testability.

**References:**
- [Structure of an MPEG-DASH MPD - OTTVerse](https://ottverse.com/structure-of-an-mpeg-dash-mpd/)
- [DASH basics - GPAC](https://wiki.gpac.io/Howtos/dash/DASH-basics/)
- [DASH-IF Content Protection Identifiers](https://dashif.org/identifiers/content_protection/)

---

## Phase 1: Data Structures

### 1.1 Create `DASHParsedInfo` struct

**File:** `OfflineBrowser/Features/Browser/Detection/DASHParser.swift`

```swift
struct DASHParsedInfo {
    var qualities: [StreamQuality]           // Video representations as quality variants
    var isLive: Bool                         // MPD@type == "dynamic"
    var isDRMProtected: Bool                 // ContentProtection elements detected
    var hasSubtitles: Bool                   // AdaptationSet with subtitles/text
    var totalDuration: TimeInterval?         // MPD@mediaPresentationDuration
    var audioTracks: [DASHAudioTrack]?       // Audio adaptation sets
    var minBufferTime: TimeInterval?         // MPD@minBufferTime
}
```

### 1.2 Create `DASHAudioTrack` struct

```swift
struct DASHAudioTrack: Identifiable, Equatable {
    let id: UUID
    let language: String?                    // AdaptationSet@lang
    let label: String?                       // AdaptationSet@label or Label element
    let codecs: String?                      // Representation@codecs
    let bandwidth: Int                       // Representation@bandwidth
}
```

### 1.3 Create `DASHSegmentInfo` struct (internal use)

```swift
struct DASHSegmentInfo {
    let initializationURL: String?           // SegmentTemplate@initialization or SegmentBase
    let mediaTemplate: String?               // SegmentTemplate@media
    let segmentURLs: [String]?               // SegmentList/SegmentURL
    let timescale: Int                       // SegmentTemplate@timescale (default 1)
    let duration: Int?                       // SegmentTemplate@duration
    let startNumber: Int                     // SegmentTemplate@startNumber (default 1)
}
```

---

## Phase 2: DASHParser Implementation

### 2.1 Core Parser Class

**File:** `OfflineBrowser/Features/Browser/Detection/DASHParser.swift`

```swift
final class DASHParser {

    enum ParseError: Error {
        case invalidURL
        case networkError(Error)
        case invalidManifest
        case noContent
        case xmlParsingError(Error)
    }

    private let urlSession: URLSessionProtocol

    init(urlSession: URLSessionProtocol = URLSession.shared) {
        self.urlSession = urlSession
    }

    // Primary entry point
    func parse(url: URL, completion: @escaping (Result<DASHParsedInfo, ParseError>) -> Void)

    // For testing with raw content
    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<DASHParsedInfo, ParseError>) -> Void)
}
```

### 2.2 XML Parsing Strategy

Use `XMLParser` (Foundation) with delegate pattern:

```swift
private class MPDParserDelegate: NSObject, XMLParserDelegate {
    var result = DASHParsedInfo(qualities: [], isLive: false, isDRMProtected: false, hasSubtitles: false)
    var currentElement = ""
    var currentAdaptationSet: AdaptationSetContext?
    var currentRepresentation: RepresentationContext?
    var baseURL: URL

    // Track parsing context
    struct AdaptationSetContext {
        var contentType: String?        // "video", "audio", "text"
        var mimeType: String?           // "video/mp4", "audio/mp4"
        var lang: String?
        var representations: [RepresentationContext] = []
        var hasContentProtection: Bool = false
        var segmentTemplate: SegmentTemplateContext?
    }

    struct RepresentationContext {
        var id: String?
        var bandwidth: Int = 0
        var width: Int?
        var height: Int?
        var codecs: String?
        var baseURL: String?
    }

    struct SegmentTemplateContext {
        var initialization: String?
        var media: String?
        var timescale: Int = 1
        var duration: Int?
        var startNumber: Int = 1
    }
}
```

### 2.3 Key Parsing Methods

#### MPD Root Element
```swift
func parser(_ parser: XMLParser, didStartElement elementName: String, ..., attributes: [String: String]) {
    switch elementName {
    case "MPD":
        // type="static" (VOD) or "dynamic" (live)
        result.isLive = attributes["type"] == "dynamic"

        // mediaPresentationDuration="PT1H30M45.5S"
        if let duration = attributes["mediaPresentationDuration"] {
            result.totalDuration = parseISO8601Duration(duration)
        }

    case "AdaptationSet":
        currentAdaptationSet = AdaptationSetContext()
        currentAdaptationSet?.contentType = attributes["contentType"]
        currentAdaptationSet?.mimeType = attributes["mimeType"]
        currentAdaptationSet?.lang = attributes["lang"]

        // Check for subtitles
        if attributes["contentType"] == "text" ||
           attributes["mimeType"]?.contains("text") == true {
            result.hasSubtitles = true
        }

    case "ContentProtection":
        // Any ContentProtection = DRM protected
        currentAdaptationSet?.hasContentProtection = true
        result.isDRMProtected = true

    case "Representation":
        currentRepresentation = RepresentationContext()
        currentRepresentation?.id = attributes["id"]
        currentRepresentation?.bandwidth = Int(attributes["bandwidth"] ?? "0") ?? 0
        currentRepresentation?.width = Int(attributes["width"] ?? "")
        currentRepresentation?.height = Int(attributes["height"] ?? "")
        currentRepresentation?.codecs = attributes["codecs"]

    case "SegmentTemplate":
        let template = SegmentTemplateContext(
            initialization: attributes["initialization"],
            media: attributes["media"],
            timescale: Int(attributes["timescale"] ?? "1") ?? 1,
            duration: Int(attributes["duration"] ?? ""),
            startNumber: Int(attributes["startNumber"] ?? "1") ?? 1
        )
        // Can be at AdaptationSet or Representation level
        currentAdaptationSet?.segmentTemplate = template

    case "BaseURL":
        // Will be handled in didEndElement with character data
        break
    }
}
```

#### ISO 8601 Duration Parser
```swift
// Parse "PT1H30M45.5S" -> 5445.5 seconds
private func parseISO8601Duration(_ duration: String) -> TimeInterval? {
    // Pattern: PT[nH][nM][n.nS]
    var total: TimeInterval = 0
    let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?"#

    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: duration, range: NSRange(duration.startIndex..., in: duration)) else {
        return nil
    }

    if let hoursRange = Range(match.range(at: 1), in: duration),
       let hours = Double(duration[hoursRange]) {
        total += hours * 3600
    }
    if let minutesRange = Range(match.range(at: 2), in: duration),
       let minutes = Double(duration[minutesRange]) {
        total += minutes * 60
    }
    if let secondsRange = Range(match.range(at: 3), in: duration),
       let seconds = Double(duration[secondsRange]) {
        total += seconds
    }

    return total > 0 ? total : nil
}
```

#### Building Quality Variants
```swift
func parserDidEndDocument(_ parser: XMLParser) {
    // Convert video AdaptationSets to StreamQuality array
    for adaptationSet in videoAdaptationSets {
        for rep in adaptationSet.representations {
            let resolution = formatResolution(width: rep.width, height: rep.height)

            // Build segment URL from template or base URL
            let url = buildRepresentationURL(rep, template: adaptationSet.segmentTemplate)

            let quality = StreamQuality(
                id: UUID(),
                resolution: resolution,
                bandwidth: rep.bandwidth,
                url: url,
                codecs: rep.codecs
            )
            result.qualities.append(quality)
        }
    }

    // Sort by bandwidth descending
    result.qualities.sort { $0.bandwidth > $1.bandwidth }
}
```

### 2.4 URL Resolution for Segments

```swift
// SegmentTemplate variables: $RepresentationID$, $Number$, $Time$, $Bandwidth$
private func resolveTemplateURL(_ template: String, representationID: String, bandwidth: Int, baseURL: URL) -> String {
    var url = template
    url = url.replacingOccurrences(of: "$RepresentationID$", with: representationID)
    url = url.replacingOccurrences(of: "$Bandwidth$", with: String(bandwidth))
    // $Number$ and $Time$ are runtime values, use first segment for detection
    url = url.replacingOccurrences(of: "$Number$", with: "1")
    url = url.replacingOccurrences(of: "$Time$", with: "0")

    // Resolve relative URLs
    if url.hasPrefix("http://") || url.hasPrefix("https://") {
        return url
    } else if url.hasPrefix("/") {
        return baseURL.scheme! + "://" + baseURL.host! + url
    } else {
        return baseURL.deletingLastPathComponent().appendingPathComponent(url).absoluteString
    }
}
```

---

## Phase 3: Protocol & Dependency Injection

### 3.1 Create DASHParserProtocol

**File:** `OfflineBrowser/Core/Protocols/DASHParserProtocol.swift`

```swift
protocol DASHParserProtocol {
    func parse(url: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void)
    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void)
}

extension DASHParser: DASHParserProtocol {}
```

---

## Phase 4: StreamDetector Integration

### 4.1 Add DASHParser to StreamDetector

**File:** `OfflineBrowser/Features/Browser/Detection/StreamDetector.swift`

```swift
final class StreamDetector: ObservableObject {
    // Existing
    private let hlsParser = HLSParser()

    // Add
    private let dashParser = DASHParser()

    func addStream(url: String, type: StreamType) {
        // ... existing duplicate checks ...

        switch type {
        case .hls:
            parseHLSManifest(url: url, stream: stream)
        case .dash:
            // NEW: Parse DASH manifests
            parseDASHManifest(url: url, stream: stream)
        case .direct, .unknown:
            appendStream(stream)
        }
    }

    // NEW METHOD
    private func parseDASHManifest(url: String, stream: DetectedStream) {
        guard let manifestURL = URL(string: url) else {
            NSLog("[StreamDetector] Invalid DASH URL: %@", url)
            processingURLs.remove(url)
            return
        }

        dashParser.parse(url: manifestURL) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.processingURLs.remove(url)

                switch result {
                case .success(let info):
                    var updatedStream = stream
                    updatedStream.qualities = info.qualities
                    updatedStream.isLive = info.isLive
                    updatedStream.isDRMProtected = info.isDRMProtected
                    updatedStream.hasSubtitles = info.hasSubtitles
                    updatedStream.duration = info.totalDuration

                    // Apply same filtering as HLS
                    if info.isDRMProtected {
                        NSLog("[StreamDetector] Skipping DRM-protected DASH stream")
                        return
                    }

                    if info.isLive {
                        NSLog("[StreamDetector] Skipping live DASH stream")
                        return
                    }

                    // Duration-based deduplication
                    if let duration = info.totalDuration {
                        if duration < self.minimumDurationForMainContent {
                            NSLog("[StreamDetector] Skipping short DASH stream: %.1fs", duration)
                            return
                        }

                        if let existingIndex = self.findStreamWithSimilarDuration(duration) {
                            self.mergeAsQualityVariant(newStream: updatedStream, existingIndex: existingIndex)
                            return
                        }
                    }

                    self.appendStream(updatedStream)

                case .failure(let error):
                    NSLog("[StreamDetector] DASH parse error: %@", String(describing: error))
                }
            }
        }
    }
}
```

---

## Phase 5: Testing Infrastructure

### 5.1 Create MockDASHParser

**File:** `OfflineBrowser/Tests/Mocks/MockDASHParser.swift`

```swift
@testable import OfflineBrowser

final class MockDASHParser: DASHParserProtocol {

    // MARK: - Call Tracking
    private(set) var parseURLCalls: [URL] = []
    private(set) var parseManifestCalls: [(content: String, baseURL: URL)] = []

    // MARK: - Configurable Responses
    var parseURLHandler: ((URL) -> Result<DASHParsedInfo, DASHParser.ParseError>)?
    var parseManifestHandler: ((String, URL) -> Result<DASHParsedInfo, DASHParser.ParseError>)?

    // MARK: - DASHParserProtocol

    func parse(url: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void) {
        parseURLCalls.append(url)

        if let handler = parseURLHandler {
            completion(handler(url))
        } else {
            completion(.success(Self.makeDefaultInfo()))
        }
    }

    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<DASHParsedInfo, DASHParser.ParseError>) -> Void) {
        parseManifestCalls.append((content, baseURL))

        if let handler = parseManifestHandler {
            completion(handler(content, baseURL))
        } else {
            completion(.success(Self.makeDefaultInfo()))
        }
    }

    // MARK: - Factory Methods

    static func makeDefaultInfo() -> DASHParsedInfo {
        DASHParsedInfo(
            qualities: [
                StreamQuality(id: UUID(), resolution: "1080p", bandwidth: 5_000_000, url: "https://example.com/video/1080p/init.mp4", codecs: "avc1.640028"),
                StreamQuality(id: UUID(), resolution: "720p", bandwidth: 2_500_000, url: "https://example.com/video/720p/init.mp4", codecs: "avc1.64001f")
            ],
            isLive: false,
            isDRMProtected: false,
            hasSubtitles: false,
            totalDuration: 3600,
            audioTracks: nil,
            minBufferTime: 2.0
        )
    }

    static func makeDRMProtectedInfo() -> DASHParsedInfo {
        var info = makeDefaultInfo()
        info.isDRMProtected = true
        return info
    }

    static func makeLiveInfo() -> DASHParsedInfo {
        var info = makeDefaultInfo()
        info.isLive = true
        info.totalDuration = nil
        return info
    }

    // MARK: - Helpers

    func reset() {
        parseURLCalls.removeAll()
        parseManifestCalls.removeAll()
        parseURLHandler = nil
        parseManifestHandler = nil
    }
}
```

### 5.2 Add DASH Test Fixtures

**File:** `OfflineBrowser/Tests/Helpers/TestFixtures.swift` (additions)

```swift
extension TestFixtures {

    // MARK: - DASH Manifests

    /// Basic VOD MPD with two video qualities
    static let dashVODManifest = """
    <?xml version="1.0" encoding="UTF-8"?>
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
         type="static"
         mediaPresentationDuration="PT1H30M0S"
         minBufferTime="PT2S">
      <Period>
        <AdaptationSet contentType="video" mimeType="video/mp4">
          <Representation id="1080p" bandwidth="5000000" width="1920" height="1080" codecs="avc1.640028">
            <BaseURL>video/1080p/</BaseURL>
            <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s" startNumber="1" duration="4" timescale="1"/>
          </Representation>
          <Representation id="720p" bandwidth="2500000" width="1280" height="720" codecs="avc1.64001f">
            <BaseURL>video/720p/</BaseURL>
            <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s" startNumber="1" duration="4" timescale="1"/>
          </Representation>
        </AdaptationSet>
        <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="en">
          <Representation id="audio-en" bandwidth="128000" codecs="mp4a.40.2">
            <BaseURL>audio/en/</BaseURL>
            <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s" startNumber="1" duration="4" timescale="1"/>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>
    """

    /// Live DASH manifest (dynamic type)
    static let dashLiveManifest = """
    <?xml version="1.0" encoding="UTF-8"?>
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
         type="dynamic"
         availabilityStartTime="2024-01-01T00:00:00Z"
         minimumUpdatePeriod="PT5S"
         minBufferTime="PT2S">
      <Period start="PT0S">
        <AdaptationSet contentType="video" mimeType="video/mp4">
          <Representation id="720p" bandwidth="2500000" width="1280" height="720">
            <SegmentTemplate media="chunk-$Time$.m4s" timescale="90000"/>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>
    """

    /// DRM-protected DASH manifest with Widevine
    static let dashDRMManifest = """
    <?xml version="1.0" encoding="UTF-8"?>
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
         xmlns:cenc="urn:mpeg:cenc:2013"
         type="static"
         mediaPresentationDuration="PT30M0S">
      <Period>
        <AdaptationSet contentType="video" mimeType="video/mp4">
          <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc"/>
          <ContentProtection schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed">
            <cenc:pssh>AAAANHBzc2gAAAAA7e+LqXnWSs6jyCfc1R0h7QAAABQIARIQ...</cenc:pssh>
          </ContentProtection>
          <Representation id="1080p" bandwidth="5000000" width="1920" height="1080">
            <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s"/>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>
    """

    /// DASH with subtitles
    static let dashWithSubtitlesManifest = """
    <?xml version="1.0" encoding="UTF-8"?>
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT1H0M0S">
      <Period>
        <AdaptationSet contentType="video" mimeType="video/mp4">
          <Representation id="720p" bandwidth="2500000" width="1280" height="720"/>
        </AdaptationSet>
        <AdaptationSet contentType="text" mimeType="application/ttml+xml" lang="en">
          <Representation id="sub-en" bandwidth="1000">
            <BaseURL>subtitles/en.ttml</BaseURL>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>
    """

    /// DASH with SegmentList instead of SegmentTemplate
    static let dashSegmentListManifest = """
    <?xml version="1.0" encoding="UTF-8"?>
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT10M0S">
      <Period>
        <AdaptationSet contentType="video" mimeType="video/mp4">
          <Representation id="720p" bandwidth="2500000" width="1280" height="720">
            <SegmentList duration="4">
              <Initialization sourceURL="init.mp4"/>
              <SegmentURL media="segment1.m4s"/>
              <SegmentURL media="segment2.m4s"/>
              <SegmentURL media="segment3.m4s"/>
            </SegmentList>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>
    """

    // MARK: - DASH Factory Methods

    static func makeDASHQualities() -> [StreamQuality] {
        [
            StreamQuality(id: UUID(), resolution: "1080p", bandwidth: 5_000_000, url: "https://example.com/video/1080p/init.mp4", codecs: "avc1.640028"),
            StreamQuality(id: UUID(), resolution: "720p", bandwidth: 2_500_000, url: "https://example.com/video/720p/init.mp4", codecs: "avc1.64001f"),
            StreamQuality(id: UUID(), resolution: "480p", bandwidth: 1_500_000, url: "https://example.com/video/480p/init.mp4", codecs: "avc1.64001e"),
            StreamQuality(id: UUID(), resolution: "360p", bandwidth: 800_000, url: "https://example.com/video/360p/init.mp4", codecs: "avc1.640015")
        ]
    }
}
```

### 5.3 Create DASHParserTests

**File:** `OfflineBrowser/Tests/Components/DASHParserTests.swift`

```swift
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

    // MARK: - VOD Manifest Tests

    func testParseVODManifest_extractsQualities() {
        let expectation = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/video/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            switch result {
            case .success(let info):
                XCTAssertEqual(info.qualities.count, 2)
                XCTAssertEqual(info.qualities[0].resolution, "1080p")
                XCTAssertEqual(info.qualities[0].bandwidth, 5_000_000)
                XCTAssertEqual(info.qualities[1].resolution, "720p")
                XCTAssertEqual(info.qualities[1].bandwidth, 2_500_000)
            case .failure(let error):
                XCTFail("Unexpected error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseVODManifest_extractsDuration() {
        let expectation = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // PT1H30M0S = 5400 seconds
                XCTAssertEqual(info.totalDuration, 5400)
                XCTAssertFalse(info.isLive)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Live Stream Tests

    func testParseLiveManifest_detectsLive() {
        let expectation = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashLiveManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertTrue(info.isLive)
                XCTAssertNil(info.totalDuration)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - DRM Detection Tests

    func testParseDRMManifest_detectsContentProtection() {
        let expectation = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashDRMManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertTrue(info.isDRMProtected)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Subtitle Detection Tests

    func testParseManifestWithSubtitles_detectsSubtitles() {
        let expectation = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashWithSubtitlesManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertTrue(info.hasSubtitles)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - ISO 8601 Duration Tests

    func testParseISO8601Duration_hoursMinutesSeconds() {
        // Test via manifest parsing
        let manifest = """
        <?xml version="1.0"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT2H15M30S"/>
        """
        let expectation = expectation(description: "Parse completes")

        parser.parseManifest(content: manifest, baseURL: URL(string: "https://example.com/")!) { result in
            if case .success(let info) = result {
                // 2*3600 + 15*60 + 30 = 8130 seconds
                XCTAssertEqual(info.totalDuration, 8130)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseISO8601Duration_fractionalSeconds() {
        let manifest = """
        <?xml version="1.0"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT45.5S"/>
        """
        let expectation = expectation(description: "Parse completes")

        parser.parseManifest(content: manifest, baseURL: URL(string: "https://example.com/")!) { result in
            if case .success(let info) = result {
                XCTAssertEqual(info.totalDuration, 45.5)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - URL Resolution Tests

    func testSegmentTemplateURL_resolvesRelative() {
        // Test that relative segment template URLs are resolved correctly
        let expectation = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://cdn.example.com/content/movie/manifest.mpd")!

        parser.parseManifest(content: TestFixtures.dashVODManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                // URLs should be resolved relative to manifest location
                XCTAssertTrue(info.qualities[0].url.hasPrefix("https://cdn.example.com/content/movie/"))
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - SegmentList Tests

    func testParseSegmentList_extractsSegmentURLs() {
        let expectation = expectation(description: "Parse completes")
        let baseURL = URL(string: "https://example.com/")!

        parser.parseManifest(content: TestFixtures.dashSegmentListManifest, baseURL: baseURL) { result in
            if case .success(let info) = result {
                XCTAssertEqual(info.qualities.count, 1)
                // Duration should be calculated from SegmentList duration * segment count
                // or from mediaPresentationDuration
                XCTAssertEqual(info.totalDuration, 600) // PT10M0S
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Error Handling Tests

    func testParseInvalidXML_returnsError() {
        let expectation = expectation(description: "Parse completes")
        let invalidXML = "This is not XML at all"

        parser.parseManifest(content: invalidXML, baseURL: URL(string: "https://example.com/")!) { result in
            if case .failure(let error) = result {
                switch error {
                case .xmlParsingError, .invalidManifest:
                    break // Expected
                default:
                    XCTFail("Wrong error type: \(error)")
                }
            } else {
                XCTFail("Expected failure")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseEmptyManifest_returnsError() {
        let expectation = expectation(description: "Parse completes")

        parser.parseManifest(content: "", baseURL: URL(string: "https://example.com/")!) { result in
            if case .failure(.noContent) = result {
                // Expected
            } else {
                XCTFail("Expected noContent error")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Network Tests

    func testParseURL_fetchesAndParses() {
        let expectation = expectation(description: "Parse completes")
        let url = URL(string: "https://example.com/video/manifest.mpd")!

        mockSession.dataHandler = { request in
            let data = TestFixtures.dashVODManifest.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response, nil)
        }

        parser.parse(url: url) { result in
            if case .success(let info) = result {
                XCTAssertEqual(info.qualities.count, 2)
            } else {
                XCTFail("Expected success")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testParseURL_networkError_returnsError() {
        let expectation = expectation(description: "Parse completes")
        let url = URL(string: "https://example.com/video/manifest.mpd")!

        mockSession.dataHandler = { _ in
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            return (nil, nil, error)
        }

        parser.parse(url: url) { result in
            if case .failure(.networkError) = result {
                // Expected
            } else {
                XCTFail("Expected network error")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
```

---

## Phase 6: Update project.yml

Add new test files to the test target sources.

**File:** `OfflineBrowser/project.yml` (no changes needed - Tests directory is included)

---

## Implementation Order

1. **Step 1:** Create `DASHParser.swift` with data structures and basic XML parsing
2. **Step 2:** Implement `parseISO8601Duration()` helper
3. **Step 3:** Implement MPD root element and AdaptationSet parsing
4. **Step 4:** Implement Representation and SegmentTemplate parsing
5. **Step 5:** Implement ContentProtection (DRM) detection
6. **Step 6:** Implement URL resolution for segments
7. **Step 7:** Create `DASHParserProtocol.swift`
8. **Step 8:** Create `MockDASHParser.swift`
9. **Step 9:** Add DASH fixtures to `TestFixtures.swift`
10. **Step 10:** Create `DASHParserTests.swift`
11. **Step 11:** Integrate with `StreamDetector.swift`
12. **Step 12:** Run all tests and verify

---

## Estimated Test Count

| Test File | Test Count |
|-----------|------------|
| DASHParserTests | ~20 tests |
| StreamDetector DASH integration | ~5 tests |
| **Total new tests** | ~25 tests |

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `Features/Browser/Detection/DASHParser.swift` | CREATE |
| `Core/Protocols/DASHParserProtocol.swift` | CREATE |
| `Tests/Mocks/MockDASHParser.swift` | CREATE |
| `Tests/Components/DASHParserTests.swift` | CREATE |
| `Tests/Helpers/TestFixtures.swift` | MODIFY (add DASH fixtures) |
| `Features/Browser/Detection/StreamDetector.swift` | MODIFY (add DASH parsing) |

---

## Validation Criteria

1. All existing 276 tests continue to pass
2. New DASHParser tests pass (~20 tests)
3. StreamDetector correctly filters DRM-protected DASH streams
4. StreamDetector correctly filters live DASH streams
5. Duration-based deduplication works for DASH streams
6. Quality extraction produces valid `StreamQuality` objects
