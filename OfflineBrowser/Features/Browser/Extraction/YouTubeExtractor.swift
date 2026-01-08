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

    // MARK: - Static Quality Extraction

    /// Extract quality from YouTube itag in URL
    /// YouTube HLS URLs contain itag parameter that identifies the quality
    static func extractQualityFromURL(_ urlString: String) -> String? {
        // YouTube itag to quality mapping
        // Based on https://gist.github.com/AgentOak/34d47c65b1d28829bb17c24c04a0096f
        let itagToQuality: [Int: String] = [
            // HLS video itags
            312: "1080p60",
            311: "720p60",
            310: "720p60",
            309: "720p60",
            308: "1440p60",
            315: "2160p60",
            299: "1080p60",
            298: "720p60",
            // DASH video itags
            137: "1080p",
            136: "720p",
            135: "480p",
            134: "360p",
            133: "240p",
            160: "144p",
            248: "1080p",
            247: "720p",
            244: "480p",
            243: "360p",
            242: "240p",
            278: "144p",
            // VP9 HLS
            302: "720p60",
            303: "1080p60",
            304: "1440p60",
            305: "2160p60",
            // AV1
            394: "144p",
            395: "240p",
            396: "360p",
            397: "480p",
            398: "720p",
            399: "1080p",
            400: "1440p",
            401: "2160p",
            // Direct MP4 (progressive)
            18: "360p",
            22: "720p",
            37: "1080p",
            38: "3072p"
        ]

        // Extract itag from URL
        // URL format: .../itag/123/... or itag=123
        if let itagMatch = urlString.range(of: "/itag/(\\d+)", options: .regularExpression) {
            let itagString = urlString[itagMatch]
                .replacingOccurrences(of: "/itag/", with: "")
            if let itag = Int(itagString), let quality = itagToQuality[itag] {
                return quality
            }
        }

        // Also check for itag= query parameter
        if let urlComponents = URLComponents(string: urlString),
           let itagParam = urlComponents.queryItems?.first(where: { $0.name == "itag" }),
           let itagString = itagParam.value,
           let itag = Int(itagString),
           let quality = itagToQuality[itag] {
            return quality
        }

        return nil
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
