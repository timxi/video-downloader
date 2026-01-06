# Unit Testing Plan for OfflineBrowser iOS App

## Overview
Add comprehensive unit tests with significant refactoring to enable dependency injection and testability.

**Current State**: Empty test target (OfflineBrowserTests), no tests, heavy singleton usage

---

## Phase 1: Foundation - Pure Function Tests (No Refactoring)

### Test Directory Structure
```
OfflineBrowser/Tests/
├── Helpers/
│   ├── TestFixtures.swift           # Sample HLS manifests, model factories
│   ├── TestDatabaseManager.swift    # In-memory GRDB setup
│   └── XCTestCase+Extensions.swift  # Common utilities
├── Mocks/                           # (Phase 2)
├── Pure/                            # Pure function tests
├── Components/                      # Component tests with mocks
├── Repositories/                    # Database tests
└── Integration/                     # End-to-end tests
```

### Pure Function Test Files
1. **RetryPolicyTests.swift** - Test `delay()`, `shouldRetry()`, `delayWithJitter()`
2. **StreamQualityExtensionsTests.swift** - Test `sortedByQuality`, `highest`, `lowest`, `quality(matching:)`, `formattedBandwidth`
3. **VideoComputedPropertiesTests.swift** - Test `formattedDuration`, `formattedFileSize`
4. **DownloadComputedPropertiesTests.swift** - Test `formattedProgress`, `isActive`, `canRetry`, `incrementRetry()`
5. **FolderFactoryTests.swift** - Test `Folder.autoFolder(for:)`

### Files to Read (no modification needed):
- `OfflineBrowser/Features/Download/Engine/RetryPolicy.swift`
- `OfflineBrowser/Features/Browser/Detection/DetectedStream.swift` (StreamQuality)
- `OfflineBrowser/Core/Database/Models/Video.swift`
- `OfflineBrowser/Core/Database/Models/Download.swift`
- `OfflineBrowser/Core/Database/Models/Folder.swift`

---

## Phase 2: Protocol Abstractions & Dependency Injection

### New Protocol Files to Create in `OfflineBrowser/Core/Protocols/`:

1. **URLSessionProtocol.swift**
   - `URLSessionProtocol` with `dataTask()`, `downloadTask()`
   - `URLSessionDataTaskProtocol`, `URLSessionDownloadTaskProtocol`
   - Extensions for `URLSession`, `URLSessionDataTask`, `URLSessionDownloadTask`

2. **FileManagerProtocol.swift**
   - Wrap `FileManager` methods: `fileExists()`, `createDirectory()`, `moveItem()`, `copyItem()`, etc.

3. **HLSParserProtocol.swift**
   - `parse(url:completion:)`, `parseManifest(content:baseURL:completion:)`

4. **FileStorageManagerProtocol.swift**
   - All public methods from `FileStorageManager`

5. **RepositoryProtocols.swift**
   - `VideoRepositoryProtocol`, `DownloadRepositoryProtocol`, `FolderRepositoryProtocol`

6. **FFmpegMuxerProtocol.swift**
   - `muxHLSSegments()` method

### Production Code Refactoring:

| File | Changes |
|------|---------|
| `HLSParser.swift` | Add `init(urlSession:)`, expose helper methods as `internal` |
| `FileStorageManager.swift` | Add `init(fileManager:)`, conform to protocol |
| `DownloadTask.swift` | Add `init(download:cookies:hlsParser:urlSession:fileStorage:muxer:)` |
| `StreamDetector.swift` | Add `init(hlsParser:)`, expose deduplication methods as `internal` |
| `VideoRepository.swift` | Add `init(dbPool:fileStorage:)` |
| `DownloadRepository.swift` | Add `init(dbPool:fileStorage:)` |
| `FolderRepository.swift` | Add `init(dbPool:)` |
| `DownloadManager.swift` | Add `init(downloadRepository:videoRepository:folderRepository:fileStorage:downloadTaskFactory:)` |

**Pattern**: Keep `static let shared` for backward compatibility, add injectable initializers with defaults.

---

## Phase 3: Mock Implementations & Component Tests

### Mock Files to Create in `OfflineBrowser/Tests/Mocks/`:

1. **MockURLSession.swift** - Capture requests, return configured responses
2. **MockFileManager.swift** - Track operations, configurable existence/attributes
3. **MockHLSParser.swift** - Return configured `HLSParsedInfo` results
4. **MockFileStorageManager.swift** - Track operations, return configured paths
5. **MockFFmpegMuxer.swift** - Return configured mux results
6. **MockRepositories.swift** - In-memory storage for Video, Download, Folder
7. **MockDownloadTaskDelegate.swift** - Capture delegate callbacks

### Component Test Files:

1. **HLSParserTests.swift**
   - Master playlist parsing (qualities, subtitles, DRM detection)
   - Media playlist parsing (segments, duration, encryption, fMP4)
   - URL resolution logic
   - Error handling

2. **StreamDetectorTests.swift**
   - Stream detection and filtering
   - Duration-based deduplication
   - Quality deduplication
   - DRM/live stream skipping

3. **DownloadTaskTests.swift**
   - HLS download flow (manifest → segments → mux)
   - Direct download flow
   - Pause/resume/cancel
   - fMP4 init segment handling
   - Error handling

4. **FileStorageManagerTests.swift**
   - Path generation (pure)
   - Directory creation
   - File operations with mock FileManager

5. **FFmpegMuxerTests.swift**
   - Segment number extraction
   - Limited testing (FFmpegKit hard to mock)

---

## Phase 4: Repository Tests with In-Memory Database

### TestDatabaseManager.swift
- Create in-memory `DatabasePool`
- Apply same migrations as production

### Repository Test Files:

1. **VideoRepositoryTests.swift**
   - CRUD operations
   - Queries: fetchAll, fetchByFolder, search, fetchRecent, fetchByDomain
   - Playback position updates
   - Storage statistics

2. **DownloadRepositoryTests.swift**
   - CRUD operations
   - Status filtering: pending, active, failed
   - Progress updates
   - Retry logic

3. **FolderRepositoryTests.swift**
   - CRUD operations
   - Auto-folder creation
   - Video count statistics

---

## Phase 5: Integration Tests

### DownloadManagerTests.swift
- Queue management (FIFO processing)
- Download lifecycle (start → progress → complete)
- Retry scheduling
- Cookie extraction (mock WebView)
- Completion flow (temp → video directory → database)

---

## Critical Files to Modify

| File | Priority | Scope |
|------|----------|-------|
| `DownloadTask.swift` | HIGH | Most extensive refactoring - 5 protocol dependencies |
| `DownloadManager.swift` | HIGH | Orchestrator - 5 dependencies + task factory |
| `HLSParser.swift` | HIGH | URLSession protocol + expose helpers |
| `FileStorageManager.swift` | MEDIUM | FileManager protocol |
| `StreamDetector.swift` | MEDIUM | HLSParser protocol + expose algorithms |
| `VideoRepository.swift` | MEDIUM | DatabasePool + FileStorage protocols |
| `DownloadRepository.swift` | MEDIUM | DatabasePool + FileStorage protocols |
| `FolderRepository.swift` | LOW | DatabasePool protocol only |

---

## Test Fixtures Needed

```swift
struct TestFixtures {
    // HLS Manifests
    static let masterPlaylist: String      // 2 quality variants
    static let mediaPlaylist: String       // 3 segments, VOD
    static let livePlaylist: String        // No EXT-X-ENDLIST
    static let encryptedPlaylist: String   // AES-128
    static let drmProtectedPlaylist: String // SAMPLE-AES
    static let fmp4Playlist: String        // EXT-X-MAP

    // Model Factories
    static func makeVideo(...) -> Video
    static func makeDownload(...) -> Download
    static func makeStreamQuality(...) -> StreamQuality
    static func makeFolder(...) -> Folder
}
```

---

## Sample Test Cases

### RetryPolicyTests.swift
```swift
func testDelay_RetryCount0_ReturnsBaseDelay()      // 1.0s
func testDelay_RetryCount1_Returns2Seconds()       // 2.0s
func testDelay_RetryCount10_CapsAtMaxDelay()       // 60.0s
func testShouldRetry_UnderMaxRetries_ReturnsTrue() // 0-4 returns true
func testShouldRetry_AtMaxRetries_ReturnsFalse()   // 5 returns false
```

### StreamQualityExtensionsTests.swift
```swift
func testSortedByQuality_SortsDescendingByBandwidth()
func testHighest_ReturnsHighestBandwidth()
func testQualityMatching_720p_Returns720pVariant()
func testFormattedBandwidth_FormatsCorrectly()     // 5000000 -> "5.0 Mbps"
```

### HLSParserTests.swift
```swift
func testParseMasterPlaylist_ExtractsQualities()
func testParseMediaPlaylist_ExtractsSegments()
func testParseMediaPlaylist_DetectsFMP4Format()
func testResolveURL_RelativePath_ResolvesCorrectly()
```

### DownloadTaskTests.swift
```swift
func testStart_HLSDownload_FetchesManifest()
func testStart_FMP4Stream_DownloadsInitSegment()
func testPause_StopsDownload()
func testCancel_StopsAndCallsDelegate()
```

---

## Estimated Effort

| Phase | Description | Files Created | Files Modified |
|-------|-------------|---------------|----------------|
| 1 | Pure function tests | 6 test files | 0 |
| 2 | Protocols & DI | 6 protocol files | 8 production files |
| 3 | Mocks & component tests | 7 mock files, 5 test files | 0 |
| 4 | Repository tests | 1 helper, 3 test files | 0 |
| 5 | Integration tests | 1 test file | 0 |

**Total**: ~29 new files, ~8 modified production files

---

## Implementation Order

1. **Week 1**: Phase 1 - Pure function tests
   - Set up test structure
   - Create TestFixtures
   - Write all pure function tests

2. **Week 2**: Phase 2 - Protocols & DI
   - Create protocol files
   - Refactor production code with injectable initializers
   - Ensure backward compatibility

3. **Week 3**: Phase 3 - Mocks & Component Tests
   - Create all mock implementations
   - Write HLSParser, StreamDetector, DownloadTask tests

4. **Week 4**: Phase 4 - Repository Tests
   - Create TestDatabaseManager
   - Write all repository tests

5. **Week 5**: Phase 5 - Integration Tests
   - Write DownloadManager tests
   - Code coverage analysis and gap filling
