# Cobalt Website Support Integration Plan for OfflineBrowser

This document analyzes the websites supported by [Cobalt](https://github.com/imputnet/cobalt) and provides a roadmap for extending OfflineBrowser's video detection capabilities.

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Cobalt Supported Services](#cobalt-supported-services)
3. [Current OfflineBrowser Capabilities](#current-offlinebrowser-capabilities)
4. [Gap Analysis](#gap-analysis)
5. [Integration Approaches](#integration-approaches)
6. [Implementation Priority](#implementation-priority)
7. [Technical Implementation Details](#technical-implementation-details)
8. [Recommendations](#recommendations)

---

## Executive Summary

**Cobalt** is an open-source video downloader that supports **22 services** through service-specific extraction methods (APIs, HTML scraping, reverse-engineered endpoints).

**OfflineBrowser** currently uses **generic stream detection** (HLS/DASH/MP4 interception) which works on many sites but may miss videos that:
- Require API authentication
- Use proprietary player implementations
- Have anti-bot protections
- Serve video through non-standard URLs

**Key Finding**: Many Cobalt-supported sites already work with OfflineBrowser's generic detection (Dailymotion, Vimeo, Rutube). Adding service-specific extractors would improve reliability and unlock additional features (quality selection, metadata).

---

## Cobalt Supported Services

### Complete Service List (22 Services)

| # | Service | Extraction Method | Features | Complexity |
|---|---------|------------------|----------|------------|
| 1 | **YouTube** | youtubei.js library | 4K, codec selection, subtitles, audio-only | High |
| 2 | **Twitter/X** | Syndication API | Video, GIF, multi-media picker | Medium |
| 3 | **TikTok** | HTML scraping | H.265, audio extraction, carousels | Medium |
| 4 | **Instagram** | Multiple API fallbacks | Posts, reels, stories, carousels | High |
| 5 | **Vimeo** | API + HLS | Quality selection, password-protected | Low |
| 6 | **Reddit** | OAuth2 API | Video + audio merge | Medium |
| 7 | **SoundCloud** | API | Audio with metadata | Low |
| 8 | **Bilibili** | HTML scraping | DASH, H.265, multi-part videos | Medium |
| 9 | **Bluesky** | HLS extraction | Video, images, GIFs | Low |
| 10 | **Twitch** | API | Clips only (not live) | Low |
| 11 | **Facebook** | API | HD/SD, reels | Medium |
| 12 | **Snapchat** | API | Stories, spotlight, multi-snap | Medium |
| 13 | **Pinterest** | API | Pin videos/images | Low |
| 14 | **Tumblr** | API | Audio/video posts | Low |
| 15 | **VK** | API | Multiple resolutions, subtitles | Medium |
| 16 | **Rutube** | HLS | Quality selection, subtitles | Low |
| 17 | **Xiaohongshu** | API | H.265/H.264, image carousels | Medium |
| 18 | **Dailymotion** | GraphQL API | HLS streaming | Low |
| 19 | **Loom** | API | Screen recordings | Low |
| 20 | **Newgrounds** | HTML scraping | Video and audio | Low |
| 21 | **Streamable** | Direct URL | Simple streaming | Low |
| 22 | **OK.ru** | API | Video extraction | Low |

### Service Details

#### Tier 1: High-Value, High-Complexity

**1. YouTube**
- **Method**: Uses `youtubei.js` library (Innertube API)
- **Features**:
  - Multiple codecs: H.264, VP9, AV1
  - Quality: 144p to 4320p (4K)
  - Audio-only extraction
  - Subtitle/caption download
  - Dubbed audio tracks
  - Age-restricted content (with cookies)
- **Challenges**: Bot protection (po_token), signature deciphering
- **URL Patterns**: `watch?v=`, `embed/`, `shorts/`, `youtu.be/`

**2. Instagram**
- **Method**: Multiple fallbacks (Mobile API → HTML embed → GraphQL)
- **Features**:
  - Posts, Reels, Stories
  - Carousel/multi-image posts
  - Proxy support for rate limiting
- **Challenges**: Aggressive rate limiting, login requirements
- **URL Patterns**: `/p/`, `/reel/`, `/stories/`, `/share/`

**3. TikTok**
- **Method**: HTML scraping (`__UNIVERSAL_DATA_FOR_REHYDRATION__`)
- **Features**:
  - H.265 codec support
  - Full audio extraction
  - Carousel images
  - Subtitles
- **Challenges**: Frequent page structure changes
- **URL Patterns**: `/@user/video/`, `/t/`, `vm.tiktok.com/`

#### Tier 2: Medium-Value, Medium-Complexity

**4. Twitter/X**
- **Method**: Syndication API with token generation
- **Features**:
  - Video extraction
  - GIF conversion
  - Multi-media posts (picker)
  - Subtitles
- **Challenges**: Token algorithm reverse-engineering
- **URL Patterns**: `/status/`, `x.com/`, `vxtwitter.com/`

**5. Reddit**
- **Method**: OAuth2 API
- **Features**:
  - Video + audio merging (Reddit serves separately)
  - GIF support
  - Short link resolution
- **Challenges**: OAuth setup, audio/video sync
- **URL Patterns**: `/comments/`, `/r/sub/s/`, `redd.it/`

**6. Facebook**
- **Method**: API extraction
- **Features**:
  - HD/SD quality selection
  - Reels support
  - Share link resolution
- **Challenges**: Login wall, frequent API changes
- **URL Patterns**: `/watch/`, `/reel/`, `fb.watch/`

**7. Bilibili**
- **Method**: HTML scraping (`window.__playinfo__`)
- **Features**:
  - DASH format
  - H.265 codec
  - Multi-part video selection
- **Challenges**: China-specific, may need proxy
- **URL Patterns**: `/video/BV`, `b23.tv/`

#### Tier 3: Lower Priority, Lower Complexity

**8-22. Other Services**

| Service | Method | Key Feature |
|---------|--------|-------------|
| Vimeo | API + HLS | Password protection |
| SoundCloud | API | Audio with metadata |
| Bluesky | HLS | Simple extraction |
| Twitch | API | Clips only |
| Snapchat | API | Stories/spotlight |
| Pinterest | API | Pin extraction |
| Tumblr | API | Blog media |
| VK | API | Russian social |
| Rutube | HLS | Russian YouTube |
| Xiaohongshu | API | Chinese social |
| Dailymotion | GraphQL | HLS streams |
| Loom | API | Screen recordings |
| Newgrounds | HTML | Flash-era content |
| Streamable | Direct | Simple hosting |
| OK.ru | API | Russian social |

---

## Current OfflineBrowser Capabilities

### Detection Methods

```
┌─────────────────────────────────────────────────────────────┐
│                    NetworkInterceptor.js                     │
├─────────────────────────────────────────────────────────────┤
│  • XMLHttpRequest hook (open/send)                          │
│  • Fetch API wrapper                                        │
│  • <video> element MutationObserver                         │
│  • HLS.js / Video.js library detection                      │
│  • MediaSource Extensions tracking                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      StreamDetector.swift                    │
├─────────────────────────────────────────────────────────────┤
│  • Duration-based deduplication (±15%)                      │
│  • Ad filtering (< 5 min)                                   │
│  • DRM detection (Widevine/FairPlay)                        │
│  • Quality variant grouping                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Format Parsers                            │
├─────────────────────────────────────────────────────────────┤
│  • HLSParser.swift - M3U8 manifests, fMP4/CMAF              │
│  • DASHParser.swift - MPD manifests                         │
│  • Direct MP4/WebM detection                                │
└─────────────────────────────────────────────────────────────┘
```

### Supported Formats
- **HLS**: Master playlists, media playlists, AES-128 encryption, fMP4/CMAF
- **DASH**: MPD manifests, multiple representations
- **Direct**: MP4, WebM, M4V, MOV

### Strengths
- Works on any site using standard streaming
- No service-specific code to maintain
- Cookie handling for authenticated content

### Limitations
- Can't extract videos without network requests (pre-loaded)
- No service-specific metadata
- May miss non-standard implementations
- No quality preference before detection

---

## Gap Analysis

### Sites That Work with Generic Detection

| Service | Works? | Notes |
|---------|--------|-------|
| Dailymotion | ✅ Yes | HLS detected via network |
| Vimeo | ✅ Yes | HLS streams intercepted |
| Rutube | ✅ Yes | HLS streams |
| Bluesky | ✅ Yes | HLS streams |
| Twitch | ✅ Yes | Clips use HLS |
| Streamable | ✅ Yes | Direct MP4 |
| Bilibili | ⚠️ Partial | DASH works, but needs cookie |
| VK | ⚠️ Partial | May work with login |

### Sites Requiring Service-Specific Extraction

| Service | Issue | Solution |
|---------|-------|----------|
| YouTube | Signature cipher, bot protection | youtubei.js or API |
| Instagram | Rate limiting, no direct streams | API with fallbacks |
| TikTok | No network streams, JS-rendered | HTML scraping |
| Twitter/X | Token-based syndication | Token generation |
| Reddit | Separate audio/video | API + merge |
| Facebook | Login wall | API or cookies |
| SoundCloud | Audio-only, no stream | API |

### Feature Gaps

| Feature | Cobalt | OfflineBrowser |
|---------|--------|----------------|
| Pre-download quality selection | ✅ | ⚠️ After detection |
| Audio-only extraction | ✅ | ❌ |
| Subtitle download | ✅ | ⚠️ HLS only |
| Metadata (title, artist) | ✅ | ⚠️ Page title only |
| Playlist support | ✅ | ❌ |
| Age-restricted content | ✅ | ❌ |

---

## Integration Approaches

### Option A: Port Service Handlers to Swift

**Description**: Rewrite Cobalt's JavaScript service handlers in Swift.

**Pros**:
- Native performance
- Full control over implementation
- No external dependencies

**Cons**:
- Significant development effort
- Must maintain parity with Cobalt updates
- Complex for services like YouTube

**Effort**: High (2-4 weeks per complex service)

### Option B: Embed Cobalt API Locally

**Description**: Bundle Cobalt's Node.js API as a local server.

**Pros**:
- Use Cobalt's extraction directly
- Automatic updates possible
- Proven extraction logic

**Cons**:
- Node.js runtime overhead on iOS
- App Store compliance concerns
- Memory/battery impact

**Effort**: Medium (1-2 weeks setup)

**Note**: Not recommended for iOS due to App Store restrictions.

### Option C: Hybrid Approach (Recommended)

**Description**: Keep generic detection + add service-specific extractors for high-value sites.

**Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│                    URL Detection Layer                       │
├─────────────────────────────────────────────────────────────┤
│  User navigates to page                                      │
│  ↓                                                          │
│  ServiceMatcher.swift checks URL against known patterns      │
│  ↓                                                          │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │ Known Site  │ →  │ Service-Specific Extractor          │ │
│  │ (YouTube,   │    │ (API calls, HTML parsing)           │ │
│  │  TikTok)    │    └─────────────────────────────────────┘ │
│  └─────────────┘                                            │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │ Unknown     │ →  │ Generic Stream Detection            │ │
│  │ Site        │    │ (NetworkInterceptor.js)             │ │
│  └─────────────┘    └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Pros**:
- Best of both approaches
- Graceful fallback
- Incremental implementation

**Cons**:
- Two code paths to maintain
- Complexity in choosing path

**Effort**: Medium (1 week per service)

### Option D: JavaScript Bridge

**Description**: Port Cobalt extractors to JavaScript, run in WKWebView.

**Pros**:
- Easier to port from Cobalt's JS
- Can reuse existing code
- Sandboxed execution

**Cons**:
- Bridge overhead
- Security considerations
- Debugging complexity

**Effort**: Medium (2-3 days per service)

---

## Implementation Priority

### Priority Matrix

| Priority | Service | Value | Effort | Justification |
|----------|---------|-------|--------|---------------|
| P0 | YouTube | Very High | High | Most requested, complex |
| P1 | TikTok | High | Medium | Popular, HTML scraping |
| P1 | Twitter/X | High | Medium | Popular, API available |
| P2 | Instagram | High | High | Popular but complex |
| P2 | Reddit | Medium | Medium | Audio merge needed |
| P3 | Facebook | Medium | Medium | Login challenges |
| P3 | Bilibili | Medium | Medium | Regional |
| P4 | Others | Low | Low | Generic detection works |

### Recommended Implementation Order

**Phase 1: Foundation**
1. Create `ServiceMatcher.swift` - URL pattern matching
2. Create `ServiceExtractor` protocol
3. Implement fallback to generic detection

**Phase 2: High-Value Services**
1. TikTok extractor (HTML scraping is simpler)
2. Twitter/X extractor (API is documented)
3. YouTube extractor (most complex, highest value)

**Phase 3: Additional Services**
1. Instagram extractor
2. Reddit extractor (with audio merge)
3. Bilibili extractor

**Phase 4: Polish**
1. Audio-only download option
2. Subtitle extraction
3. Playlist support

---

## Technical Implementation Details

### ServiceMatcher.swift

```swift
struct ServiceMatcher {
    static func identify(url: URL) -> ServiceType? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path

        // YouTube
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        }

        // TikTok
        if host.contains("tiktok.com") || host.contains("vm.tiktok.com") {
            return .tiktok
        }

        // Twitter/X
        if host.contains("twitter.com") || host.contains("x.com") {
            return .twitter
        }

        // ... more services

        return nil // Use generic detection
    }
}
```

### ServiceExtractor Protocol

```swift
protocol ServiceExtractor {
    var serviceName: String { get }

    func canExtract(url: URL) -> Bool
    func extract(url: URL, cookies: [HTTPCookie]) async throws -> ExtractionResult
}

struct ExtractionResult {
    let streams: [DetectedStream]
    let metadata: VideoMetadata?
    let subtitles: [SubtitleTrack]?
}
```

### TikTok Extractor Example

```swift
class TikTokExtractor: ServiceExtractor {
    let serviceName = "TikTok"

    func extract(url: URL, cookies: [HTTPCookie]) async throws -> ExtractionResult {
        // 1. Fetch page HTML
        let html = try await fetchHTML(url: url, cookies: cookies)

        // 2. Extract JSON from script tag
        guard let jsonStr = html.extractBetween(
            start: "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\"",
            end: "</script>"
        ) else {
            throw ExtractionError.parseFailure
        }

        // 3. Parse video data
        let data = try JSONDecoder().decode(TikTokData.self, from: jsonStr.data(using: .utf8)!)
        let videoDetail = data.defaultScope.webappVideoDetail

        // 4. Build streams
        let stream = DetectedStream(
            url: videoDetail.video.playAddr,
            type: .direct,
            qualities: [StreamQuality(
                resolution: "\(videoDetail.video.height)p",
                bandwidth: videoDetail.video.bitrate,
                url: videoDetail.video.playAddr
            )]
        )

        return ExtractionResult(
            streams: [stream],
            metadata: VideoMetadata(
                title: videoDetail.desc,
                author: videoDetail.author.nickname
            ),
            subtitles: nil
        )
    }
}
```

---

## Recommendations

### Short-Term (1-2 weeks)
1. **Keep current generic detection** - It works for many sites
2. **Add ServiceMatcher** - URL pattern detection infrastructure
3. **Implement TikTok extractor** - Good balance of value/complexity

### Medium-Term (1-2 months)
1. **Add Twitter/X extractor** - Popular, API is stable
2. **Add YouTube basic support** - Even partial support is valuable
3. **Improve metadata extraction** - Title, thumbnail, duration

### Long-Term (3+ months)
1. **Full YouTube support** - Quality selection, codecs, subtitles
2. **Instagram support** - Complex but high value
3. **Audio-only downloads** - SoundCloud, YouTube Music
4. **Playlist support** - YouTube, SoundCloud playlists

### What NOT to Do
- ❌ Don't try to support all 22 services at once
- ❌ Don't bundle Node.js/Cobalt API (App Store issues)
- ❌ Don't remove generic detection (fallback is essential)
- ❌ Don't hardcode credentials (use user's login cookies)

---

## Appendix: Cobalt Service File Locations

```
cobalt/api/src/processing/
├── services/
│   ├── youtube.js      (520 lines)
│   ├── twitter.js      (180 lines)
│   ├── tiktok.js       (150 lines)
│   ├── instagram.js    (350 lines)
│   ├── vimeo.js        (120 lines)
│   ├── reddit.js       (100 lines)
│   ├── soundcloud.js   (130 lines)
│   ├── bilibili.js     (200 lines)
│   ├── bluesky.js      (80 lines)
│   ├── twitch.js       (60 lines)
│   ├── facebook.js     (100 lines)
│   ├── snapchat.js     (120 lines)
│   ├── pinterest.js    (70 lines)
│   ├── tumblr.js       (80 lines)
│   ├── vk.js           (150 lines)
│   ├── rutube.js       (100 lines)
│   ├── xiaohongshu.js  (90 lines)
│   ├── dailymotion.js  (80 lines)
│   ├── loom.js         (50 lines)
│   ├── newgrounds.js   (70 lines)
│   ├── streamable.js   (40 lines)
│   └── ok.js           (60 lines)
├── service-config.js   (URL patterns)
├── service-patterns.js (ID validation)
├── match.js            (Router)
└── url.js              (URL normalization)
```

---

*Document generated: January 2026*
*Based on Cobalt commit: latest*
*OfflineBrowser version: current main branch*
