import Foundation
import AVFoundation
@testable import OfflineBrowser

final class MockFileStorageManager: FileStorageManagerProtocol {

    // MARK: - Tracking

    private(set) var createdVideoDirectories: [UUID] = []
    private(set) var createdTempDirectories: [UUID] = []
    private(set) var deletedVideos: [Video] = []
    private(set) var deletedDownloads: [Download] = []
    private(set) var movedFiles: [(from: URL, to: URL)] = []
    private(set) var copiedFiles: [(from: URL, to: URL)] = []
    private(set) var copiedDirectories: [(from: URL, to: URL)] = []

    // MARK: - Configurable State

    var mockDocumentsDirectory = URL(fileURLWithPath: "/mock/documents")
    var existingFiles: Set<URL> = []
    var fileSizes: [URL: Int64] = [:]
    var mockSegments: [UUID: [URL]] = [:]

    // Convenience properties for tests
    var fileExistsResult: Bool = false
    var fileSizeResult: Int64 = 0

    // MARK: - Error Simulation

    var shouldThrowOnCreateVideoDirectory = false
    var shouldThrowOnCreateTempDirectory = false
    var shouldThrowOnMove = false
    var shouldThrowOnCopy = false

    // MARK: - Directory Paths

    var documentsDirectory: URL {
        mockDocumentsDirectory
    }

    var videosDirectory: URL {
        mockDocumentsDirectory.appendingPathComponent("videos")
    }

    var tempDirectory: URL {
        mockDocumentsDirectory.appendingPathComponent("temp")
    }

    var thumbnailsDirectory: URL {
        mockDocumentsDirectory.appendingPathComponent("thumbnails")
    }

    // MARK: - Video Storage

    func videoDirectory(for videoID: UUID) -> URL {
        videosDirectory.appendingPathComponent(videoID.uuidString)
    }

    func createVideoDirectory(for videoID: UUID) throws -> URL {
        if shouldThrowOnCreateVideoDirectory {
            throw NSError(domain: "MockFileStorageManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create video directory"])
        }
        createdVideoDirectories.append(videoID)
        return videoDirectory(for: videoID)
    }

    func videoFilePath(for videoID: UUID, extension fileExtension: String) -> URL {
        videoDirectory(for: videoID).appendingPathComponent("video.\(fileExtension)")
    }

    func thumbnailPath(for videoID: UUID) -> URL {
        videoDirectory(for: videoID).appendingPathComponent("thumbnail.jpg")
    }

    func subtitlePath(for videoID: UUID) -> URL {
        videoDirectory(for: videoID).appendingPathComponent("subtitles.vtt")
    }

    // MARK: - Temp Storage

    func tempDirectory(for downloadID: UUID) -> URL {
        tempDirectory.appendingPathComponent(downloadID.uuidString)
    }

    func segmentsDirectory(for downloadID: UUID) -> URL {
        tempDirectory(for: downloadID).appendingPathComponent("segments")
    }

    func createTempDirectory(for downloadID: UUID) throws -> URL {
        if shouldThrowOnCreateTempDirectory {
            throw NSError(domain: "MockFileStorageManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create temp directory"])
        }
        createdTempDirectories.append(downloadID)
        return segmentsDirectory(for: downloadID)
    }

    func segmentPath(for downloadID: UUID, index: Int, isFMP4: Bool) -> URL {
        let ext = isFMP4 ? "m4s" : "ts"
        return segmentsDirectory(for: downloadID).appendingPathComponent("segment_\(index).\(ext)")
    }

    func initSegmentPath(for downloadID: UUID) -> URL {
        segmentsDirectory(for: downloadID).appendingPathComponent("init.mp4")
    }

    // MARK: - Cleanup

    func deleteVideoFiles(for video: Video) {
        deletedVideos.append(video)
    }

    func deleteTempFiles(for download: Download) {
        deletedDownloads.append(download)
    }

    func deleteAllTempFiles() {
        // No-op for mock
    }

    func deleteAllVideos() {
        // No-op for mock
    }

    // MARK: - Storage Calculation

    private var mockTotalStorageUsed: Int64 = 0
    private var mockTempStorageUsed: Int64 = 0

    func totalStorageUsed() -> Int64 {
        mockTotalStorageUsed
    }

    func tempStorageUsed() -> Int64 {
        mockTempStorageUsed
    }

    var formattedTotalStorageUsed: String {
        ByteCountFormatter.string(fromByteCount: mockTotalStorageUsed, countStyle: .file)
    }

    func setMockStorageUsed(total: Int64, temp: Int64 = 0) {
        mockTotalStorageUsed = total
        mockTempStorageUsed = temp
    }

    // MARK: - File Operations

    func moveFile(from source: URL, to destination: URL) throws {
        if shouldThrowOnMove {
            throw NSError(domain: "MockFileStorageManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to move file"])
        }
        movedFiles.append((from: source, to: destination))
        existingFiles.remove(source)
        existingFiles.insert(destination)
    }

    func copyFile(from source: URL, to destination: URL) throws {
        if shouldThrowOnCopy {
            throw NSError(domain: "MockFileStorageManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to copy file"])
        }
        copiedFiles.append((from: source, to: destination))
        existingFiles.insert(destination)
    }

    func copyDirectory(from source: URL, to destination: URL) throws {
        if shouldThrowOnCopy {
            throw NSError(domain: "MockFileStorageManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to copy directory"])
        }
        copiedDirectories.append((from: source, to: destination))
    }

    func fileExists(at url: URL) -> Bool {
        // Use the convenience property if set, otherwise check the set
        if fileExistsResult {
            return true
        }
        return existingFiles.contains(url)
    }

    func fileSize(at url: URL) -> Int64? {
        // Use the convenience property if set, otherwise check the dictionary
        if fileSizeResult > 0 {
            return fileSizeResult
        }
        return fileSizes[url]
    }

    private(set) var removedFiles: [URL] = []

    func removeFile(at url: URL) throws {
        removedFiles.append(url)
        existingFiles.remove(url)
        fileSizes.removeValue(forKey: url)
    }

    // MARK: - Segment Management

    func listSegments(for downloadID: UUID) -> [URL] {
        mockSegments[downloadID] ?? []
    }

    func segmentCount(for downloadID: UUID) -> Int {
        mockSegments[downloadID]?.count ?? 0
    }

    // MARK: - Thumbnail Generation

    func generateThumbnail(from videoURL: URL, at time: CMTime) -> URL? {
        // Return a mock thumbnail URL
        thumbnailsDirectory.appendingPathComponent("mock_thumbnail.jpg")
    }

    // MARK: - Helpers

    func reset() {
        createdVideoDirectories.removeAll()
        createdTempDirectories.removeAll()
        deletedVideos.removeAll()
        deletedDownloads.removeAll()
        movedFiles.removeAll()
        copiedFiles.removeAll()
        copiedDirectories.removeAll()
        removedFiles.removeAll()
        existingFiles.removeAll()
        fileSizes.removeAll()
        mockSegments.removeAll()
        mockTotalStorageUsed = 0
        mockTempStorageUsed = 0
        shouldThrowOnCreateVideoDirectory = false
        shouldThrowOnCreateTempDirectory = false
        shouldThrowOnMove = false
        shouldThrowOnCopy = false
    }

    func addExistingFile(at url: URL, size: Int64 = 0) {
        existingFiles.insert(url)
        fileSizes[url] = size
    }

    func addMockSegments(for downloadID: UUID, count: Int, isFMP4: Bool = false) {
        var segments: [URL] = []
        for i in 0..<count {
            segments.append(segmentPath(for: downloadID, index: i, isFMP4: isFMP4))
        }
        mockSegments[downloadID] = segments
    }
}
