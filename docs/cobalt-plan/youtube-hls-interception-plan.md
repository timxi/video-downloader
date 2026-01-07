# YouTube HLS Interception Plan (Option 4)

## Overview

**Alternative Approach**: Instead of calling YouTube's Innertube API directly (which triggers bot protection), intercept the HLS manifest URLs that YouTube's web player fetches when a video plays.

**Key Insight**: On iOS WebKit, YouTube's mobile web player often serves HLS streams directly (not MSE/DASH) because iOS Safari has limited Media Source Extensions support.

---

## Why This Might Work

### iOS WebKit Behavior

When YouTube detects iOS Safari/WebKit:
1. It falls back to HLS streaming (native iOS video support)
2. The player requests `.m3u8` manifest URLs directly
3. These URLs are fetchable and downloadable

```
YouTube Web Player (iOS)
         │
         ▼
  Detects iOS/Safari
         │
         ▼
  Serves HLS stream ──► .m3u8 manifest ──► Our interceptor captures it
         │
         ▼
  Video plays natively
```

### Advantage Over Innertube API

| Aspect | Innertube API | HLS Interception |
|--------|--------------|------------------|
| Bot protection | ❌ Triggers po_token check | ✅ User is watching = legitimate |
| Authentication | Manual cookie passing | ✅ Browser handles automatically |
| Request origin | Hidden WebView (suspicious) | ✅ Real user browsing |
| Success rate | ~30-50% | Potentially higher |

---

## Technical Architecture

### Current Network Interception (Already Exists)

```
NetworkInterceptor.js
        │
        ├── XMLHttpRequest.open() hook
        ├── fetch() wrapper
        ├── MutationObserver for <video>
        ├── MediaSource.addSourceBuffer() hook
        └── URL.createObjectURL() hook
```

**Current HLS Detection** (lines 165-175):
```javascript
function isHLSUrl(url) {
    const lowerUrl = url.toLowerCase();
    return lowerUrl.includes('.m3u8') ||
           lowerUrl.includes('/manifest/') ||
           lowerUrl.includes('index.m3u8') ||
           lowerUrl.includes('master.m3u8') ||
           (lowerUrl.includes('.ts') && lowerUrl.includes('/video/'));
}
```

### What Needs to Change

#### 1. YouTube-Specific HLS Pattern Detection

Add patterns for YouTube's HLS manifest URLs:

```javascript
function isYouTubeHLSUrl(url) {
    const lowerUrl = url.toLowerCase();

    // YouTube HLS manifest patterns
    return (
        // googlevideo.com HLS manifests
        (lowerUrl.includes('googlevideo.com') && lowerUrl.includes('.m3u8')) ||
        // youtube.com HLS manifests
        (lowerUrl.includes('youtube.com') && lowerUrl.includes('/manifest/')) ||
        // ytimg or other CDN variants
        (lowerUrl.includes('ytimg.com') && lowerUrl.includes('.m3u8'))
    );
}
```

#### 2. Enhanced Video Element Monitoring

Capture HLS URLs from video.src and source elements:

```javascript
function monitorVideoElements() {
    const videos = document.querySelectorAll('video');
    videos.forEach(video => {
        // Check direct src
        if (video.src && isYouTubeHLSUrl(video.src)) {
            reportStream(video.src, 'hls');
        }

        // Check source elements
        video.querySelectorAll('source').forEach(source => {
            if (source.src && isYouTubeHLSUrl(source.src)) {
                reportStream(source.src, 'hls');
            }
        });

        // Monitor for src changes
        const observer = new MutationObserver(mutations => {
            mutations.forEach(m => {
                if (m.attributeName === 'src' && isYouTubeHLSUrl(video.src)) {
                    reportStream(video.src, 'hls');
                }
            });
        });
        observer.observe(video, { attributes: true });
    });
}
```

#### 3. XHR/Fetch Response Inspection for YouTube

Intercept manifest fetches specifically:

```javascript
const originalFetch = window.fetch;
window.fetch = async function(url, options) {
    const response = await originalFetch.apply(this, arguments);

    const urlStr = typeof url === 'string' ? url : url.url;

    // If this is a YouTube manifest request, capture the URL
    if (isYouTubeHLSUrl(urlStr)) {
        reportStream(urlStr, 'hls');
    }

    return response;
};
```

---

## Implementation Phases

### Phase 1: YouTube HLS Pattern Detection

**File**: `Resources/NetworkInterceptor.js`

Add YouTube-specific HLS URL detection:

```javascript
// YouTube HLS detection patterns
const YOUTUBE_HLS_PATTERNS = [
    /googlevideo\.com.*\.m3u8/i,
    /youtube\.com\/api\/manifest\/hls/i,
    /manifest\.googlevideo\.com/i,
    /\.googlevideo\.com\/videoplayback.*mime=.*m3u8/i
];

function isYouTubeHLS(url) {
    return YOUTUBE_HLS_PATTERNS.some(pattern => pattern.test(url));
}
```

### Phase 2: Playback-Triggered Detection

Detect when YouTube video starts playing and wait for HLS manifest:

```javascript
// When on YouTube, monitor for video playback
if (isYouTubePage()) {
    document.addEventListener('play', function(e) {
        if (e.target.tagName === 'VIDEO') {
            // Video started - HLS manifest should be loaded soon
            // Start aggressive monitoring for 5 seconds
            startHLSCapture();
        }
    }, true);
}
```

### Phase 3: Disable Innertube API When Interception Succeeds

In `StreamDetector.swift`, prefer intercepted HLS over API extraction:

```swift
func checkAndExtractYouTube(url: URL, webView: WKWebView) -> Bool {
    guard youtubeExtractor.canExtract(url: url) else { return false }

    // First, wait briefly to see if HLS is intercepted from player
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
        // If no HLS detected yet, fall back to Innertube API
        if self?.detectedStreams.isEmpty == true {
            self?.extractViaInnertubeAPI(url: url, webView: webView)
        }
    }

    return true
}
```

### Phase 4: User-Initiated Playback Hint

Show UI prompting user to tap play on the video:

```swift
// In BrowserViewController, when YouTube video page detected
func showPlaybackHint() {
    let hint = "Tap play on the video, then tap the download button"
    HintManager.shared.showHint(message: hint, from: floatingPill, in: view)
}
```

---

## Challenges & Mitigations

### Challenge 1: YouTube May Use MSE Instead of HLS

**Risk**: On some devices/videos, YouTube uses Media Source Extensions instead of HLS.

**Mitigation**:
- Force mobile user agent to encourage HLS
- Fall back to Innertube API if no HLS detected after playback

### Challenge 2: Manifest URLs May Be Short-Lived

**Risk**: YouTube's signed URLs expire quickly (hours, not days).

**Mitigation**:
- Download immediately after detection
- Store manifest content, not just URL
- Re-fetch manifest if download delayed

### Challenge 3: Quality Selection

**Risk**: Intercepted manifest may be for a specific quality, not master playlist.

**Mitigation**:
- Parse intercepted manifest for quality variants
- If single quality, accept it
- Try to find master playlist URL pattern from variant URL

### Challenge 4: DRM-Protected Content

**Risk**: Some YouTube content uses Widevine DRM even in HLS.

**Mitigation**:
- Detect `#EXT-X-KEY:METHOD=SAMPLE-AES` or similar
- Skip DRM streams with user-friendly message
- This is a YouTube policy limitation, not solvable

---

## File Changes Required

| File | Changes |
|------|---------|
| `NetworkInterceptor.js` | Add YouTube HLS patterns, playback monitoring |
| `StreamDetector.swift` | Add delay before Innertube fallback |
| `BrowserViewController.swift` | Add playback hint for YouTube pages |
| `HLSParser.swift` | Handle YouTube's HLS manifest format variations |

---

## Testing Plan

### Test Cases

1. **YouTube mobile web (m.youtube.com)**
   - Navigate to video page
   - Tap play
   - Verify HLS manifest captured

2. **Different video types**
   - Regular videos
   - Music videos
   - Age-restricted (logged in)
   - Live streams (should be filtered)

3. **Fallback behavior**
   - If HLS not captured in 5 seconds, Innertube API should trigger
   - Innertube failures should show appropriate error

4. **Quality detection**
   - Verify qualities parsed from manifest
   - Test download of different qualities

---

## Success Metrics

| Metric | Target |
|--------|--------|
| HLS interception rate | >70% of YouTube videos |
| Time to detection | <5 seconds after play |
| Download success rate | >90% of detected streams |
| No bot protection errors | 100% (since user is playing video) |

---

## Comparison: Current vs. Proposed

| Aspect | Current (Innertube API) | Proposed (HLS Interception) |
|--------|------------------------|----------------------------|
| User action required | None (automatic) | Must tap play |
| Bot protection | Frequently blocked | Bypassed (legitimate playback) |
| Quality options | All from API | What player loads |
| Complexity | Medium | Low (uses existing interceptor) |
| Reliability | Low (~30-50%) | Potentially high |

---

## Recommendation

**Implement as a complement, not replacement:**

1. Keep Innertube API as first attempt (works for some videos)
2. If Innertube fails with bot protection, prompt user to play video
3. Capture HLS from player as fallback
4. Best of both worlds

```
YouTube Video Detected
         │
         ▼
  Try Innertube API ───────────────────────┐
         │                                 │
    Success?                          Bot blocked?
         │                                 │
         ▼                                 ▼
   Use HLS URL                    Show "Tap play to download" hint
         │                                 │
         ▼                                 ▼
     Download                    User taps play → HLS intercepted
                                          │
                                          ▼
                                      Download
```

---

## Implementation Effort

| Phase | Effort | Priority |
|-------|--------|----------|
| Phase 1: Pattern detection | 2 hours | High |
| Phase 2: Playback monitoring | 3 hours | High |
| Phase 3: Fallback logic | 2 hours | Medium |
| Phase 4: UI hints | 1 hour | Low |

**Total: ~8 hours**

---

## Next Steps

1. Test current NetworkInterceptor on YouTube to see if any HLS is captured
2. Identify exact YouTube HLS URL patterns via browser dev tools
3. Implement Phase 1 pattern detection
4. Test on various YouTube videos
5. Implement remaining phases based on results
