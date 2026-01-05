# Offline Browser - Implementation Plan

## Overview

This plan provides step-by-step instructions to build the iOS video downloader app based on spec.md. The app uses WKWebView with JavaScript injection for stream detection, FFmpeg for muxing, and a custom video player.

---

## Project Structure

```
OfflineBrowser/
├── App/
│   ├── OfflineBrowserApp.swift          # App entry point
│   ├── AppDelegate.swift                 # Background URLSession handling
│   └── SceneDelegate.swift               # Scene lifecycle
├── Core/
│   ├── Database/
│   │   ├── DatabaseManager.swift         # GRDB setup and migrations
│   │   ├── Models/
│   │   │   ├── Video.swift               # Video record model
│   │   │   ├── Folder.swift              # Folder record model
│   │   │   ├── Download.swift            # Download record model
│   │   │   └── Preference.swift          # Key-value preferences
│   │   └── Repositories/
│   │       ├── VideoRepository.swift
│   │       ├── FolderRepository.swift
│   │       └── DownloadRepository.swift
│   ├── Networking/
│   │   ├── BackgroundSessionManager.swift   # URLSession background config
│   │   └── CookieManager.swift              # Cookie sync WKWebView <-> URLSession
│   └── Storage/
│       └── FileStorageManager.swift         # File paths, cleanup, storage calc
├── Features/
│   ├── Browser/
│   │   ├── BrowserViewController.swift      # UIKit - WKWebView container
│   │   ├── BrowserNavigationBar.swift       # URL bar, back/forward/refresh
│   │   ├── CSPBypass/
│   │   │   └── ContentRuleListManager.swift # WKContentRuleList for CSP strip
│   │   ├── Injection/
│   │   │   ├── ScriptMessageHandler.swift   # WKScriptMessageHandler
│   │   │   ├── NetworkInterceptor.js        # JS to intercept XHR/fetch
│   │   │   └── InjectionManager.swift       # Inject scripts, handle messages
│   │   └── Detection/
│   │       ├── StreamDetector.swift         # Coordinate detection logic
│   │       ├── HLSParser.swift              # Parse m3u8 manifests
│   │       ├── DASHParser.swift             # Parse mpd manifests
│   │       └── DetectedStream.swift         # Model for detected streams
│   ├── Download/
│   │   ├── UI/
│   │   │   ├── FloatingPillView.swift       # FAB showing detected videos
│   │   │   └── DownloadOptionsSheet.swift   # Quality selection bottom sheet
│   │   ├── Engine/
│   │   │   ├── DownloadManager.swift        # Queue, scheduling, state
│   │   │   ├── DownloadTask.swift           # Single download lifecycle
│   │   │   ├── SegmentDownloader.swift      # HLS segment fetching
│   │   │   ├── DirectDownloader.swift       # MP4/WebM direct download
│   │   │   └── RetryPolicy.swift            # Exponential backoff logic
│   │   ├── Muxing/
│   │   │   ├── FFmpegMuxer.swift            # ffmpeg-kit wrapper
│   │   │   └── AESDecryptor.swift           # HLS AES-128 key handling
│   │   └── MetadataExtractor.swift          # Title, thumbnail extraction
│   ├── Library/
│   │   ├── LibraryView.swift                # SwiftUI - main library screen
│   │   ├── FolderListView.swift             # Folder sidebar/list
│   │   ├── VideoGridView.swift              # Video thumbnails grid
│   │   ├── VideoRowView.swift               # Single video cell
│   │   ├── SearchBar.swift                  # Search filtering
│   │   └── FolderManagement/
│   │       ├── CreateFolderSheet.swift
│   │       ├── MoveVideoSheet.swift
│   │       └── FolderContextMenu.swift
│   ├── Player/
│   │   ├── PlayerViewController.swift       # UIKit - AVPlayer container
│   │   ├── PlayerControlsView.swift         # Play/pause, seek, etc.
│   │   ├── GestureHandler.swift             # Swipe, double-tap gestures
│   │   ├── SubtitleRenderer.swift           # VTT/WebVTT display
│   │   ├── PiPManager.swift                 # Picture-in-Picture setup
│   │   ├── SleepTimerManager.swift          # Sleep timer logic
│   │   └── PlaybackSpeedPicker.swift        # Speed selection UI
│   └── Settings/
│       ├── SettingsView.swift               # SwiftUI - settings screen
│       ├── DownloadSettingsSection.swift
│       ├── PlaybackSettingsSection.swift
│       ├── AppearanceSettingsSection.swift
│       ├── StorageSettingsSection.swift
│       ├── PrivacySettingsSection.swift
│       └── AboutSection.swift
├── Shared/
│   ├── Theme/
│   │   ├── ThemeManager.swift               # Light/Dark/System handling
│   │   └── Colors.swift                     # App color definitions
│   ├── Onboarding/
│   │   ├── HintManager.swift                # Track shown hints
│   │   └── ContextualHintView.swift         # Tooltip-style hints
│   ├── Extensions/
│   │   ├── URL+Extensions.swift
│   │   ├── String+Extensions.swift
│   │   └── FileManager+Extensions.swift
│   └── Utilities/
│       ├── NotificationManager.swift        # Local notifications
│       └── NetworkMonitor.swift             # WiFi vs cellular detection
├── Resources/
│   ├── Assets.xcassets
│   ├── NetworkInterceptor.js                # Bundled JS file
│   └── Localizable.strings
└── Tests/
    ├── HLSParserTests.swift
    ├── DownloadManagerTests.swift
    └── DatabaseTests.swift
```

---

## Technical Spikes (Validate First)

Before full implementation, prototype these risky components:

### Spike 1: CSP Bypass Validation
**Goal:** Confirm WKContentRuleList can strip CSP headers reliably
**Steps:**
1. Create minimal WKWebView app
2. Implement content rule to strip `Content-Security-Policy` header
3. Test on YouTube, Twitter, Instagram
4. Verify injected JS executes without CSP errors

### Spike 2: JavaScript Injection Communication
**Goal:** Confirm JS can intercept requests and communicate to Swift
**Steps:**
1. Write JS that monkey-patches XMLHttpRequest and fetch
2. Implement WKScriptMessageHandler to receive messages
3. Test detection of .m3u8 URLs on sample sites
4. Verify timing (detection happens before/during video play)

### Spike 3: Background URLSession with Cookies
**Goal:** Confirm cookies from WKWebView work in background downloads
**Steps:**
1. Create WKWebView, log into a site requiring auth
2. Extract cookies from WKHTTPCookieStore
3. Apply to URLSession via HTTPCookieStorage
4. Download authenticated resource in background

### Spike 4: FFmpeg-kit Integration
**Goal:** Validate muxing and app size impact
**Steps:**
1. Add ffmpeg-kit-ios-min (smallest variant) via SPM
2. Mux sample .ts segments into .mp4
3. Test AES-128 decryption during mux
4. Measure app size increase

---

## Implementation Steps

### Phase 0: Project Setup

#### Step 0.1: Create Xcode Project
- [ ] Create new iOS App project named "OfflineBrowser"
- [ ] Set minimum deployment target: iOS 15.0
- [ ] Set device: iPhone only
- [ ] Create folder structure as defined above

#### Step 0.2: Add Dependencies
- [ ] Add GRDB.swift via Swift Package Manager
  - URL: `https://github.com/groue/GRDB.swift`
- [ ] Add ffmpeg-kit via SPM
  - URL: `https://github.com/arthenica/ffmpeg-kit`
  - Use `min` variant for smallest size
- [ ] Add Firebase Crashlytics via SPM
  - URL: `https://github.com/firebase/firebase-ios-sdk`

#### Step 0.3: Configure Capabilities
- [ ] Enable Background Modes:
  - [x] Audio, AirPlay, and Picture in Picture
  - [x] Background fetch
  - [x] Background processing
- [ ] Configure Audio Session category for background playback
- [ ] Add Privacy descriptions to Info.plist:
  - NSCameraUsageDescription (for thumbnail capture if needed)

#### Step 0.4: Configure App Structure
- [ ] Create AppDelegate for background URLSession delegate
- [ ] Set up SceneDelegate for window management
- [ ] Create main TabBarController with two tabs: Browser, Library

---

### Phase 1: Database Foundation

#### Step 1.1: Database Setup
- [ ] Implement `DatabaseManager.swift`
  - Create SQLite database in Documents directory
  - Configure GRDB DatabasePool
  - Define migration system

#### Step 1.2: Define Models
- [ ] Implement `Video.swift` - GRDB Record
  ```swift
  struct Video: Codable, FetchableRecord, PersistableRecord {
      var id: UUID
      var title: String
      var sourceURL: String
      var sourceDomain: String
      var filePath: String
      var thumbnailPath: String?
      var subtitlePath: String?
      var duration: Int
      var fileSize: Int64
      var quality: String
      var folderID: UUID?
      var createdAt: Date
      var lastPlayedAt: Date?
      var playbackPosition: Int
  }
  ```
- [ ] Implement `Folder.swift`
- [ ] Implement `Download.swift` with status enum
- [ ] Implement `Preference.swift` for key-value settings

#### Step 1.3: Implement Repositories
- [ ] `VideoRepository` - CRUD operations, search, folder queries
- [ ] `FolderRepository` - Create, rename, delete, list
- [ ] `DownloadRepository` - Queue management, status updates

#### Step 1.4: Database Migrations
- [ ] Migration 1: Create initial schema (videos, folders, downloads, preferences)

**Checkpoint:** Unit tests pass for all repository operations

---

### Phase 2: Core Browser

#### Step 2.1: Browser View Controller
- [ ] Create `BrowserViewController` (UIViewController)
- [ ] Add WKWebView as main view
- [ ] Configure WKWebViewConfiguration:
  - Enable JavaScript
  - Allow inline media playback
  - Enable media playback requires user action = false

#### Step 2.2: Navigation Bar
- [ ] Create `BrowserNavigationBar` (UIView)
- [ ] Add URL text field with keyboard handling
- [ ] Add back button (disabled when can't go back)
- [ ] Add forward button (disabled when can't go forward)
- [ ] Add refresh button
- [ ] Handle URL submission and navigation

#### Step 2.3: Session Persistence
- [ ] Configure WKWebsiteDataStore for persistent storage
- [ ] Ensure cookies persist across app launches
- [ ] Test login persistence on sample site

#### Step 2.4: Tab Bar Integration
- [ ] Create main TabBarController
- [ ] Add Browser tab with BrowserViewController
- [ ] Add placeholder Library tab
- [ ] Set up tab bar icons and titles

**Checkpoint:** Can browse websites, sessions persist across launches

---

### Phase 3: JavaScript Injection & Stream Detection

#### Step 3.1: CSP Bypass
- [ ] Implement `ContentRuleListManager`
- [ ] Create JSON rules to remove CSP headers:
  ```json
  [{
    "trigger": {"url-filter": ".*"},
    "action": {"type": "modify-headers", "response-headers": [
      {"header": "Content-Security-Policy", "operation": "remove"},
      {"header": "Content-Security-Policy-Report-Only", "operation": "remove"}
    ]}
  }]
  ```
- [ ] Compile and apply WKContentRuleList to WKWebView

#### Step 3.2: Network Interceptor JavaScript
- [ ] Create `NetworkInterceptor.js`:
  ```javascript
  (function() {
    const originalXHR = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      checkForStream(url);
      return originalXHR.apply(this, arguments);
    };

    const originalFetch = window.fetch;
    window.fetch = function(input, init) {
      const url = typeof input === 'string' ? input : input.url;
      checkForStream(url);
      return originalFetch.apply(this, arguments);
    };

    function checkForStream(url) {
      if (url.includes('.m3u8') || url.includes('.mpd') ||
          url.match(/\.(mp4|webm)(\?|$)/i)) {
        window.webkit.messageHandlers.streamDetector.postMessage({
          type: 'streamDetected',
          url: url
        });
      }
    }
  })();
  ```

#### Step 3.3: Script Message Handler
- [ ] Implement `ScriptMessageHandler` (WKScriptMessageHandler)
- [ ] Handle incoming messages from JavaScript
- [ ] Parse URL and determine stream type

#### Step 3.4: Injection Manager
- [ ] Create `InjectionManager`
- [ ] Inject script at document start
- [ ] Configure WKUserContentController
- [ ] Connect message handler

#### Step 3.5: Stream Detector
- [ ] Implement `StreamDetector` singleton
- [ ] Maintain list of detected streams per page
- [ ] Deduplicate detections
- [ ] Publish changes via Combine/NotificationCenter

#### Step 3.6: HLS Parser
- [ ] Implement `HLSParser`
- [ ] Parse master playlist to extract quality variants
- [ ] Parse media playlist to count segments
- [ ] Detect EXT-X-KEY for AES-128 encryption
- [ ] Detect EXT-X-MEDIA for subtitle tracks
- [ ] Detect #EXT-X-ENDLIST absence (live stream)
- [ ] Handle EXT-X-STREAM-INF bandwidth info

#### Step 3.7: Direct URL Detection
- [ ] Detect .mp4 and .webm direct URLs
- [ ] Create DetectedStream model for direct downloads

#### Step 3.8: DRM Detection
- [ ] Detect EXT-X-KEY with METHOD=SAMPLE-AES (FairPlay)
- [ ] Detect KEYFORMAT="com.apple.streamingkeydelivery"
- [ ] Mark streams as DRM-protected, exclude from UI

**Checkpoint:** Visit video site, see console logs for detected streams

---

### Phase 4: Floating Pill UI

#### Step 4.1: Floating Pill View
- [ ] Create `FloatingPillView` (UIView)
- [ ] Position at bottom-right of browser, above tab bar
- [ ] Show download icon + count badge
- [ ] Add bounce animation on new detection
- [ ] Fade in/out based on detection state

#### Step 4.2: Stream List Sheet
- [ ] Create `DownloadOptionsSheet` (UIViewController presented as sheet)
- [ ] List all detected streams with:
  - Inferred video title
  - Quality/resolution
  - Estimated file size (if known)
- [ ] Tap to select for download
- [ ] Show quality picker if first download (to set preference)

#### Step 4.3: Integration
- [ ] Connect pill to StreamDetector updates
- [ ] Show/hide pill based on detected stream count
- [ ] Present sheet on pill tap

**Checkpoint:** Pill appears when video detected, can see stream list

---

### Phase 5: Download Engine

#### Step 5.1: Download Manager
- [ ] Implement `DownloadManager` singleton
- [ ] Maintain download queue (array of pending downloads)
- [ ] Process one download at a time
- [ ] Publish state changes via Combine

#### Step 5.2: Background URLSession Setup
- [ ] Implement `BackgroundSessionManager`
- [ ] Create background URLSession configuration
- [ ] Implement delegate in AppDelegate for background completion
- [ ] Handle app relaunch for background completion

#### Step 5.3: Cookie Synchronization
- [ ] Implement `CookieManager`
- [ ] Sync cookies from WKHTTPCookieStore to HTTPCookieStorage
- [ ] Apply cookies to background URLSession requests

#### Step 5.4: Segment Downloader (HLS)
- [ ] Implement `SegmentDownloader`
- [ ] Fetch and parse m3u8 manifest
- [ ] Download segments sequentially
- [ ] Save to temp/{download_id}/segments/
- [ ] Track progress in database
- [ ] Handle AES-128 key download

#### Step 5.5: Direct Downloader (MP4/WebM)
- [ ] Implement `DirectDownloader`
- [ ] Simple background download task
- [ ] Track progress via URLSessionDownloadDelegate

#### Step 5.6: Retry Policy
- [ ] Implement `RetryPolicy`
- [ ] Exponential backoff: 1s, 2s, 4s, 8s, max 60s
- [ ] Max retry count: 5
- [ ] Resume from last segment on reconnect

#### Step 5.7: Network Monitoring
- [ ] Implement `NetworkMonitor` using NWPathMonitor
- [ ] Detect WiFi vs cellular
- [ ] Pause downloads on cellular if setting disabled
- [ ] Resume when WiFi reconnects

**Checkpoint:** Can download HLS segments to temp folder

---

### Phase 6: FFmpeg Muxing

#### Step 6.1: FFmpeg Wrapper
- [ ] Implement `FFmpegMuxer`
- [ ] Build ffmpeg command for segment concatenation
- [ ] Execute via ffmpeg-kit
- [ ] Monitor progress

#### Step 6.2: AES-128 Decryption
- [ ] Implement `AESDecryptor`
- [ ] Extract key from EXT-X-KEY URI
- [ ] Pass key to ffmpeg for decryption during mux
- [ ] Or decrypt segments before mux using CommonCrypto

#### Step 6.3: Muxing Integration
- [ ] After all segments downloaded, trigger mux
- [ ] Move final .mp4 to videos/{uuid}/video.mp4
- [ ] Clean up temp segments folder

#### Step 6.4: Subtitle Handling
- [ ] Download subtitle m3u8 and segments
- [ ] Mux into sidecar .vtt file
- [ ] Store path in database

**Checkpoint:** Complete download produces playable .mp4

---

### Phase 7: Metadata Extraction

#### Step 7.1: Title Extraction
- [ ] Implement `MetadataExtractor`
- [ ] Request page HTML via JavaScript:
  ```javascript
  document.title ||
  document.querySelector('meta[property="og:title"]')?.content
  ```
- [ ] Clean up title (remove site name suffixes, etc.)

#### Step 7.2: Thumbnail Capture
- [ ] Inject JS to find video element dimensions/position
- [ ] Use WKWebView snapshot or video element canvas capture
- [ ] Fallback: Generate thumbnail from downloaded video using AVAssetImageGenerator

#### Step 7.3: Database Entry
- [ ] Create Video record after successful download
- [ ] Auto-create folder based on source domain if not exists
- [ ] Link video to folder

**Checkpoint:** Downloaded videos appear in library with title and thumbnail

---

### Phase 8: Video Library (SwiftUI)

#### Step 8.1: Library View
- [ ] Create `LibraryView` (SwiftUI)
- [ ] Two-column layout: Folders sidebar (iPad style collapsed to menu on iPhone), video grid
- [ ] Fetch videos from database via VideoRepository

#### Step 8.2: Folder List
- [ ] Create `FolderListView`
- [ ] Show "All Videos" at top
- [ ] List user folders and auto-generated folders
- [ ] Highlight selected folder
- [ ] Long-press for context menu (rename, delete)

#### Step 8.3: Video Grid
- [ ] Create `VideoGridView`
- [ ] Display video thumbnails in grid
- [ ] Show title, duration overlay
- [ ] Tap to play
- [ ] Long-press for context menu (move, delete)

#### Step 8.4: Search
- [ ] Add search bar above grid
- [ ] Filter videos by title as user types
- [ ] Debounce search input

#### Step 8.5: Folder Management
- [ ] Create folder sheet
- [ ] Rename folder sheet
- [ ] Move video to folder sheet
- [ ] Delete folder with confirmation (videos move to root)

#### Step 8.6: Storage Display
- [ ] Calculate total storage used
- [ ] Display in settings and optionally in library header

**Checkpoint:** Full library browsing with folders, search, management

---

### Phase 9: Video Player

#### Step 9.1: Player View Controller
- [ ] Create `PlayerViewController` (UIViewController)
- [ ] Add AVPlayerLayer as layer
- [ ] Configure AVAudioSession for playback category
- [ ] Enable background audio mode

#### Step 9.2: Player Controls
- [ ] Create `PlayerControlsView` (overlay)
- [ ] Play/pause button
- [ ] Seek slider with current/total time
- [ ] Skip forward/back 10s buttons
- [ ] Fullscreen toggle
- [ ] Auto-hide after 3 seconds of inactivity

#### Step 9.3: Gesture Handler
- [ ] Implement `GestureHandler`
- [ ] Horizontal pan: seek (calculate offset from pan distance)
- [ ] Vertical pan left: brightness (UIScreen.main.brightness)
- [ ] Vertical pan right: volume (MPVolumeView slider)
- [ ] Double-tap edges: skip 10s
- [ ] Single tap: toggle controls

#### Step 9.4: Playback Position
- [ ] Save position to database on pause/exit
- [ ] Resume from saved position on play
- [ ] Show "Continue from X:XX?" prompt if position > 10s

#### Step 9.5: Playback Speed
- [ ] Implement `PlaybackSpeedPicker`
- [ ] Options: 0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x
- [ ] Apply via AVPlayer.rate

#### Step 9.6: Picture-in-Picture
- [ ] Implement `PiPManager`
- [ ] Configure AVPictureInPictureController
- [ ] Handle PiP start/stop
- [ ] Maintain playback state during PiP

#### Step 9.7: Background Audio
- [ ] Configure AVAudioSession category: .playback
- [ ] Handle interruptions (phone call, etc.)
- [ ] Continue playback when app backgrounds

#### Step 9.8: Sleep Timer
- [ ] Implement `SleepTimerManager`
- [ ] Options: 15min, 30min, 45min, 1hr, end of video
- [ ] Timer pauses playback and shows optional notification

#### Step 9.9: Subtitle Renderer
- [ ] Implement `SubtitleRenderer`
- [ ] Parse WebVTT file
- [ ] Display captions synced to playback time
- [ ] Toggle visibility
- [ ] Position at bottom with background

#### Step 9.10: Orientation Handling
- [ ] Force landscape on fullscreen enter
- [ ] Return to portrait on fullscreen exit
- [ ] Use UIViewController orientation overrides

**Checkpoint:** Full video playback with all features working

---

### Phase 10: Settings (SwiftUI)

#### Step 10.1: Settings View Structure
- [ ] Create `SettingsView` as Form
- [ ] Organize into sections per spec

#### Step 10.2: Download Settings
- [ ] Quality picker (stored in Preferences)
- [ ] Allow cellular toggle

#### Step 10.3: Playback Settings
- [ ] Default playback speed picker
- [ ] Background audio toggle
- [ ] Remember position toggle

#### Step 10.4: Appearance Settings
- [ ] Theme picker: Light / Dark / System
- [ ] Apply via ThemeManager

#### Step 10.5: Storage Settings
- [ ] Display total space used
- [ ] "Clear all downloads" with confirmation alert

#### Step 10.6: Privacy Settings
- [ ] Clear browsing data button
- [ ] Clear cookies button (warns about losing logins)

#### Step 10.7: About Section
- [ ] App version from bundle
- [ ] Licenses button (shows OSS licenses)

**Checkpoint:** All settings functional and persisted

---

### Phase 11: Theme & Onboarding

#### Step 11.1: Theme Manager
- [ ] Implement `ThemeManager`
- [ ] Read/write theme preference
- [ ] Apply UIUserInterfaceStyle override
- [ ] Handle system theme changes

#### Step 11.2: Contextual Hints
- [ ] Implement `HintManager` (tracks shown hints)
- [ ] Create `ContextualHintView` (tooltip UI)
- [ ] Hint 1: Download pill (first video detection)
- [ ] Hint 2: Gesture controls (first video play)
- [ ] Hint 3: Folder organization (first 5 downloads)
- [ ] Dismiss on tap, don't show again

**Checkpoint:** Hints appear at right moments, theme switching works

---

### Phase 12: Notifications & Crashlytics

#### Step 12.1: Local Notifications
- [ ] Implement `NotificationManager`
- [ ] Request notification permission on first download
- [ ] Send notification on download complete/failed
- [ ] Tapping notification opens library

#### Step 12.2: Firebase Crashlytics
- [ ] Configure Firebase in AppDelegate
- [ ] Initialize Crashlytics
- [ ] Set user properties if needed (non-identifying)
- [ ] Verify crash reports in Firebase console

**Checkpoint:** Notifications work, crashes reported to Firebase

---

### Phase 13: Polish & Edge Cases

#### Step 13.1: Error Handling
- [ ] Display user-friendly error messages for download failures
- [ ] Handle network unreachable gracefully
- [ ] Handle storage full scenario

#### Step 13.2: Empty States
- [ ] Library empty state with guidance
- [ ] Search no results state
- [ ] Download queue empty state

#### Step 13.3: Loading States
- [ ] Skeleton/shimmer for loading library
- [ ] Progress indicator for downloads
- [ ] Muxing progress display

#### Step 13.4: Memory Management
- [ ] Clear video cache on memory warning
- [ ] Limit thumbnail cache size
- [ ] Release AVPlayer when not in use

#### Step 13.5: Accessibility
- [ ] VoiceOver labels for all controls
- [ ] Dynamic Type support
- [ ] Reduce Motion support

**Checkpoint:** App handles edge cases gracefully

---

### Phase 14: Testing & App Store Prep

#### Step 14.1: Unit Tests
- [ ] HLSParser tests (various manifest formats)
- [ ] Database repository tests
- [ ] DownloadManager queue logic tests

#### Step 14.2: Integration Tests
- [ ] Full download flow test
- [ ] Background download completion test
- [ ] Session persistence test

#### Step 14.3: Manual Testing Checklist
- [ ] Test on various video sites
- [ ] Test background downloads
- [ ] Test PiP and background audio
- [ ] Test low storage scenarios
- [ ] Test poor network conditions

#### Step 14.4: App Store Assets
- [ ] App icon (all sizes)
- [ ] Screenshots (6.5", 5.5")
- [ ] App description (offline utility framing)
- [ ] Privacy policy URL
- [ ] Keywords

#### Step 14.5: Submission
- [ ] Archive build
- [ ] TestFlight internal testing
- [ ] Submit for review

---

## Dependencies Between Steps

```
Phase 0 (Setup)
    ↓
Phase 1 (Database)
    ↓
Phase 2 (Browser) ──────────────────┐
    ↓                                │
Phase 3 (Detection) ←────────────────┤
    ↓                                │
Phase 4 (Pill UI) ←──────────────────┤
    ↓                                │
Phase 5 (Download Engine) ←──────────┤
    ↓                                │
Phase 6 (FFmpeg) ←───────────────────┤
    ↓                                │
Phase 7 (Metadata) ←─────────────────┤
    ↓                                │
Phase 8 (Library) ←──────────────────┘
    ↓
Phase 9 (Player)
    ↓
Phase 10-14 (Settings, Polish, Ship)
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| CSP bypass fails on major sites | Fallback: Document unsupported sites, or implement proxy fallback |
| FFmpeg adds 50MB+ to app | Use min variant, strip unused codecs, evaluate alternatives |
| App Store rejection | Careful framing, be prepared to appeal or pivot to TestFlight |
| Background downloads unreliable | Extensive testing, implement robust retry/resume |
| Cookie sync fails for some CDNs | Test extensively, may need per-site workarounds |

---

## Estimated Complexity

| Phase | Complexity | Notes |
|-------|------------|-------|
| 0: Setup | Low | Standard Xcode project |
| 1: Database | Low | GRDB makes this straightforward |
| 2: Browser | Low | Basic WKWebView |
| 3: Detection | High | JS injection + CSP bypass + parsing |
| 4: Pill UI | Medium | Custom floating view |
| 5: Download Engine | High | Background sessions, queue, retry |
| 6: FFmpeg | Medium | Integration, not custom coding |
| 7: Metadata | Medium | JS communication, image capture |
| 8: Library | Medium | Standard SwiftUI CRUD |
| 9: Player | High | Custom gestures, PiP, background audio |
| 10: Settings | Low | Standard SwiftUI forms |
| 11: Theme/Onboarding | Low | Small features |
| 12: Notifications | Low | Standard iOS APIs |
| 13: Polish | Medium | Many small fixes |
| 14: Testing/Ship | Medium | Thorough QA needed |
