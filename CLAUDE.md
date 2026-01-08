# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

This is an iOS project using XcodeGen to generate the Xcode project from `project.yml`.

```bash
# Generate Xcode project (required after modifying project.yml or adding files)
cd OfflineBrowser
/opt/homebrew/bin/xcodegen generate

# Run all tests
SHELL=/bin/bash xcodebuild test \
  -project OfflineBrowser/OfflineBrowser.xcodeproj \
  -scheme OfflineBrowser \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'

# Run a specific test class
SHELL=/bin/bash xcodebuild test \
  -project OfflineBrowser/OfflineBrowser.xcodeproj \
  -scheme OfflineBrowser \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:OfflineBrowserTests/HLSParserTests

# Run a specific test method
-only-testing:OfflineBrowserTests/HLSParserTests/testParseMasterPlaylist
```

## Architecture Overview

**OfflineBrowser** is an iOS video downloader app with an embedded browser. It detects HLS/MP4 streams via JavaScript injection, downloads segments, muxes them with FFmpeg, and provides offline playback.

### Core Flow
1. **Browser** (WKWebView) → JavaScript intercepts network requests
2. **StreamDetector** → Parses HLS manifests, deduplicates streams
3. **DownloadManager** → Queues downloads, creates DownloadTask instances
4. **DownloadTask** → Downloads segments sequentially, handles cookies/auth
5. **FFmpegMuxer** → Concatenates segments into MP4
6. **VideoRepository** → Saves to database, auto-creates domain folders

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `StreamDetector` | Features/Browser/Detection/ | Detects and deduplicates video streams from intercepted URLs |
| `HLSParser` | Features/Browser/Detection/ | Parses m3u8 manifests (master/media), extracts qualities, detects DRM/encryption |
| `DownloadManager` | Features/Download/Engine/ | Singleton managing download queue, processes one at a time |
| `DownloadTask` | Features/Download/Engine/ | Handles single download lifecycle (HLS segments or direct MP4) |
| `FFmpegMuxer` | Features/Download/Muxing/ | Muxes TS/fMP4 segments into MP4 via ffmpeg-kit |
| `NetworkInterceptor.js` | Resources/ | Injected JS that intercepts XHR/fetch for stream detection |

### Database Layer (GRDB)
- Models: `Video`, `Folder`, `Download`, `Preference` in Core/Database/Models/
- Repositories with protocol abstractions in Core/Database/Repositories/
- Protocol definitions in Core/Protocols/ enable dependency injection for testing

### UI Architecture
- **UIKit**: BrowserViewController, player controls
- **SwiftUI**: LibraryView, SettingsView, PlayerView
- Hybrid approach with UIHostingController bridges

## Testing

Tests are in `OfflineBrowser/Tests/` organized by type:
- `Pure/` - Unit tests for pure functions (RetryPolicy, model computed properties)
- `Components/` - Component tests with mocks (HLSParser, FileStorageManager)
- `Repositories/` - Database tests with in-memory GRDB
- `Integration/` - DownloadManager integration tests
- `Mocks/` - Mock implementations for protocols
- `Helpers/` - TestFixtures, TestDatabaseManager

All production classes have injectable initializers for testability while maintaining `static let shared` singletons for production use.

## Dependencies

- **GRDB.swift** - SQLite database wrapper
- **ffmpeg-kit** - Video muxing (TS/fMP4 segments → MP4)
- **Firebase Crashlytics** - Crash reporting (not yet integrated)

## Development Guidelines

When adding new code, ensure unit tests are written to cover the new functionality. Use the existing mock infrastructure in `Tests/Mocks/` and follow the established patterns:
- Pure functions → test in `Tests/Pure/`
- Components with dependencies → create protocol, add mock, test in `Tests/Components/`
- Repository operations → use TestDatabaseManager for in-memory database tests

## Implementation Status

See `plan.md` for detailed task tracking. Key incomplete areas:
- Phase 9: Player missing PiP, SleepTimer, SubtitleRenderer
- Phase 3: DASHParser not implemented
- Phase 13: Accessibility features not implemented
