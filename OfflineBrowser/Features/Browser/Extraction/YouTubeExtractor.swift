import Foundation
import os.log

/// Extracts video streams from YouTube URLs using a JavaScript bridge
final class YouTubeExtractor: YouTubeExtractorProtocol {

    // MARK: - Properties

    private let jsBridge: JSBridge
    private let logger = Logger(subsystem: "com.offlinebrowser.app", category: "YouTubeExtractor")

    /// URL patterns that indicate a YouTube video page
    private let youtubePatterns: [String] = [
        "youtube.com/watch",
        "youtu.be/",
        "youtube.com/shorts/",
        "youtube.com/embed/",
        "youtube.com/v/",
        "youtube-nocookie.com/embed/"
    ]

    /// Hosts that are considered YouTube
    private let youtubeHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com"
    ]

    // MARK: - Initialization

    init() {
        self.jsBridge = JSBridge()
        jsBridge.setup()
    }

    deinit {
        jsBridge.teardown()
    }

    // MARK: - YouTubeExtractorProtocol

    func canExtract(url: URL) -> Bool {
        // Check host first
        guard let host = url.host?.lowercased() else { return false }

        let isYouTubeHost = youtubeHosts.contains(host) ||
                           youtubeHosts.contains(where: { host.hasSuffix(".\($0)") })

        guard isYouTubeHost else { return false }

        // Check URL pattern
        let urlString = url.absoluteString.lowercased()
        return youtubePatterns.contains { urlString.contains($0) }
    }

    func extractVideoId(from url: URL) -> String? {
        let urlString = url.absoluteString

        // Pattern 1: youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return sanitizeVideoId(videoId)
        }

        // Pattern 2: youtu.be/VIDEO_ID
        if url.host == "youtu.be" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                return sanitizeVideoId(path)
            }
        }

        // Pattern 3: youtube.com/shorts/VIDEO_ID
        if urlString.contains("/shorts/") {
            let path = url.path
            if let range = path.range(of: "/shorts/") {
                let videoId = String(path[range.upperBound...])
                    .components(separatedBy: "/").first ?? ""
                if !videoId.isEmpty {
                    return sanitizeVideoId(videoId)
                }
            }
        }

        // Pattern 4: youtube.com/embed/VIDEO_ID
        if urlString.contains("/embed/") {
            let path = url.path
            if let range = path.range(of: "/embed/") {
                let videoId = String(path[range.upperBound...])
                    .components(separatedBy: "/").first ?? ""
                if !videoId.isEmpty {
                    return sanitizeVideoId(videoId)
                }
            }
        }

        // Pattern 5: youtube.com/v/VIDEO_ID
        if urlString.contains("/v/") {
            let path = url.path
            if let range = path.range(of: "/v/") {
                let videoId = String(path[range.upperBound...])
                    .components(separatedBy: "/").first ?? ""
                if !videoId.isEmpty {
                    return sanitizeVideoId(videoId)
                }
            }
        }

        logger.warning("Could not extract video ID from URL: \(urlString)")
        return nil
    }

    func extract(url: URL, cookies: [HTTPCookie], completion: @escaping (Result<[DetectedStream], Error>) -> Void) {
        guard canExtract(url: url) else {
            logger.warning("URL is not a YouTube video: \(url.absoluteString)")
            completion(.failure(YouTubeExtractionError.invalidVideoId))
            return
        }

        guard let videoId = extractVideoId(from: url) else {
            logger.error("Could not extract video ID from: \(url.absoluteString)")
            completion(.failure(YouTubeExtractionError.invalidVideoId))
            return
        }

        logger.info("Extracting YouTube video: \(videoId)")

        jsBridge.extractYouTube(videoId: videoId, cookies: cookies) { [weak self] result in
            switch result {
            case .success(let extractionResult):
                let stream = self?.createDetectedStream(from: extractionResult, originalURL: url)
                if let stream = stream {
                    completion(.success([stream]))
                } else {
                    completion(.failure(YouTubeExtractionError.extractionFailed("Failed to create stream")))
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Private Methods

    /// Sanitize video ID by removing any query parameters or fragments
    private func sanitizeVideoId(_ videoId: String) -> String {
        var sanitized = videoId

        // Remove query string if present
        if let queryIndex = sanitized.firstIndex(of: "?") {
            sanitized = String(sanitized[..<queryIndex])
        }

        // Remove fragment if present
        if let fragmentIndex = sanitized.firstIndex(of: "#") {
            sanitized = String(sanitized[..<fragmentIndex])
        }

        // Trim whitespace
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // YouTube video IDs are typically 11 characters
        // But we'll accept any reasonable length
        return sanitized
    }

    /// Create a DetectedStream from the extraction result
    private func createDetectedStream(from result: YouTubeExtractionResult, originalURL: URL) -> DetectedStream {
        var stream = DetectedStream(
            url: result.hlsURL,
            type: .hls
        )

        stream.duration = result.duration
        stream.pageTitle = result.title
        stream.thumbnailURL = result.thumbnailURL

        logger.info("Created DetectedStream from YouTube: \(result.hlsURL)")

        return stream
    }
}

// MARK: - DetectedStream Extension

extension DetectedStream {
    var pageTitle: String? {
        get { return nil } // Not stored directly
        set { /* Would need to add property to DetectedStream */ }
    }

    var thumbnailURL: String? {
        get { return nil } // Not stored directly
        set { /* Would need to add property to DetectedStream */ }
    }
}
