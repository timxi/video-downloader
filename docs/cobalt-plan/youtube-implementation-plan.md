# YouTube Support Implementation Plan

## Overview

**Priority**: P0 (Highest value, most complex)
**Estimated Complexity**: High
**Dependencies**: JavaScript bridge infrastructure

YouTube is the most requested video platform. Cobalt's implementation uses the `youtubei.js` library to interact with YouTube's Innertube API, handling bot protection, signature deciphering, and quality selection.

---

## Technical Analysis

### How Cobalt Handles YouTube

Cobalt's YouTube implementation (`api/src/processing/services/youtube.js`, 520+ lines) uses:

1. **youtubei.js Library** (v15.1.1)
   - NPM package that wraps YouTube's internal Innertube API
   - Handles authentication, API requests, and response parsing
   - Extracts video info, streaming URLs, and metadata

2. **Bot Protection (po_token)**
   - YouTube requires Proof of Origin tokens for playback
   - Generated via `BG` (BotGuard) challenge-response
   - Cobalt uses external token generation service
   - Tokens expire and need refresh

3. **Two Download Paths**:
   - **HLS Path** (iOS client): Returns `.m3u8` manifest, simpler but lower quality ceiling
   - **Adaptive Path** (Web client): Returns DASH-like formats, requires signature deciphering

4. **Signature Deciphering**
   - Non-iOS clients receive encrypted stream URLs
   - Requires extracting decipher function from YouTube's player JavaScript
   - `youtubei.js` handles this automatically

5. **Quality Options**
   - Range: 144p, 240p, 360p, 480p, 720p, 1080p, 1440p, 2160p, 4320p
   - Codecs: H.264 (avc1), VP9 (vp9), AV1 (av01)
   - Audio: AAC (mp4a), Opus (opus), Vorbis (vorbis)

### Key Code Patterns from Cobalt

```javascript
// Initialize Innertube with po_token
const yt = await Innertube.create({
    po_token: proofOfOrigin,
    visitor_data: visitorData,
    fetch: async (input, init) => {
        // Custom fetch with cookie handling
    }
});

// Get video info
const info = await yt.getBasicInfo(videoId, clientType);

// Extract streaming data
const streamingData = info.streaming_data;
const hlsManifest = streamingData?.hls_manifest_url;
const adaptiveFormats = streamingData?.adaptive_formats;
```

---

## Implementation Strategy

### Recommended Approach: JavaScript Bridge

Rather than porting `youtubei.js` to Swift (massive effort), run JavaScript in a hidden WKWebView and bridge results to Swift.

```
┌─────────────────────────────────────────────────────────────┐
│                     OfflineBrowser                          │
├─────────────────────────────────────────────────────────────┤
│  BrowserViewController                                      │
│     │                                                       │
│     ▼                                                       │
│  StreamDetector ──► YouTubeExtractor (new)                  │
│                          │                                  │
│                          ▼                                  │
│                    Hidden WKWebView                         │
│                          │                                  │
│                    ┌─────┴─────┐                            │
│                    │  Bundle   │                            │
│                    │  youtube- │                            │
│                    │  extract  │                            │
│                    │    .js    │                            │
│                    └─────┬─────┘                            │
│                          │                                  │
│                    Message Handler                          │
│                          │                                  │
│                          ▼                                  │
│                 DetectedStream (HLS URL)                    │
│                          │                                  │
│                          ▼                                  │
│              Existing Download Pipeline                     │
│              (HLSParser → DownloadTask)                     │
└─────────────────────────────────────────────────────────────┘
```

### Why JavaScript Bridge?

| Approach | Pros | Cons |
|----------|------|------|
| Port to Swift | Native, fast | Huge effort, hard to maintain |
| Embed Node.js | Full youtubei.js | App size, complexity |
| **JS Bridge** | Reuse library, maintainable | WebView overhead |
| API Proxy | Simplest | Server cost, single point of failure |

---

## Implementation Phases

### Phase 1: Infrastructure (JS Bridge)

**Files to Create:**
- `Features/Browser/Extraction/YouTubeExtractor.swift`
- `Features/Browser/Extraction/JSBridge.swift`
- `Resources/youtube-extract.js`

**JSBridge.swift:**
```swift
protocol JSBridgeDelegate: AnyObject {
    func jsBridge(_ bridge: JSBridge, didExtractStreams streams: [DetectedStream])
    func jsBridge(_ bridge: JSBridge, didFailWithError error: Error)
}

class JSBridge: NSObject {
    private var webView: WKWebView!
    weak var delegate: JSBridgeDelegate?

    func setup() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "streamExtracted")
        contentController.add(self, name: "extractionError")
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)

        // Load bundled JS
        if let jsURL = Bundle.main.url(forResource: "youtube-extract", withExtension: "js"),
           let jsCode = try? String(contentsOf: jsURL) {
            webView.evaluateJavaScript(jsCode)
        }
    }

    func extractYouTube(videoId: String, cookies: [HTTPCookie]) {
        let cookieJSON = cookies.map { ["name": $0.name, "value": $0.value] }
        let script = "extractYouTube('\(videoId)', \(cookieJSON.jsonString))"
        webView.evaluateJavaScript(script)
    }
}

extension JSBridge: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "streamExtracted":
            // Parse JSON response into DetectedStream
            if let dict = message.body as? [String: Any] {
                let streams = parseStreams(dict)
                delegate?.jsBridge(self, didExtractStreams: streams)
            }
        case "extractionError":
            let error = NSError(domain: "YouTubeExtractor", code: -1)
            delegate?.jsBridge(self, didFailWithError: error)
        default:
            break
        }
    }
}
```

**YouTubeExtractor.swift:**
```swift
protocol YouTubeExtractorProtocol {
    func canExtract(url: URL) -> Bool
    func extract(url: URL, cookies: [HTTPCookie], completion: @escaping (Result<[DetectedStream], Error>) -> Void)
}

class YouTubeExtractor: YouTubeExtractorProtocol {
    private let jsBridge = JSBridge()

    private let youtubePatterns = [
        "youtube.com/watch",
        "youtu.be/",
        "youtube.com/shorts/",
        "youtube.com/embed/"
    ]

    func canExtract(url: URL) -> Bool {
        let urlString = url.absoluteString
        return youtubePatterns.contains { urlString.contains($0) }
    }

    func extract(url: URL, cookies: [HTTPCookie],
                 completion: @escaping (Result<[DetectedStream], Error>) -> Void) {
        guard let videoId = extractVideoId(from: url) else {
            completion(.failure(YouTubeError.invalidURL))
            return
        }

        jsBridge.extractYouTube(videoId: videoId, cookies: cookies)
    }

    private func extractVideoId(from url: URL) -> String? {
        // Handle: youtube.com/watch?v=ID, youtu.be/ID, youtube.com/shorts/ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return videoId
        }

        let path = url.path
        if path.hasPrefix("/shorts/") {
            return String(path.dropFirst(8))
        }

        if url.host == "youtu.be" {
            return String(path.dropFirst(1))
        }

        return nil
    }
}
```

### Phase 2: JavaScript Extraction Module

**youtube-extract.js:**
```javascript
// Bundled with app - uses subset of youtubei.js functionality
// Simplified implementation focused on HLS extraction

const INNERTUBE_API_KEY = '<INNERTUBE_KEY>'; // Public YouTube web client key
const INNERTUBE_CLIENT_VERSION = '2.20240101.00.00';

async function extractYouTube(videoId, cookies) {
    try {
        // Use iOS client to get HLS manifest (avoids signature deciphering)
        const response = await fetch('https://www.youtube.com/youtubei/v1/player', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Youtube-Client-Name': '5', // iOS
                'X-Youtube-Client-Version': '19.29.1',
            },
            body: JSON.stringify({
                videoId: videoId,
                context: {
                    client: {
                        clientName: 'IOS',
                        clientVersion: '19.29.1',
                        deviceModel: 'iPhone16,2',
                        userAgent: 'com.google.ios.youtube/19.29.1',
                        hl: 'en',
                        gl: 'US',
                    }
                },
                contentCheckOk: true,
                racyCheckOk: true,
            }),
            credentials: 'include',
        });

        const data = await response.json();

        if (data.playabilityStatus?.status !== 'OK') {
            throw new Error(data.playabilityStatus?.reason || 'Video unavailable');
        }

        const streamingData = data.streamingData;
        const hlsUrl = streamingData?.hlsManifestUrl;

        if (hlsUrl) {
            // Return HLS manifest URL - let OfflineBrowser's HLSParser handle it
            window.webkit.messageHandlers.streamExtracted.postMessage({
                type: 'hls',
                url: hlsUrl,
                title: data.videoDetails?.title,
                duration: parseInt(data.videoDetails?.lengthSeconds) || 0,
                thumbnail: data.videoDetails?.thumbnail?.thumbnails?.pop()?.url,
            });
        } else {
            // No HLS, would need signature deciphering for adaptive formats
            throw new Error('HLS manifest not available');
        }

    } catch (error) {
        window.webkit.messageHandlers.extractionError.postMessage({
            message: error.message
        });
    }
}

// Expose to Swift
window.extractYouTube = extractYouTube;
```

### Phase 3: Integration with StreamDetector

**Modify StreamDetector.swift:**
```swift
class StreamDetector {
    // Add extractor
    private let youtubeExtractor: YouTubeExtractorProtocol

    init(hlsParser: HLSParserProtocol = HLSParser(),
         dashParser: DASHParserProtocol = DASHParser(),
         youtubeExtractor: YouTubeExtractorProtocol = YouTubeExtractor()) {
        self.hlsParser = hlsParser
        self.dashParser = dashParser
        self.youtubeExtractor = youtubeExtractor
    }

    func detectStreams(in webView: WKWebView) async -> [DetectedStream] {
        // Check for YouTube first
        if let url = webView.url, youtubeExtractor.canExtract(url: url) {
            // Get cookies from webView
            let cookies = await getCookies(from: webView)

            do {
                return try await youtubeExtractor.extract(url: url, cookies: cookies)
            } catch {
                // Fall through to generic detection
                os_log("YouTube extraction failed: %@", error.localizedDescription)
            }
        }

        // Existing generic detection
        return await detectGenericStreams(in: webView)
    }
}
```

### Phase 4: UI Integration

**Modify BrowserViewController.swift:**
```swift
// In handleDownloadTap() or similar:

if let url = webView.url, url.host?.contains("youtube.com") == true || url.host == "youtu.be" {
    // Show YouTube-specific loading indicator
    showLoadingIndicator(message: "Extracting YouTube video...")

    Task {
        let streams = await streamDetector.detectStreams(in: webView)
        hideLoadingIndicator()

        if streams.isEmpty {
            showAlert(title: "Cannot Download",
                     message: "This YouTube video cannot be downloaded. It may be age-restricted, private, or region-locked.")
        } else {
            showDownloadOptions(streams: streams)
        }
    }
}
```

### Phase 5: Testing

**Create YouTubeExtractorTests.swift:**
```swift
import XCTest
@testable import OfflineBrowser

class YouTubeExtractorTests: XCTestCase {
    var extractor: YouTubeExtractor!

    override func setUp() {
        extractor = YouTubeExtractor()
    }

    func testCanExtractYouTubeWatch() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertTrue(extractor.canExtract(url: url))
    }

    func testCanExtractYoutuBe() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertTrue(extractor.canExtract(url: url))
    }

    func testCanExtractYouTubeShorts() {
        let url = URL(string: "https://www.youtube.com/shorts/abc123")!
        XCTAssertTrue(extractor.canExtract(url: url))
    }

    func testCannotExtractOtherSites() {
        let url = URL(string: "https://vimeo.com/123456")!
        XCTAssertFalse(extractor.canExtract(url: url))
    }

    func testExtractVideoIdFromWatch() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertEqual(extractor.extractVideoId(from: url), "dQw4w9WgXcQ")
    }

    func testExtractVideoIdFromShortUrl() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertEqual(extractor.extractVideoId(from: url), "dQw4w9WgXcQ")
    }
}
```

---

## Known Limitations & Mitigations

### 1. Age-Restricted Videos
- **Issue**: Require login to access
- **Mitigation**: User logs into YouTube in browser, cookies passed to extractor

### 2. Private/Unlisted Videos
- **Issue**: Require account access
- **Mitigation**: Same as above - use authenticated session

### 3. Premium-Only Content
- **Issue**: YouTube Premium exclusive
- **Mitigation**: Detect and show user-friendly error

### 4. Bot Protection Changes
- **Issue**: YouTube may update po_token requirements
- **Mitigation**: Use iOS client (less strict), monitor for changes

### 5. Regional Restrictions
- **Issue**: Some videos blocked by country
- **Mitigation**: Detect and inform user

### 6. Rate Limiting
- **Issue**: Too many requests may get blocked
- **Mitigation**: Add delay between extractions, respect 429 responses

---

## File Structure

```
OfflineBrowser/
├── Features/
│   └── Browser/
│       └── Extraction/           # New folder
│           ├── JSBridge.swift
│           ├── YouTubeExtractor.swift
│           └── YouTubeExtractorProtocol.swift
├── Resources/
│   └── youtube-extract.js        # Bundled JS module
└── Tests/
    ├── Components/
    │   └── YouTubeExtractorTests.swift
    └── Mocks/
        └── MockYouTubeExtractor.swift
```

---

## Implementation Checklist

- [x] Phase 1: JSBridge infrastructure
  - [x] Create JSBridge.swift with WKWebView message handlers
  - [x] Create YouTubeExtractor.swift with URL pattern matching
  - [x] Add YouTubeExtractorProtocol for testing

- [x] Phase 2: JavaScript module
  - [x] Create youtube-extract.js with Innertube API calls (iOS client)
  - [x] Add to Xcode project as bundle resource
  - [x] Test HLS URL extraction

- [x] Phase 3: StreamDetector integration
  - [x] Add YouTubeExtractor to StreamDetector
  - [x] Implement cookie forwarding from WKWebView
  - [x] Handle SPA navigation (URL change observer)
  - [x] Add fallback to generic detection

- [x] Phase 4: UI integration
  - [x] Add YouTube-specific loading state (FloatingPill spinner)
  - [x] Handle extraction errors gracefully
  - [x] Show appropriate error messages (BOT_PROTECTION, AGE_RESTRICTED, etc.)

- [ ] Phase 5: Testing
  - [ ] Unit tests for URL pattern matching
  - [ ] Unit tests for video ID extraction
  - [ ] Mock extractor for integration tests
  - [ ] Manual testing with various YouTube URLs

## Current Status (January 2026)

### What Works
- YouTube URL detection (all patterns: watch, shorts, embed, youtu.be)
- Video ID extraction
- iOS client Innertube API calls
- Cookie forwarding from browser session
- Loading state UI

### Known Limitation: Bot Protection
YouTube's bot protection (`po_token` requirement) blocks many extraction attempts with:
> "Sign in to confirm you're not a bot"

**Root Cause**: YouTube requires a Proof of Origin token (`po_token`) generated via BotGuard challenge-response. This cannot be generated in-app without running YouTube's obfuscated JavaScript.

**Cobalt's Solution**: Uses external `yt-session-generator` server:
https://github.com/imputnet/youtube-trusted-session-generator

**Options for OfflineBrowser**:
1. Accept lower success rate (~30-50% of videos work without po_token)
2. Deploy companion po_token server
3. Wait for community solutions to po_token generation

---

## Success Metrics

1. **Extraction Rate**: >90% of public YouTube videos extractable
2. **Quality**: HLS streams with multiple quality options available
3. **Speed**: Extraction completes in <3 seconds
4. **Reliability**: Graceful fallback when extraction fails

---

## Future Enhancements

1. **Adaptive Format Support**: Add signature deciphering for higher quality
2. **Playlist Support**: Extract all videos from playlist
3. **Subtitle Download**: Extract and save caption tracks
4. **Channel Support**: Browse and download from channel pages
5. **Background Download**: Continue download when app backgrounded
