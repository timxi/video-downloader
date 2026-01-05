import Foundation
import WebKit
import Combine

final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var activeDownload: Download?
    @Published private(set) var downloadQueue: [Download] = []

    private var currentTask: DownloadTask?
    private var cancellables = Set<AnyCancellable>()

    // Store cookies for each download by download ID
    private var downloadCookies: [UUID: [HTTPCookie]] = [:]

    var hasPendingDownloads: Bool {
        !downloadQueue.isEmpty || activeDownload != nil
    }

    private init() {
        loadPendingDownloads()
    }

    // MARK: - Public Methods

    func startDownload(stream: DetectedStream, pageTitle: String?, pageURL: URL?, webView: WKWebView) {
        NSLog("[DownloadManager] startDownload called for stream: %@", stream.url)

        guard URL(string: stream.url) != nil else {
            NSLog("[DownloadManager] ERROR: Invalid stream URL")
            return
        }

        // Get ALL cookies from WebView - the CDN domain may need cookies from the main page
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            NSLog("[DownloadManager] Got %d total cookies from WebView", cookies.count)

            // Log cookie domains for debugging
            let domains = Set(cookies.map { $0.domain })
            NSLog("[DownloadManager] Cookie domains: %@", domains.joined(separator: ", "))

            // Store all cookies in HTTPCookieStorage
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }

            self?.createAndQueueDownload(stream: stream, pageTitle: pageTitle, pageURL: pageURL, cookies: cookies)
        }
    }

    func pauseAllDownloads() {
        currentTask?.pause()
        if var download = activeDownload {
            download.status = .paused
            try? DownloadRepository.shared.update(download)
        }
    }

    func resumePendingDownloads(completion: ((Bool) -> Void)?) {
        processNextDownload()
        completion?(true)
    }

    func retryDownload(_ download: Download) {
        do {
            try DownloadRepository.shared.resetForRetry(download)
            loadPendingDownloads()
            processNextDownload()
        } catch {
            print("Failed to retry download: \(error)")
        }
    }

    func cancelDownload(_ download: Download) {
        if activeDownload?.id == download.id {
            currentTask?.cancel()
            currentTask = nil
            activeDownload = nil
        }

        try? DownloadRepository.shared.delete(download)
        downloadQueue.removeAll { $0.id == download.id }

        processNextDownload()
    }

    // MARK: - Private Methods

    private func createAndQueueDownload(stream: DetectedStream, pageTitle: String?, pageURL: URL?, cookies: [HTTPCookie]) {
        guard let url = URL(string: stream.url) else { return }

        let download = Download(
            videoURL: stream.url,
            manifestURL: stream.type == .hls ? stream.url : nil,
            pageTitle: pageTitle,
            pageURL: pageURL?.absoluteString,
            sourceDomain: url.host,
            quality: stream.qualities?.first?.resolution
        )

        print("[DownloadManager] Creating download with \(cookies.count) cookies for domain: \(url.host ?? "unknown")")

        do {
            try DownloadRepository.shared.save(download)
            downloadQueue.append(download)

            // Store cookies for this download
            downloadCookies[download.id] = cookies

            // Notify user
            NotificationManager.shared.showDownloadStarted(title: pageTitle ?? "Video")

            // Start processing if no active download
            if activeDownload == nil {
                processNextDownload()
            }
        } catch {
            print("Failed to save download: \(error)")
        }
    }

    private func loadPendingDownloads() {
        do {
            downloadQueue = try DownloadRepository.shared.fetchPending()
            if let active = try DownloadRepository.shared.fetchActive().first {
                activeDownload = active
            }
        } catch {
            print("Failed to load pending downloads: \(error)")
        }
    }

    private func processNextDownload() {
        NSLog("[DownloadManager] processNextDownload called. Queue size: %d, activeDownload: %@", downloadQueue.count, activeDownload == nil ? "nil" : "exists")
        guard activeDownload == nil, let next = downloadQueue.first else {
            NSLog("[DownloadManager] Skipping - either active download exists or queue is empty")
            return
        }

        NSLog("[DownloadManager] Starting next download: %@", next.videoURL)
        activeDownload = next
        downloadQueue.removeFirst()

        // Update status
        do {
            try DownloadRepository.shared.updateStatus(next, to: .downloading)
        } catch {
            NSLog("[DownloadManager] Failed to update download status: %@", error.localizedDescription)
        }

        // Get cookies for this download
        let cookies = downloadCookies[next.id] ?? []
        NSLog("[DownloadManager] Starting download task with %d cookies", cookies.count)

        // Create download task with cookies
        currentTask = DownloadTask(download: next, cookies: cookies)
        currentTask?.delegate = self
        currentTask?.start()
    }

    private func completeDownload(_ download: Download, videoURL: URL) {
        // Create video entry
        let videoID = UUID()

        print("[DownloadManager] Completing download, source: \(videoURL.path)")

        do {
            // Verify source file exists
            guard FileStorageManager.shared.fileExists(at: videoURL) else {
                throw NSError(domain: "DownloadManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Downloaded file not found at \(videoURL.path)"])
            }

            print("[DownloadManager] Source file exists, size: \(FileStorageManager.shared.fileSize(at: videoURL) ?? 0) bytes")

            // Move video to permanent location
            let videoDir = try FileStorageManager.shared.createVideoDirectory(for: videoID)
            let fileExtension = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
            var destinationURL: URL
            var relativePath: String

            // Single video file
            destinationURL = videoDir.appendingPathComponent("video.\(fileExtension)")
            try FileStorageManager.shared.copyFile(from: videoURL, to: destinationURL)
            relativePath = "videos/\(videoID.uuidString)/video.\(fileExtension)"
            print("[DownloadManager] Copied to: \(destinationURL.path)")

            // Generate thumbnail
            let thumbnailURL = FileStorageManager.shared.generateThumbnail(from: destinationURL)

            // Get video duration
            let duration = getVideoDuration(url: destinationURL)

            // Get file size
            let fileSize = FileStorageManager.shared.fileSize(at: destinationURL) ?? 0

            print("[DownloadManager] Duration: \(duration)s, Size: \(fileSize) bytes")

            // Create or get folder
            let folder: Folder?
            if let domain = download.sourceDomain {
                folder = try FolderRepository.shared.fetchOrCreateAutoFolder(for: domain)
                print("[DownloadManager] Created/found folder for domain: \(domain)")
            } else {
                folder = nil
            }

            // Create video record
            let video = Video(
                id: videoID,
                title: download.pageTitle ?? "Downloaded Video",
                sourceURL: download.videoURL,
                sourceDomain: download.sourceDomain ?? "unknown",
                filePath: relativePath,
                thumbnailPath: thumbnailURL.map { "thumbnails/\($0.lastPathComponent)" },
                duration: duration,
                fileSize: fileSize,
                quality: download.quality ?? "unknown",
                folderID: folder?.id
            )

            try VideoRepository.shared.save(video)
            print("[DownloadManager] Video saved to database: \(video.id)")

            // Mark download as completed and remove
            try DownloadRepository.shared.updateStatus(download, to: .completed)
            try DownloadRepository.shared.delete(download)

            // Clean up temp files
            FileStorageManager.shared.deleteTempFiles(for: download)

            // Notify
            NotificationManager.shared.showDownloadCompleted(title: video.title)

            print("[DownloadManager] Download completed successfully!")

        } catch {
            print("[DownloadManager] ERROR: Failed to complete download: \(error)")
            try? DownloadRepository.shared.markFailed(download, error: error.localizedDescription)
        }

        activeDownload = nil
        currentTask = nil
        processNextDownload()
    }

    private func getVideoDuration(url: URL) -> Int {
        let asset = AVAsset(url: url)

        // For TS files, we need to load duration asynchronously
        // But for simplicity, we'll try to load it synchronously with a timeout
        let semaphore = DispatchSemaphore(value: 0)
        var duration: Double = 0

        asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)

            if status == .loaded {
                duration = CMTimeGetSeconds(asset.duration)
                print("[DownloadManager] Loaded duration: \(duration) seconds")
            } else {
                print("[DownloadManager] Failed to load duration: \(error?.localizedDescription ?? "unknown")")
            }
            semaphore.signal()
        }

        // Wait up to 5 seconds for duration to load
        _ = semaphore.wait(timeout: .now() + 5)

        // If duration is invalid, try to estimate from file size
        if !duration.isFinite || duration <= 0 {
            print("[DownloadManager] Duration invalid, returning 0")
            return 0
        }

        return Int(duration)
    }
}

// MARK: - DownloadTaskDelegate

extension DownloadManager: DownloadTaskDelegate {
    func downloadTask(_ task: DownloadTask, didUpdateProgress progress: Double, segmentsDownloaded: Int) {
        guard var download = activeDownload else { return }
        download.progress = progress
        download.segmentsDownloaded = segmentsDownloaded
        activeDownload = download

        try? DownloadRepository.shared.updateProgress(download, progress: progress, segmentsDownloaded: segmentsDownloaded)
    }

    func downloadTask(_ task: DownloadTask, didCompleteWithURL url: URL) {
        guard let download = activeDownload else { return }
        completeDownload(download, videoURL: url)
    }

    func downloadTask(_ task: DownloadTask, didFailWithError error: Error) {
        guard let download = activeDownload else { return }

        try? DownloadRepository.shared.markFailed(download, error: error.localizedDescription)
        NotificationManager.shared.showDownloadFailed(title: download.pageTitle ?? "Video")

        activeDownload = nil
        currentTask = nil

        // Check if we should retry
        if download.canRetry {
            DispatchQueue.main.asyncAfter(deadline: .now() + RetryPolicy.delay(for: download.retryCount)) { [weak self] in
                self?.retryDownload(download)
            }
        } else {
            processNextDownload()
        }
    }
}

import AVFoundation
