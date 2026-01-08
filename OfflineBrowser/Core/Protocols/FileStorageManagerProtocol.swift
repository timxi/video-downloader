import Foundation
import AVFoundation

protocol FileStorageManagerProtocol {
    // MARK: - Directory Paths
    var documentsDirectory: URL { get }
    var videosDirectory: URL { get }
    var tempDirectory: URL { get }
    var thumbnailsDirectory: URL { get }

    // MARK: - Video Storage
    func videoDirectory(for videoID: UUID) -> URL
    func createVideoDirectory(for videoID: UUID) throws -> URL
    func videoFilePath(for videoID: UUID, extension fileExtension: String) -> URL
    func thumbnailPath(for videoID: UUID) -> URL
    func subtitlePath(for videoID: UUID) -> URL

    // MARK: - Temp Storage
    func tempDirectory(for downloadID: UUID) -> URL
    func segmentsDirectory(for downloadID: UUID) -> URL
    func createTempDirectory(for downloadID: UUID) throws -> URL
    func segmentPath(for downloadID: UUID, index: Int, isFMP4: Bool) -> URL
    func initSegmentPath(for downloadID: UUID) -> URL

    // MARK: - Cleanup
    func deleteVideoFiles(for video: Video)
    func deleteTempFiles(for download: Download)
    func deleteAllTempFiles()
    func deleteAllVideos()

    // MARK: - Storage Calculation
    func totalStorageUsed() -> Int64
    func tempStorageUsed() -> Int64
    var formattedTotalStorageUsed: String { get }

    // MARK: - File Operations
    func moveFile(from source: URL, to destination: URL) throws
    func copyFile(from source: URL, to destination: URL) throws
    func copyDirectory(from source: URL, to destination: URL) throws
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) -> Int64?
    func removeFile(at url: URL) throws

    // MARK: - Segment Management
    func listSegments(for downloadID: UUID) -> [URL]
    func segmentCount(for downloadID: UUID) -> Int

    // MARK: - Thumbnail Generation
    func generateThumbnail(from videoURL: URL, at time: CMTime) -> URL?
}

// MARK: - Default Parameter Values

extension FileStorageManagerProtocol {
    func videoFilePath(for videoID: UUID) -> URL {
        videoFilePath(for: videoID, extension: "mp4")
    }

    func segmentPath(for downloadID: UUID, index: Int) -> URL {
        segmentPath(for: downloadID, index: index, isFMP4: false)
    }

    func generateThumbnail(from videoURL: URL) -> URL? {
        generateThumbnail(from: videoURL, at: CMTime(seconds: 1, preferredTimescale: 1))
    }
}

// MARK: - FileStorageManager Conformance

extension FileStorageManager: FileStorageManagerProtocol {}
