import Foundation
import AVFoundation

final class FileStorageManager {
    static let shared = FileStorageManager()

    // MARK: - Dependencies

    private let fileManager: FileManagerProtocol

    // MARK: - Initialization

    init(fileManager: FileManagerProtocol = FileManager.default) {
        self.fileManager = fileManager
        createDirectoryStructure()
    }

    // MARK: - Directory Paths

    var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var videosDirectory: URL {
        documentsDirectory.appendingPathComponent("videos")
    }

    var tempDirectory: URL {
        documentsDirectory.appendingPathComponent("temp")
    }

    var thumbnailsDirectory: URL {
        documentsDirectory.appendingPathComponent("thumbnails")
    }

    // MARK: - Directory Setup

    private func createDirectoryStructure() {
        let directories = [videosDirectory, tempDirectory, thumbnailsDirectory]

        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Video Storage

    func videoDirectory(for videoID: UUID) -> URL {
        videosDirectory.appendingPathComponent(videoID.uuidString)
    }

    func createVideoDirectory(for videoID: UUID) throws -> URL {
        let directory = videoDirectory(for: videoID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func videoFilePath(for videoID: UUID, extension fileExtension: String = "mp4") -> URL {
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
        let directory = segmentsDirectory(for: downloadID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func segmentPath(for downloadID: UUID, index: Int, isFMP4: Bool = false) -> URL {
        let ext = isFMP4 ? "m4s" : "ts"
        return segmentsDirectory(for: downloadID).appendingPathComponent("segment_\(index).\(ext)")
    }

    func initSegmentPath(for downloadID: UUID) -> URL {
        segmentsDirectory(for: downloadID).appendingPathComponent("init.mp4")
    }

    // MARK: - Cleanup

    func deleteVideoFiles(for video: Video) {
        let directory = videoDirectory(for: video.id)
        try? fileManager.removeItem(at: directory)
    }

    func deleteTempFiles(for download: Download) {
        let directory = tempDirectory(for: download.id)
        try? fileManager.removeItem(at: directory)
    }

    func deleteAllTempFiles() {
        try? fileManager.removeItem(at: tempDirectory)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    func deleteAllVideos() {
        try? fileManager.removeItem(at: videosDirectory)
        try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Storage Calculation

    func totalStorageUsed() -> Int64 {
        calculateDirectorySize(videosDirectory)
    }

    func tempStorageUsed() -> Int64 {
        calculateDirectorySize(tempDirectory)
    }

    private func calculateDirectorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let fileAttributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = fileAttributes.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    var formattedTotalStorageUsed: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsed(), countStyle: .file)
    }

    // MARK: - File Operations

    func moveFile(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    func copyFile(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    func copyDirectory(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    // MARK: - Segment Management

    func listSegments(for downloadID: UUID) -> [URL] {
        let directory = segmentsDirectory(for: downloadID)
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        // Support both .ts and .m4s segment extensions
        return files.filter { $0.pathExtension == "ts" || $0.pathExtension == "m4s" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func segmentCount(for downloadID: UUID) -> Int {
        listSegments(for: downloadID).count
    }

    // MARK: - Thumbnail Generation

    func generateThumbnail(from videoURL: URL, at time: CMTime = CMTime(seconds: 1, preferredTimescale: 1)) -> URL? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 400)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)

            guard let data = uiImage.jpegData(compressionQuality: 0.8) else {
                return nil
            }

            let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: thumbnailURL)

            return thumbnailURL
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }
}

import UIKit
