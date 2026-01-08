# Offline Browser - iOS App Specification

## Overview

**App Name:** Offline Browser
**Platform:** iOS 15+ (iPhone only)
**Distribution:** App Store (framed as offline browsing utility)
**UI Framework:** Hybrid - UIKit for browser/player, SwiftUI for library/settings

---

## Core Features

### 1. Embedded Browser

**Implementation:**
- WKWebView-based browser
- Minimal navigation: URL bar, back/forward buttons, refresh
- Persistent sessions - cookies, local storage, and logins retained across app launches

**Stream Detection:**
- JavaScript injection to intercept network requests (XMLHttpRequest, fetch)
- WKContentRuleList to strip CSP headers that would block injection
- Detection runs automatically as user browses

**Supported Formats:**
| Format | Extension | Notes |
|--------|-----------|-------|
| HLS | .m3u8 | Full spec parsing including nested manifests |
| DASH | .mpd | MPEG-DASH manifest support |
| MP4 | .mp4 | Direct video URLs |
| WebM | .webm | Direct video URLs |

**DRM/Encryption Handling:**
| Type | Behavior |
|------|----------|
| FairPlay (DRM) | Silent skip - no download option shown |
| AES-128 HLS | Download and decrypt locally during muxing |
| Live streams | Ignore - no download option shown |

---

### 2. Download System

**User Interface:**
- Floating pill/FAB appears when video(s) detected
- Single pill with count badge when multiple videos on page (e.g., "3 videos")
- Tap pill to see list and select which video(s) to download

**Quality Selection:**
- Remember user preference globally
- Apply to all future downloads without prompting
- Initial prompt shows available qualities with estimated file sizes

**Network Rules:**
- WiFi-only by default
- Global toggle to allow cellular downloads
- Per-download override option

**Queue Management:**
- One download at a time (sequential queue)
- Background downloads via URLSession background transfer service
- Downloads continue when app is suspended or screen locked

**Failure Handling:**
- Auto-retry with exponential backoff on network failure
- Resume from last successfully downloaded segment
- Track segment progress in database

**Notifications:**
- Completion notification only (success or failure)
- No progress update notifications

**Muxing:**
- FFmpeg via MobileFFmpeg/ffmpeg-kit
- Mux HLS segments into single MP4 file
- Decrypt AES-128 segments during mux process

---

### 3. Video Metadata

**Extraction:**
- Video title: Parse from page title or Open Graph tags
- Thumbnail: Capture from video element when possible
- Source domain: Stored for auto-folder organization

**Subtitles:**
- Detect EXT-X-MEDIA subtitle tracks in HLS manifests
- Download subtitle tracks alongside video
- Store as sidecar files for offline playback

---

### 4. Video Library

**Organization:**
- User-created folders/playlists
- Auto-generated folders by source domain (e.g., "twitter.com", "reddit.com")
- User can move videos between folders and rename folders

**Search:**
- Basic text search filtering by video title
- Results update as user types

**Storage:**
- App sandbox only - videos not visible in iOS Files app
- No export/share functionality
- User manages storage manually via in-app deletion
- Display total storage used by downloaded videos

---

### 5. Video Player

**Framework:**
- Custom player built on AVPlayer (not AVPlayerViewController)
- Full control over UI and gestures

**Core Features:**
- Picture-in-Picture (PiP) support
- Background audio - continues playing when app backgrounds or screen locks
- Sleep timer (15min, 30min, 45min, 1hr, end of video)
- Subtitle display with embedded subtitle tracks
- Remember playback position per video

**Gesture Controls:**
| Gesture | Action |
|---------|--------|
| Horizontal swipe | Seek forward/backward |
| Vertical swipe (left side) | Adjust brightness |
| Vertical swipe (right side) | Adjust volume |
| Double-tap left edge | Skip back 10 seconds |
| Double-tap right edge | Skip forward 10 seconds |
| Single tap | Toggle controls visibility |

**Playback Controls (on-screen):**
- Play/pause
- Skip forward/back 10s buttons
- Seek slider with time display
- Playback speed selector (0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x)
- PiP toggle
- Subtitle toggle
- Sleep timer button
- Fullscreen toggle

**Orientation:**
- Auto-rotate to landscape when entering fullscreen
- Return to portrait when exiting fullscreen

---

## Technical Architecture

### Data Persistence

**Database:** SQLite with GRDB.swift

**Schema (conceptual):**
```
videos
  - id (UUID)
  - title (TEXT)
  - source_url (TEXT)
  - source_domain (TEXT)
  - file_path (TEXT)
  - thumbnail_path (TEXT)
  - subtitle_path (TEXT, nullable)
  - duration (INTEGER)
  - file_size (INTEGER)
  - quality (TEXT)
  - folder_id (UUID, nullable)
  - created_at (TIMESTAMP)
  - last_played_at (TIMESTAMP, nullable)
  - playback_position (INTEGER, default 0)

folders
  - id (UUID)
  - name (TEXT)
  - is_auto_generated (BOOLEAN)
  - created_at (TIMESTAMP)

downloads
  - id (UUID)
  - video_url (TEXT)
  - manifest_url (TEXT, nullable)
  - status (TEXT: pending, downloading, muxing, completed, failed)
  - progress (REAL)
  - segments_downloaded (INTEGER)
  - segments_total (INTEGER)
  - retry_count (INTEGER)
  - error_message (TEXT, nullable)
  - created_at (TIMESTAMP)

preferences
  - key (TEXT PRIMARY KEY)
  - value (TEXT)
```

### File Storage Structure

```
Documents/
  videos/
    {uuid}/
      video.mp4
      thumbnail.jpg
      subtitles.vtt (if applicable)
  temp/
    {download_id}/
      segments/
        segment_0.ts
        segment_1.ts
        ...
```

### Third-Party Dependencies

| Library | Purpose | Notes |
|---------|---------|-------|
| GRDB.swift | SQLite wrapper | Swift-native, lightweight |
| ffmpeg-kit | Video muxing | LGPLv3 variant to avoid GPL |
| Firebase Crashlytics | Crash reporting | Google SDK dependency |

---

## User Experience

### Theming
- User toggle in settings: Light / Dark / System
- Override system setting when explicitly chosen

### Onboarding
- Contextual hints on first encounter of features
- Hint for download pill on first video detection
- Hint for gesture controls on first video playback
- Hints dismissable and don't repeat

### Settings Screen
- **Downloads**
  - Preferred quality (with explanation of current selection)
  - Allow cellular downloads (toggle)
- **Playback**
  - Default playback speed
  - Background audio (toggle, default on)
  - Remember playback position (toggle, default on)
- **Appearance**
  - Theme selector (Light/Dark/System)
- **Storage**
  - Total space used display
  - "Clear all downloads" button with confirmation
- **Privacy**
  - Clear browsing data button
  - Clear cookies button
- **About**
  - Version number
  - Licenses (for FFmpeg, GRDB, etc.)

---

## App Store Considerations

### Positioning
- Frame as "offline browsing utility" - save content for offline viewing
- Emphasize legitimate use cases: personal content, educational resources
- Avoid explicit "video downloader" language in metadata

### Privacy Policy Requirements
- Disclose data collected (crash reports via Crashlytics)
- Clarify no personal data sold or shared
- Document local-only storage of user content

### Screenshots/Marketing
- Show browser interface
- Emphasize offline library management
- De-emphasize download functionality in primary screenshots

---

## Implementation Priorities

### Phase 1: Core Browser
1. WKWebView setup with minimal navigation
2. Session persistence (cookies, local storage)
3. Basic UI shell (browser tab, library tab)

### Phase 2: Stream Detection
1. JavaScript injection framework
2. CSP bypass via WKContentRuleList
3. HLS manifest detection and parsing
4. MP4/WebM direct URL detection
5. DASH manifest detection and parsing (if time permits)

### Phase 3: Download Engine
1. Download queue management
2. HLS segment downloading
3. Background URLSession integration
4. Auto-retry with backoff logic
5. FFmpeg muxing integration
6. AES-128 decryption during mux

### Phase 4: Library & Playback
1. GRDB database setup
2. Library UI with folders
3. Custom video player with gestures
4. PiP and background audio
5. Subtitle support
6. Search functionality

### Phase 5: Polish
1. Contextual onboarding hints
2. Settings screen
3. Storage management UI
4. Theme support
5. Crashlytics integration
6. App Store preparation

---

## Open Questions / Future Considerations

- **DASH support complexity:** Full DASH parsing is significantly more complex than HLS. May defer to post-launch.
- **ffmpeg-kit size:** Evaluate minimal build with only required codecs to reduce app size.
- **Rate limiting:** Some sites may rate-limit segment downloads. May need configurable delay between requests.
- **Cookies for segments:** Some CDNs require authentication cookies for segment URLs. Ensure cookie forwarding from WKWebView to URLSession.
