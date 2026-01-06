import XCTest
@testable import OfflineBrowser

final class FileStorageManagerTests: XCTestCase {

    var sut: FileStorageManager!
    var mockFileManager: MockFileManager!

    override func setUp() {
        super.setUp()
        mockFileManager = MockFileManager()
        mockFileManager.documentsURL = URL(fileURLWithPath: "/mock/documents")
        sut = FileStorageManager(fileManager: mockFileManager)
    }

    override func tearDown() {
        sut = nil
        mockFileManager = nil
        super.tearDown()
    }

    // MARK: - Directory Path Tests

    func testDocumentsDirectory_returnsCorrectPath() {
        XCTAssertEqual(sut.documentsDirectory.path, "/mock/documents")
    }

    func testVideosDirectory_appendsVideosToDocuments() {
        XCTAssertEqual(sut.videosDirectory.path, "/mock/documents/videos")
    }

    func testTempDirectory_appendsTempToDocuments() {
        XCTAssertEqual(sut.tempDirectory.path, "/mock/documents/temp")
    }

    func testThumbnailsDirectory_appendsThumbnailsToDocuments() {
        XCTAssertEqual(sut.thumbnailsDirectory.path, "/mock/documents/thumbnails")
    }

    // MARK: - Video Directory Tests

    func testVideoDirectory_returnsCorrectPath() {
        let videoID = UUID()
        let expected = "/mock/documents/videos/\(videoID.uuidString)"
        XCTAssertEqual(sut.videoDirectory(for: videoID).path, expected)
    }

    func testVideoFilePath_returnsCorrectPathWithExtension() {
        let videoID = UUID()
        let path = sut.videoFilePath(for: videoID, extension: "mp4")
        XCTAssertTrue(path.path.contains(videoID.uuidString))
        XCTAssertTrue(path.path.hasSuffix("video.mp4"))
    }

    func testVideoFilePath_defaultsToMP4() {
        let videoID = UUID()
        let path = sut.videoFilePath(for: videoID)
        XCTAssertTrue(path.path.hasSuffix("video.mp4"))
    }

    func testThumbnailPath_returnsCorrectPath() {
        let videoID = UUID()
        let path = sut.thumbnailPath(for: videoID)
        XCTAssertTrue(path.path.contains(videoID.uuidString))
        XCTAssertTrue(path.path.hasSuffix("thumbnail.jpg"))
    }

    func testSubtitlePath_returnsCorrectPath() {
        let videoID = UUID()
        let path = sut.subtitlePath(for: videoID)
        XCTAssertTrue(path.path.contains(videoID.uuidString))
        XCTAssertTrue(path.path.hasSuffix("subtitles.vtt"))
    }

    // MARK: - Temp Directory Tests

    func testTempDirectoryForDownload_returnsCorrectPath() {
        let downloadID = UUID()
        let expected = "/mock/documents/temp/\(downloadID.uuidString)"
        XCTAssertEqual(sut.tempDirectory(for: downloadID).path, expected)
    }

    func testSegmentsDirectory_returnsCorrectPath() {
        let downloadID = UUID()
        let path = sut.segmentsDirectory(for: downloadID)
        XCTAssertTrue(path.path.contains(downloadID.uuidString))
        XCTAssertTrue(path.path.hasSuffix("segments"))
    }

    func testSegmentPath_forTSSegment_returnsCorrectPath() {
        let downloadID = UUID()
        let path = sut.segmentPath(for: downloadID, index: 5, isFMP4: false)
        XCTAssertTrue(path.path.hasSuffix("segment_5.ts"))
    }

    func testSegmentPath_forFMP4Segment_returnsCorrectPath() {
        let downloadID = UUID()
        let path = sut.segmentPath(for: downloadID, index: 5, isFMP4: true)
        XCTAssertTrue(path.path.hasSuffix("segment_5.m4s"))
    }

    func testInitSegmentPath_returnsCorrectPath() {
        let downloadID = UUID()
        let path = sut.initSegmentPath(for: downloadID)
        XCTAssertTrue(path.path.hasSuffix("init.mp4"))
    }

    // MARK: - Directory Creation Tests

    func testCreateVideoDirectory_createsDirectory() throws {
        let videoID = UUID()
        _ = try sut.createVideoDirectory(for: videoID)

        XCTAssertEqual(mockFileManager.createdDirectories.count, 4) // 3 from init + 1 video dir
        XCTAssertTrue(mockFileManager.createdDirectories.last?.path.contains(videoID.uuidString) ?? false)
    }

    func testCreateTempDirectory_createsSegmentsDirectory() throws {
        let downloadID = UUID()
        _ = try sut.createTempDirectory(for: downloadID)

        let lastCreated = mockFileManager.createdDirectories.last
        XCTAssertNotNil(lastCreated)
        XCTAssertTrue(lastCreated?.path.contains(downloadID.uuidString) ?? false)
        XCTAssertTrue(lastCreated?.path.contains("segments") ?? false)
    }

    func testCreateVideoDirectory_throwsOnError() {
        mockFileManager.shouldThrowOnCreateDirectory = true

        XCTAssertThrowsError(try sut.createVideoDirectory(for: UUID()))
    }

    // MARK: - File Operations Tests

    func testMoveFile_movesFileCorrectly() throws {
        let source = URL(fileURLWithPath: "/source/file.mp4")
        let destination = URL(fileURLWithPath: "/destination/file.mp4")

        try sut.moveFile(from: source, to: destination)

        XCTAssertEqual(mockFileManager.movedItems.count, 1)
        XCTAssertEqual(mockFileManager.movedItems.first?.from, source)
        XCTAssertEqual(mockFileManager.movedItems.first?.to, destination)
    }

    func testMoveFile_removesExistingDestination() throws {
        let source = URL(fileURLWithPath: "/source/file.mp4")
        let destination = URL(fileURLWithPath: "/destination/file.mp4")
        mockFileManager.addExistingFile(at: destination.path)

        try sut.moveFile(from: source, to: destination)

        XCTAssertTrue(mockFileManager.removedItems.contains(destination))
    }

    func testCopyFile_copiesFileCorrectly() throws {
        let source = URL(fileURLWithPath: "/source/file.mp4")
        let destination = URL(fileURLWithPath: "/destination/file.mp4")

        try sut.copyFile(from: source, to: destination)

        XCTAssertEqual(mockFileManager.copiedItems.count, 1)
        XCTAssertEqual(mockFileManager.copiedItems.first?.from, source)
        XCTAssertEqual(mockFileManager.copiedItems.first?.to, destination)
    }

    func testCopyFile_removesExistingDestination() throws {
        let source = URL(fileURLWithPath: "/source/file.mp4")
        let destination = URL(fileURLWithPath: "/destination/file.mp4")
        mockFileManager.addExistingFile(at: destination.path)

        try sut.copyFile(from: source, to: destination)

        XCTAssertTrue(mockFileManager.removedItems.contains(destination))
    }

    func testCopyDirectory_copiesDirectoryCorrectly() throws {
        let source = URL(fileURLWithPath: "/source/dir")
        let destination = URL(fileURLWithPath: "/destination/dir")

        try sut.copyDirectory(from: source, to: destination)

        XCTAssertEqual(mockFileManager.copiedItems.count, 1)
    }

    func testMoveFile_throwsOnError() {
        mockFileManager.shouldThrowOnMove = true
        let source = URL(fileURLWithPath: "/source/file.mp4")
        let destination = URL(fileURLWithPath: "/destination/file.mp4")

        XCTAssertThrowsError(try sut.moveFile(from: source, to: destination))
    }

    func testCopyFile_throwsOnError() {
        mockFileManager.shouldThrowOnCopy = true
        let source = URL(fileURLWithPath: "/source/file.mp4")
        let destination = URL(fileURLWithPath: "/destination/file.mp4")

        XCTAssertThrowsError(try sut.copyFile(from: source, to: destination))
    }

    // MARK: - File Existence Tests

    func testFileExists_returnsTrueForExistingFile() {
        let url = URL(fileURLWithPath: "/existing/file.mp4")
        mockFileManager.addExistingFile(at: url.path)

        XCTAssertTrue(sut.fileExists(at: url))
    }

    func testFileExists_returnsFalseForNonExistingFile() {
        let url = URL(fileURLWithPath: "/nonexisting/file.mp4")

        XCTAssertFalse(sut.fileExists(at: url))
    }

    // MARK: - File Size Tests

    func testFileSize_returnsCorrectSize() {
        let url = URL(fileURLWithPath: "/existing/file.mp4")
        mockFileManager.addExistingFile(at: url.path, size: 1_000_000)

        let size = sut.fileSize(at: url)
        XCTAssertEqual(size, 1_000_000)
    }

    func testFileSize_returnsNilForNonExistingFile() {
        let url = URL(fileURLWithPath: "/nonexisting/file.mp4")

        let size = sut.fileSize(at: url)
        XCTAssertNil(size)
    }

    // MARK: - Cleanup Tests

    func testDeleteVideoFiles_removesVideoDirectory() {
        let video = TestFixtures.makeVideo()

        sut.deleteVideoFiles(for: video)

        XCTAssertEqual(mockFileManager.removedItems.count, 1)
        XCTAssertTrue(mockFileManager.removedItems.first?.path.contains(video.id.uuidString) ?? false)
    }

    func testDeleteTempFiles_removesTempDirectory() {
        let download = TestFixtures.makeDownload()

        sut.deleteTempFiles(for: download)

        XCTAssertEqual(mockFileManager.removedItems.count, 1)
        XCTAssertTrue(mockFileManager.removedItems.first?.path.contains(download.id.uuidString) ?? false)
    }

    func testDeleteAllTempFiles_removesTempAndRecreates() {
        sut.deleteAllTempFiles()

        XCTAssertTrue(mockFileManager.removedItems.contains(sut.tempDirectory))
        // Should also recreate
        XCTAssertTrue(mockFileManager.createdDirectories.contains(sut.tempDirectory))
    }

    func testDeleteAllVideos_removesVideosAndRecreates() {
        sut.deleteAllVideos()

        XCTAssertTrue(mockFileManager.removedItems.contains(sut.videosDirectory))
        // Should also recreate
        XCTAssertTrue(mockFileManager.createdDirectories.contains(sut.videosDirectory))
    }

    // MARK: - Segment Listing Tests

    func testListSegments_returnsTSSegments() {
        let downloadID = UUID()
        let segmentsDir = sut.segmentsDirectory(for: downloadID)

        // Add mock segments
        let seg0 = segmentsDir.appendingPathComponent("segment_0.ts")
        let seg1 = segmentsDir.appendingPathComponent("segment_1.ts")
        let other = segmentsDir.appendingPathComponent("init.mp4")
        mockFileManager.directoryContents[segmentsDir] = [seg0, seg1, other]

        let segments = sut.listSegments(for: downloadID)

        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments.allSatisfy { $0.pathExtension == "ts" })
    }

    func testListSegments_returnsM4SSegments() {
        let downloadID = UUID()
        let segmentsDir = sut.segmentsDirectory(for: downloadID)

        let seg0 = segmentsDir.appendingPathComponent("segment_0.m4s")
        let seg1 = segmentsDir.appendingPathComponent("segment_1.m4s")
        mockFileManager.directoryContents[segmentsDir] = [seg0, seg1]

        let segments = sut.listSegments(for: downloadID)

        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments.allSatisfy { $0.pathExtension == "m4s" })
    }

    func testSegmentCount_returnsCorrectCount() {
        let downloadID = UUID()
        let segmentsDir = sut.segmentsDirectory(for: downloadID)

        let segments = (0..<5).map { segmentsDir.appendingPathComponent("segment_\($0).ts") }
        mockFileManager.directoryContents[segmentsDir] = segments

        XCTAssertEqual(sut.segmentCount(for: downloadID), 5)
    }

    func testSegmentCount_returnsZeroForEmptyDirectory() {
        let downloadID = UUID()

        XCTAssertEqual(sut.segmentCount(for: downloadID), 0)
    }

    // MARK: - Directory Structure Creation Tests

    func testInit_createsRequiredDirectories() {
        // MockFileManager was passed to sut in setUp, init already ran
        // Check that videos, temp, and thumbnails directories were created
        let createdPaths = mockFileManager.createdDirectories.map { $0.path }

        XCTAssertTrue(createdPaths.contains("/mock/documents/videos"))
        XCTAssertTrue(createdPaths.contains("/mock/documents/temp"))
        XCTAssertTrue(createdPaths.contains("/mock/documents/thumbnails"))
    }

    func testInit_skipsExistingDirectories() {
        // Create a new file manager with pre-existing directories
        let newMockFileManager = MockFileManager()
        newMockFileManager.documentsURL = URL(fileURLWithPath: "/mock/documents")
        newMockFileManager.addExistingDirectory(at: "/mock/documents/videos")
        newMockFileManager.addExistingDirectory(at: "/mock/documents/temp")
        newMockFileManager.addExistingDirectory(at: "/mock/documents/thumbnails")

        _ = FileStorageManager(fileManager: newMockFileManager)

        // Should not create any directories since they already exist
        XCTAssertTrue(newMockFileManager.createdDirectories.isEmpty)
    }
}
