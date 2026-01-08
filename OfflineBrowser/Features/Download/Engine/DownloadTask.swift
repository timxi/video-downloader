import Foundation
import os.log

private let logger = Logger(subsystem: "com.offlinebrowser.app", category: "DownloadTask")

// MARK: - Download Task Protocol

protocol DownloadTaskProtocol: AnyObject {
    var delegate: DownloadTaskDelegate? { get set }
    var download: Download { get }
    func start()
    func pause()
    func resume()
    func cancel()
}

protocol DownloadTaskDelegate: AnyObject {
    func downloadTask(_ task: DownloadTaskProtocol, didUpdateProgress progress: Double, segmentsDownloaded: Int)
    func downloadTask(_ task: DownloadTaskProtocol, didCompleteWithURL url: URL)
    func downloadTask(_ task: DownloadTaskProtocol, didFailWithError error: Error)
}

final class DownloadTask: DownloadTaskProtocol {

    // MARK: - Properties

    weak var delegate: DownloadTaskDelegate?

    let download: Download
    private let cookies: [HTTPCookie]
    private let hlsParser = HLSParser()
    private var segments: [HLSSegment] = []
    private var downloadedSegments: [URL] = []
    private var encryptionKeyData: Data?

    private var isCancelled = false
    private var isPaused = false

    private var currentSegmentIndex = 0

    // fMP4/CMAF support
    private var isFMP4 = false
    private var initSegmentURL: String?
    private var initSegmentByteRange: String?  // e.g., "1234@0" means 1234 bytes at offset 0

    enum TaskError: Error {
        case cancelled
        case invalidURL
        case noSegments
        case muxingFailed
        case networkError(Error)
    }

    // MARK: - Initialization

    init(download: Download, cookies: [HTTPCookie] = []) {
        self.download = download
        self.cookies = cookies
    }

    // YouTube iOS client User-Agent (must match what was used to get the HLS manifest)
    private static let youtubeIOSUserAgent = "com.google.ios.youtube/20.03.02 (iPhone16,2; U; CPU iOS 18_2_1 like Mac OS X;)"

    // Helper to create a request with cookies
    private func createRequest(for url: URL, referer: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60

        // Add cookies
        if !cookies.isEmpty {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
            logger.info("Added \(self.cookies.count) cookies to request")
        }

        // Detect if this is a YouTube/Google Video domain
        let host = url.host?.lowercased() ?? ""
        let isYouTubeDomain = host.contains("googlevideo.com") ||
                              host.contains("youtube.com") ||
                              host.contains("ytimg.com")

        // Use YouTube iOS client User-Agent for YouTube domains to match the original manifest request
        // This is critical because YouTube validates User-Agent consistency
        if isYouTubeDomain {
            request.setValue(Self.youtubeIOSUserAgent, forHTTPHeaderField: "User-Agent")
            // YouTube's video CDN expects specific Origin
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        } else {
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            // Add Referer and Origin for non-YouTube video servers
            if let referer = referer ?? download.pageURL {
                request.setValue(referer, forHTTPHeaderField: "Referer")
                if let refererURL = URL(string: referer), let scheme = refererURL.scheme, let host = refererURL.host {
                    request.setValue("\(scheme)://\(host)", forHTTPHeaderField: "Origin")
                }
            }
        }

        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        return request
    }

    // MARK: - Public Methods

    func start() {
        guard let url = URL(string: download.videoURL) else {
            delegate?.downloadTask(self, didFailWithError: TaskError.invalidURL)
            return
        }

        // Check if it's a direct video URL or HLS
        if download.manifestURL != nil {
            // HLS download
            startHLSDownload(manifestURL: url)
        } else {
            // Direct file download
            startDirectDownload(url: url)
        }
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
        downloadNextSegment()
    }

    func cancel() {
        isCancelled = true
    }

    // MARK: - HLS Download

    private func startHLSDownload(manifestURL: URL) {
        logger.info("Starting HLS download from: \(manifestURL.absoluteString)")
        logger.info("Using \(self.cookies.count) cookies")
        NSLog("[DownloadTask] Starting HLS download from: %@", manifestURL.absoluteString)
        NSLog("[DownloadTask] Using %d cookies", cookies.count)

        // Fetch manifest with cookies
        let request = createRequest(for: manifestURL)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                logger.error("Manifest fetch error: \(error.localizedDescription)")
                logger.error("Error domain: \(nsError.domain), code: \(nsError.code)")
                logger.error("Error userInfo: \(nsError.userInfo.description)")
                NSLog("[DownloadTask] Manifest fetch error: %@", error.localizedDescription)
                NSLog("[DownloadTask] Error domain: %@, code: %d", nsError.domain, nsError.code)
                self.delegate?.downloadTask(self, didFailWithError: error)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                logger.info("Manifest response status: \(httpResponse.statusCode)")
                NSLog("[DownloadTask] Manifest response status: %d", httpResponse.statusCode)
            }

            guard let data = data, let content = String(data: data, encoding: .utf8) else {
                logger.error("Failed to decode manifest")
                NSLog("[DownloadTask] ERROR: Failed to decode manifest data")
                self.delegate?.downloadTask(self, didFailWithError: TaskError.noSegments)
                return
            }

            // Check if it's HTML error page
            if content.contains("<!DOCTYPE") || content.contains("<html") {
                logger.error("Received HTML instead of manifest")
                NSLog("[DownloadTask] ERROR: Received HTML instead of manifest")
                self.delegate?.downloadTask(self, didFailWithError: TaskError.networkError(NSError(domain: "DownloadTask", code: -1, userInfo: [NSLocalizedDescriptionKey: "Received HTML error page instead of manifest"])))
                return
            }

            NSLog("[DownloadTask] Manifest fetched successfully, length: %d", content.count)
            logger.info("Manifest content (first 500 chars): \(String(content.prefix(500)))")

            self.hlsParser.parseManifest(content: content, baseURL: manifestURL) { result in
                self.handleManifestParseResult(result, manifestURL: manifestURL)
            }
        }.resume()
    }

    private func handleManifestParseResult(_ result: Result<HLSParsedInfo, HLSParser.ParseError>, manifestURL: URL) {
        guard !isCancelled else { return }

        switch result {
        case .success(let info):
            NSLog("[DownloadTask] Parsed HLS - qualities: %d, segments: %d", info.qualities.count, info.segments?.count ?? 0)

            // If master playlist, get the best quality variant
            if !info.qualities.isEmpty {
                let preferredQuality = PreferenceRepository.shared.preferredQuality
                if let quality = info.qualities.quality(matching: preferredQuality),
                   let variantURL = URL(string: quality.url) {
                    NSLog("[DownloadTask] Selected quality: %@ - %@", quality.resolution, variantURL.absoluteString)
                    startHLSDownload(manifestURL: variantURL)
                } else {
                    NSLog("[DownloadTask] ERROR: Invalid quality URL")
                    delegate?.downloadTask(self, didFailWithError: TaskError.invalidURL)
                }
            }
            // Media playlist
            else if let segments = info.segments, !segments.isEmpty {
                NSLog("[DownloadTask] Found %d segments to download", segments.count)
                self.segments = segments
                self.isFMP4 = info.isFMP4
                self.initSegmentURL = info.initSegmentURL
                self.initSegmentByteRange = info.initSegmentByteRange

                if info.isFMP4 {
                    NSLog("[DownloadTask] Stream uses fMP4 format (CMAF)")
                    if let byteRange = info.initSegmentByteRange {
                        NSLog("[DownloadTask] Init segment byte range: %@", byteRange)
                    }
                }

                // Download encryption key if needed
                if let keyURL = info.encryptionKeyURL, let url = URL(string: keyURL) {
                    NSLog("[DownloadTask] Downloading encryption key from: %@", keyURL)
                    downloadEncryptionKey(url: url) { [weak self] in
                        self?.downloadInitSegmentIfNeeded {
                            self?.startSegmentDownloads()
                        }
                    }
                } else {
                    downloadInitSegmentIfNeeded { [weak self] in
                        self?.startSegmentDownloads()
                    }
                }
            } else {
                NSLog("[DownloadTask] ERROR: No segments found in manifest")
                delegate?.downloadTask(self, didFailWithError: TaskError.noSegments)
            }

        case .failure(let error):
            NSLog("[DownloadTask] ERROR: Failed to parse HLS manifest: %@", String(describing: error))
            delegate?.downloadTask(self, didFailWithError: error)
        }
    }

    private func legacyStartHLSDownload(manifestURL: URL) {
        print("[DownloadTask] Starting legacy HLS download from: \(manifestURL)")

        hlsParser.parse(url: manifestURL) { [weak self] result in
            guard let self = self, !self.isCancelled else { return }

            switch result {
            case .success(let info):
                print("[DownloadTask] Parsed HLS - qualities: \(info.qualities.count), segments: \(info.segments?.count ?? 0)")

                // If master playlist, get the best quality variant
                if !info.qualities.isEmpty {
                    let preferredQuality = PreferenceRepository.shared.preferredQuality
                    if let quality = info.qualities.quality(matching: preferredQuality),
                       let variantURL = URL(string: quality.url) {
                        print("[DownloadTask] Selected quality: \(quality.resolution) - \(variantURL)")
                        self.startHLSDownload(manifestURL: variantURL)
                    } else {
                        self.delegate?.downloadTask(self, didFailWithError: TaskError.invalidURL)
                    }
                }
                // Media playlist
                else if let segments = info.segments, !segments.isEmpty {
                    print("[DownloadTask] Found \(segments.count) segments to download")
                    self.segments = segments

                    // Download encryption key if needed
                    if let keyURL = info.encryptionKeyURL, let url = URL(string: keyURL) {
                        print("[DownloadTask] Downloading encryption key from: \(keyURL)")
                        self.downloadEncryptionKey(url: url) { [weak self] in
                            self?.startSegmentDownloads()
                        }
                    } else {
                        self.startSegmentDownloads()
                    }
                } else {
                    print("[DownloadTask] ERROR: No segments found in manifest")
                    self.delegate?.downloadTask(self, didFailWithError: TaskError.noSegments)
                }

            case .failure(let error):
                print("[DownloadTask] ERROR: Failed to parse HLS manifest: \(error)")
                self.delegate?.downloadTask(self, didFailWithError: error)
            }
        }
    }

    private func downloadEncryptionKey(url: URL, completion: @escaping () -> Void) {
        let request = createRequest(for: url)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("[DownloadTask] Encryption key response status: \(httpResponse.statusCode)")
            }
            if let data = data {
                print("[DownloadTask] Downloaded encryption key: \(data.count) bytes")
                self?.encryptionKeyData = data
            }
            completion()
        }.resume()
    }

    private var initSegmentRetryCount = 0
    private let maxInitSegmentRetries = 3

    private func downloadInitSegmentIfNeeded(completion: @escaping () -> Void) {
        guard isFMP4, let initURLString = initSegmentURL, let initURL = URL(string: initURLString) else {
            // Not fMP4 or no init segment - proceed immediately
            completion()
            return
        }

        NSLog("[DownloadTask] Downloading fMP4 initialization segment from: %@", initURLString)
        NSLog("[DownloadTask] Init segment host: %@", initURL.host ?? "unknown")

        // Create temp directory first if needed
        do {
            _ = try FileStorageManager.shared.createTempDirectory(for: download.id)
        } catch {
            NSLog("[DownloadTask] ERROR: Failed to create temp directory: %@", error.localizedDescription)
            completion()
            return
        }

        let destinationURL = FileStorageManager.shared.initSegmentPath(for: download.id)
        var request = createRequest(for: initURL)

        // Add Range header if byterange is specified (format: "length@offset" or just "length")
        if let byteRange = initSegmentByteRange {
            let rangeHeader: String
            if byteRange.contains("@") {
                let parts = byteRange.split(separator: "@")
                if parts.count == 2, let length = Int(parts[0]), let offset = Int(parts[1]) {
                    rangeHeader = "bytes=\(offset)-\(offset + length - 1)"
                } else {
                    rangeHeader = "bytes=0-\(byteRange)"
                }
            } else if let length = Int(byteRange) {
                rangeHeader = "bytes=0-\(length - 1)"
            } else {
                rangeHeader = ""
            }
            if !rangeHeader.isEmpty {
                request.setValue(rangeHeader, forHTTPHeaderField: "Range")
                NSLog("[DownloadTask] Using Range header for init segment: %@", rangeHeader)
            }
        }

        // Log all request headers for debugging
        NSLog("[DownloadTask] Init segment request headers: %@", request.allHTTPHeaderFields?.description ?? "none")

        URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self = self else {
                completion()
                return
            }

            if let error = error {
                NSLog("[DownloadTask] ERROR: Failed to download init segment: %@", error.localizedDescription)
                self.retryInitSegmentOrContinue(completion: completion)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                NSLog("[DownloadTask] Init segment response status: %d", httpResponse.statusCode)
                NSLog("[DownloadTask] Init segment response headers: %@", httpResponse.allHeaderFields.description)

                // Handle non-success status codes
                if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                    NSLog("[DownloadTask] Auth error on init segment, will retry or continue without it")
                    self.retryInitSegmentOrContinue(completion: completion)
                    return
                }

                if httpResponse.statusCode != 200 && httpResponse.statusCode != 206 {
                    NSLog("[DownloadTask] Unexpected status code for init segment: %d", httpResponse.statusCode)
                    self.retryInitSegmentOrContinue(completion: completion)
                    return
                }
            }

            guard let tempURL = tempURL else {
                NSLog("[DownloadTask] ERROR: No temp URL for init segment")
                completion()
                return
            }

            // Verify we got actual data, not an error page
            if let data = try? Data(contentsOf: tempURL, options: .mappedIfSafe) {
                if data.count < 100 {
                    NSLog("[DownloadTask] Init segment too small (%d bytes), might be error page", data.count)
                    self.retryInitSegmentOrContinue(completion: completion)
                    return
                }

                // Check for HTML content
                let header = data.prefix(20)
                if let str = String(data: header, encoding: .utf8),
                   (str.lowercased().contains("<!doctype") || str.lowercased().contains("<html")) {
                    NSLog("[DownloadTask] Init segment is HTML, not video data")
                    self.retryInitSegmentOrContinue(completion: completion)
                    return
                }

                // Log first bytes for debugging (ftyp box should start with size + "ftyp")
                NSLog("[DownloadTask] Init segment first 20 bytes hex: %@", data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))
            }

            do {
                try FileStorageManager.shared.moveFile(from: tempURL, to: destinationURL)
                let size = FileStorageManager.shared.fileSize(at: destinationURL) ?? 0
                NSLog("[DownloadTask] Init segment saved: %@ - %lld bytes", destinationURL.lastPathComponent, size)

                if size == 0 {
                    NSLog("[DownloadTask] WARNING: Init segment is 0 bytes, removing")
                    try? FileStorageManager.shared.removeFile(at: destinationURL)
                }
            } catch {
                NSLog("[DownloadTask] ERROR: Failed to save init segment: %@", error.localizedDescription)
            }

            completion()
        }.resume()
    }

    private func retryInitSegmentOrContinue(completion: @escaping () -> Void) {
        initSegmentRetryCount += 1
        if initSegmentRetryCount < maxInitSegmentRetries {
            NSLog("[DownloadTask] Retrying init segment download (%d/%d)", initSegmentRetryCount, maxInitSegmentRetries)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.downloadInitSegmentIfNeeded(completion: completion)
            }
        } else {
            NSLog("[DownloadTask] Init segment download failed after %d retries, continuing without it", maxInitSegmentRetries)
            NSLog("[DownloadTask] Video may not be playable - FFmpeg will attempt to remux")
            completion()
        }
    }

    private func startSegmentDownloads() {
        NSLog("[DownloadTask] startSegmentDownloads - %d total segments", segments.count)
        // Create temp directory
        do {
            _ = try FileStorageManager.shared.createTempDirectory(for: download.id)
        } catch {
            NSLog("[DownloadTask] ERROR: Failed to create temp directory: %@", error.localizedDescription)
            delegate?.downloadTask(self, didFailWithError: error)
            return
        }

        // Resume from last downloaded segment if any
        currentSegmentIndex = download.segmentsDownloaded
        downloadNextSegment()
    }

    private var segmentRetryCount = 0
    private let maxSegmentRetries = 3

    private func downloadNextSegment() {
        guard !isCancelled else {
            delegate?.downloadTask(self, didFailWithError: TaskError.cancelled)
            return
        }

        guard !isPaused else { return }

        guard currentSegmentIndex < segments.count else {
            NSLog("[DownloadTask] All segments downloaded, starting mux")
            // All segments downloaded, start muxing
            muxSegments()
            return
        }

        let segment = segments[currentSegmentIndex]
        NSLog("[DownloadTask] Segment %d URL: %@", currentSegmentIndex, segment.url)

        guard let url = URL(string: segment.url) else {
            NSLog("[DownloadTask] ERROR: Invalid segment URL, skipping: %@", segment.url)
            currentSegmentIndex += 1
            segmentRetryCount = 0
            downloadNextSegment()
            return
        }

        let destinationURL = FileStorageManager.shared.segmentPath(for: download.id, index: segment.index, isFMP4: isFMP4)
        NSLog("[DownloadTask] Downloading segment %d to: %@ (attempt %d)", currentSegmentIndex, destinationURL.path, segmentRetryCount + 1)

        downloadSegment(from: url, to: destinationURL) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fileURL):
                self.downloadedSegments.append(fileURL)
                self.currentSegmentIndex += 1
                self.segmentRetryCount = 0

                let progress = Double(self.currentSegmentIndex) / Double(self.segments.count)
                self.delegate?.downloadTask(self, didUpdateProgress: progress * 0.9, segmentsDownloaded: self.currentSegmentIndex) // Reserve 10% for muxing

                self.downloadNextSegment()

            case .failure(let error):
                self.segmentRetryCount += 1
                if self.segmentRetryCount < self.maxSegmentRetries {
                    NSLog("[DownloadTask] Segment %d failed, retrying (%d/%d): %@", self.currentSegmentIndex, self.segmentRetryCount, self.maxSegmentRetries, error.localizedDescription)
                    // Wait a bit before retrying
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.downloadNextSegment()
                    }
                } else {
                    NSLog("[DownloadTask] Segment %d failed after %d retries: %@", self.currentSegmentIndex, self.maxSegmentRetries, error.localizedDescription)
                    self.delegate?.downloadTask(self, didFailWithError: error)
                }
            }
        }
    }

    private func downloadSegment(from url: URL, to destination: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let request = createRequest(for: url)
        logger.info("Downloading segment from: \(url.absoluteString)")

        let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                let nsError = error as NSError
                logger.error("Segment download error: \(error.localizedDescription)")
                logger.error("Error domain: \(nsError.domain), code: \(nsError.code)")
                logger.error("Error userInfo: \(nsError.userInfo.description)")
                NSLog("[DownloadTask] Segment error: %@", error.localizedDescription)
                NSLog("[DownloadTask] Error domain: %@, code: %d", nsError.domain, nsError.code)
                completion(.failure(TaskError.networkError(error)))
                return
            }

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                logger.info("Segment response status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    completion(.failure(TaskError.networkError(NSError(domain: "HTTP", code: httpResponse.statusCode, userInfo: nil))))
                    return
                }
            }

            guard let tempURL = tempURL else {
                completion(.failure(TaskError.invalidURL))
                return
            }

            // Verify it's actually video data, not HTML error page
            if let data = try? Data(contentsOf: tempURL, options: .mappedIfSafe) {
                let header = data.prefix(10)
                if let str = String(data: header, encoding: .utf8), str.contains("<!DOCTYPE") || str.contains("<html") {
                    print("[DownloadTask] ERROR: Received HTML instead of video data")
                    completion(.failure(TaskError.networkError(NSError(domain: "DownloadTask", code: -1, userInfo: [NSLocalizedDescriptionKey: "Received HTML error page instead of video segment"]))))
                    return
                }
            }

            do {
                try FileStorageManager.shared.moveFile(from: tempURL, to: destination)
                let size = FileStorageManager.shared.fileSize(at: destination) ?? 0
                print("[DownloadTask] Segment saved: \(destination.lastPathComponent) - \(size) bytes")
                completion(.success(destination))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: - Direct Download

    private func startDirectDownload(url: URL) {
        // Create temp directory first
        let tempDir: URL
        do {
            tempDir = try FileStorageManager.shared.createTempDirectory(for: download.id)
        } catch {
            delegate?.downloadTask(self, didFailWithError: error)
            return
        }

        // Determine file extension from URL
        let fileExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let destination = FileStorageManager.shared.tempDirectory(for: download.id).appendingPathComponent("video.\(fileExtension)")

        // Use regular URLSession for direct downloads to avoid background session file issues
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.delegate?.downloadTask(self, didFailWithError: TaskError.networkError(error))
                }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    self.delegate?.downloadTask(self, didFailWithError: TaskError.invalidURL)
                }
                return
            }

            do {
                // Copy immediately while the temp file still exists
                try FileStorageManager.shared.copyFile(from: tempURL, to: destination)
                DispatchQueue.main.async {
                    self.delegate?.downloadTask(self, didCompleteWithURL: destination)
                }
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.downloadTask(self, didFailWithError: error)
                }
            }
        }
        task.resume()
    }

    // MARK: - Muxing

    private func muxSegments() {
        delegate?.downloadTask(self, didUpdateProgress: 0.95, segmentsDownloaded: segments.count)

        let segmentsDir = FileStorageManager.shared.segmentsDirectory(for: download.id)
        let outputURL = FileStorageManager.shared.tempDirectory(for: download.id).appendingPathComponent("video.mp4")

        FFmpegMuxer.shared.muxHLSSegments(
            directory: segmentsDir,
            outputURL: outputURL,
            encryptionKey: encryptionKeyData,
            isFMP4: isFMP4
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let url):
                self.delegate?.downloadTask(self, didCompleteWithURL: url)
            case .failure(let error):
                self.delegate?.downloadTask(self, didFailWithError: error)
            }
        }
    }
}
