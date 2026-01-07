import Foundation
import Combine
import WebKit
import os.log

final class StreamDetector: ObservableObject {
    static let shared = StreamDetector()

    @Published private(set) var detectedStreams: [DetectedStream] = []
    @Published private(set) var isExtractingYouTube: Bool = false

    private let hlsParser = HLSParser()
    private let dashParser = DASHParser()
    private let youtubeExtractor = YouTubeExtractor()
    private var processingURLs: Set<String> = []
    private let logger = Logger(subsystem: "com.offlinebrowser.app", category: "StreamDetector")

    // Minimum duration in seconds to filter out ads (5 minutes)
    private let minimumDurationForMainContent: TimeInterval = 300

    // Duration tolerance for considering streams as same content (15%)
    // Increased to handle CDN variations in segment packaging
    private let durationTolerancePercent: Double = 0.15

    // Minimum ratio of duration compared to longest stream to keep (70%)
    // Streams shorter than 70% of the longest will be filtered out as secondary content
    private let minimumDurationRatio: Double = 0.70

    private init() {}

    // MARK: - Public Methods

    func addStream(url: String, type: StreamType, source: String? = nil) {
        // Avoid duplicates
        guard !detectedStreams.contains(where: { $0.url == url }) else { return }

        // Avoid processing the same URL multiple times
        guard !processingURLs.contains(url) else { return }

        // If YouTube HLS was intercepted from the player, cancel any pending Innertube extraction
        if source == "youtube-intercept" {
            logger.info("YouTube HLS intercepted from player, cancelling Innertube extraction")
            isExtractingYouTube = false
        }

        let stream = DetectedStream(url: url, type: type)

        // For HLS and DASH streams, fetch and parse the manifest for additional info
        switch type {
        case .hls:
            processingURLs.insert(url)
            parseHLSManifest(url: url, stream: stream)
        case .dash:
            processingURLs.insert(url)
            parseDASHManifest(url: url, stream: stream)
        case .direct, .unknown:
            detectedStreams.append(stream)
        }
    }

    func clearStreams() {
        detectedStreams.removeAll()
        processingURLs.removeAll()
        isExtractingYouTube = false
    }

    func removeStream(_ stream: DetectedStream) {
        detectedStreams.removeAll { $0.id == stream.id }
    }

    // MARK: - YouTube Extraction

    /// Check if the URL is a YouTube video and extract streams if so
    /// - Parameters:
    ///   - url: The current page URL
    ///   - webView: The WKWebView to get cookies from (for authenticated access)
    /// - Returns: True if YouTube extraction was started
    @discardableResult
    func checkAndExtractYouTube(url: URL, webView: WKWebView) -> Bool {
        guard youtubeExtractor.canExtract(url: url) else {
            return false
        }

        logger.info("YouTube URL detected, starting extraction: \(url.absoluteString)")

        // Avoid duplicate extractions
        let urlString = url.absoluteString
        guard !processingURLs.contains(urlString) else {
            logger.info("Already processing YouTube URL: \(urlString)")
            return true
        }

        processingURLs.insert(urlString)
        isExtractingYouTube = true
        logger.info("Starting YouTube extraction for: \(urlString)")

        // Get cookies from the webView's data store
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            // Filter to YouTube cookies only
            let youtubeCookies = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                return domain.contains("youtube.com") || domain.contains("google.com")
            }

            self?.logger.info("Starting YouTube extraction with \(youtubeCookies.count) cookies")

            self?.youtubeExtractor.extract(url: url, cookies: youtubeCookies) { [weak self] result in
                DispatchQueue.main.async {
                    self?.processingURLs.remove(urlString)
                    self?.isExtractingYouTube = false

                    switch result {
                    case .success(let streams):
                        self?.logger.info("YouTube extraction successful: \(streams.count) streams")
                        for stream in streams {
                            // Check if we already have this stream
                            if !(self?.detectedStreams.contains(where: { $0.url == stream.url }) ?? false) {
                                self?.detectedStreams.append(stream)
                            }
                        }

                    case .failure(let error):
                        self?.logger.warning("YouTube extraction failed: \(error.localizedDescription)")
                        // Fall back to generic detection - the JavaScript injection may still detect HLS streams
                    }
                }
            }
        }

        return true
    }

    /// Check if a URL is a YouTube video URL
    func isYouTubeURL(_ url: URL) -> Bool {
        return youtubeExtractor.canExtract(url: url)
    }

    // MARK: - HLS Parsing

    private func parseHLSManifest(url: String, stream: DetectedStream) {
        guard let manifestURL = URL(string: url) else {
            processingURLs.remove(url)
            detectedStreams.append(stream)
            return
        }

        hlsParser.parse(url: manifestURL) { [weak self] result in
            DispatchQueue.main.async {
                self?.processingURLs.remove(url)

                switch result {
                case .success(let parsedInfo):
                    var updatedStream = stream
                    updatedStream.qualities = parsedInfo.qualities
                    updatedStream.isLive = parsedInfo.isLive
                    updatedStream.isDRMProtected = parsedInfo.isDRMProtected
                    updatedStream.hasSubtitles = parsedInfo.hasSubtitles
                    updatedStream.duration = parsedInfo.totalDuration

                    // Skip DRM-protected or live streams
                    if parsedInfo.isDRMProtected == true {
                        self?.logger.info("Skipping DRM-protected stream: \(url)")
                        return
                    }
                    if parsedInfo.isLive == true {
                        self?.logger.info("Skipping live stream: \(url)")
                        return
                    }

                    // Filter by duration - skip short streams (likely ads)
                    guard let duration = parsedInfo.totalDuration else {
                        // Unknown duration - skip to be safe (likely failed to fetch variant)
                        self?.logger.warning("Skipping stream with unknown duration: \(url)")
                        return
                    }

                    let minDuration = self?.minimumDurationForMainContent ?? 60
                    if duration < minDuration {
                        self?.logger.info("Skipping short stream (ad): \(url) - Duration: \(duration, format: .fixed(precision: 1))s < \(minDuration)s")
                        return
                    }

                    // Check for existing stream with same duration (deduplicate quality variants)
                    if let existingIndex = self?.findStreamWithSimilarDuration(duration) {
                        // Merge as quality variant of existing stream
                        self?.mergeAsQualityVariant(newStream: updatedStream, existingIndex: existingIndex)
                        NSLog("[StreamDetector] MERGED: Duration %.1fs matches existing stream at index %d", duration, existingIndex)
                    } else {
                        // Deduplicate qualities before adding
                        updatedStream.qualities = self?.deduplicateQualities(updatedStream.qualities)

                        // Add as new stream
                        self?.detectedStreams.append(updatedStream)
                        let existingDurations = self?.detectedStreams.compactMap { $0.duration }.map { String(format: "%.1f", $0) }.joined(separator: ", ") ?? ""
                        NSLog("[StreamDetector] ADDED NEW: Duration %.1fs - Existing durations: [%@]", duration, existingDurations)

                        // Filter out short streams after adding new one
                        self?.filterShortStreams()
                    }

                case .failure(let error):
                    self?.logger.error("Failed to parse HLS manifest: \(error.localizedDescription) - \(url)")
                    // Don't add streams that failed to parse
                }
            }
        }
    }

    // MARK: - DASH Parsing

    private func parseDASHManifest(url: String, stream: DetectedStream) {
        guard let manifestURL = URL(string: url) else {
            logger.warning("Invalid DASH URL: \(url)")
            processingURLs.remove(url)
            return
        }

        dashParser.parse(url: manifestURL) { [weak self] result in
            DispatchQueue.main.async {
                self?.processingURLs.remove(url)

                switch result {
                case .success(let parsedInfo):
                    var updatedStream = stream
                    updatedStream.qualities = parsedInfo.qualities
                    updatedStream.isLive = parsedInfo.isLive
                    updatedStream.isDRMProtected = parsedInfo.isDRMProtected
                    updatedStream.hasSubtitles = parsedInfo.hasSubtitles
                    updatedStream.duration = parsedInfo.totalDuration

                    // Skip DRM-protected streams
                    if parsedInfo.isDRMProtected {
                        self?.logger.info("Skipping DRM-protected DASH stream: \(url)")
                        return
                    }

                    // Skip live streams
                    if parsedInfo.isLive {
                        self?.logger.info("Skipping live DASH stream: \(url)")
                        return
                    }

                    // Filter by duration - skip short streams (likely ads)
                    guard let duration = parsedInfo.totalDuration else {
                        self?.logger.warning("Skipping DASH stream with unknown duration: \(url)")
                        return
                    }

                    let minDuration = self?.minimumDurationForMainContent ?? 60
                    if duration < minDuration {
                        self?.logger.info("Skipping short DASH stream (ad): \(url) - Duration: \(duration, format: .fixed(precision: 1))s < \(minDuration)s")
                        return
                    }

                    // Check for existing stream with same duration (deduplicate quality variants)
                    if let existingIndex = self?.findStreamWithSimilarDuration(duration) {
                        // Merge as quality variant of existing stream
                        self?.mergeAsQualityVariant(newStream: updatedStream, existingIndex: existingIndex)
                        NSLog("[StreamDetector] MERGED DASH: Duration %.1fs matches existing stream at index %d", duration, existingIndex)
                    } else {
                        // Deduplicate qualities before adding
                        updatedStream.qualities = self?.deduplicateQualities(updatedStream.qualities)

                        // Add as new stream
                        self?.detectedStreams.append(updatedStream)
                        let existingDurations = self?.detectedStreams.compactMap { $0.duration }.map { String(format: "%.1f", $0) }.joined(separator: ", ") ?? ""
                        NSLog("[StreamDetector] ADDED NEW DASH: Duration %.1fs - Existing durations: [%@]", duration, existingDurations)

                        // Filter out short streams after adding new one
                        self?.filterShortStreams()
                    }

                case .failure(let error):
                    self?.logger.error("Failed to parse DASH manifest: \(String(describing: error)) - \(url)")
                    // Don't add streams that failed to parse
                }
            }
        }
    }

    // MARK: - Filtering

    /// Remove streams that are much shorter than the longest stream
    private func filterShortStreams() {
        guard detectedStreams.count > 1 else { return }

        // Find the longest duration
        let longestDuration = detectedStreams.compactMap { $0.duration }.max() ?? 0
        guard longestDuration > 0 else { return }

        let threshold = longestDuration * minimumDurationRatio

        // Remove streams shorter than the threshold
        let beforeCount = detectedStreams.count
        detectedStreams.removeAll { stream in
            guard let duration = stream.duration else { return false }
            if duration < threshold {
                NSLog("[StreamDetector] FILTERED OUT: Duration %.1fs < threshold %.1fs (%.0f%% of longest %.1fs)",
                      duration, threshold, minimumDurationRatio * 100, longestDuration)
                return true
            }
            return false
        }

        if detectedStreams.count < beforeCount {
            NSLog("[StreamDetector] Filtered: %d -> %d streams", beforeCount, detectedStreams.count)
        }
    }

    // MARK: - Deduplication

    /// Find an existing stream with similar duration (within tolerance)
    private func findStreamWithSimilarDuration(_ duration: TimeInterval) -> Int? {
        for (index, stream) in detectedStreams.enumerated() {
            guard let existingDuration = stream.duration else { continue }

            // Calculate tolerance based on duration
            let tolerance = existingDuration * durationTolerancePercent
            let lowerBound = existingDuration - tolerance
            let upperBound = existingDuration + tolerance

            if duration >= lowerBound && duration <= upperBound {
                return index
            }
        }
        return nil
    }

    /// Merge a new stream as a quality variant of an existing stream
    private func mergeAsQualityVariant(newStream: DetectedStream, existingIndex: Int) {
        var existing = detectedStreams[existingIndex]

        // Get qualities from the new stream (these have proper bandwidth info from HLS parsing)
        let newQualities = newStream.qualities ?? []

        // Initialize existing qualities array if needed
        if existing.qualities == nil {
            existing.qualities = []
        }

        // If new stream has parsed qualities, merge them
        if !newQualities.isEmpty {
            for quality in newQualities {
                // Avoid duplicate URLs
                if !(existing.qualities?.contains(where: { $0.url == quality.url }) ?? false) {
                    existing.qualities?.append(quality)
                }
            }
            NSLog("[StreamDetector] Merged %d qualities from duplicate stream", newQualities.count)
        } else {
            // Fallback: create a quality entry from the stream URL (with 0 bandwidth)
            let fallbackQuality = StreamQuality(
                resolution: guessResolutionFromURL(newStream.url) ?? "Alt Quality",
                bandwidth: 0,
                url: newStream.url,
                codecs: nil
            )
            if !(existing.qualities?.contains(where: { $0.url == newStream.url }) ?? false) {
                existing.qualities?.append(fallbackQuality)
            }
        }

        // Deduplicate and sort
        existing.qualities = deduplicateQualities(existing.qualities)

        // Update the stream
        detectedStreams[existingIndex] = existing
    }

    /// Deduplicate qualities by resolution + bandwidth (rounded to nearest 100kbps)
    private func deduplicateQualities(_ qualities: [StreamQuality]?) -> [StreamQuality]? {
        guard var qualities = qualities, !qualities.isEmpty else { return qualities }

        // Sort by bandwidth descending first
        qualities.sort { $0.bandwidth > $1.bandwidth }

        // Deduplicate by resolution + rounded bandwidth
        var seen = Set<String>()
        let deduplicated = qualities.filter { quality in
            // Round bandwidth to nearest 100kbps for comparison
            let roundedBandwidth = (quality.bandwidth / 100_000) * 100_000
            let key = "\(quality.resolution.lowercased())-\(roundedBandwidth)"
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }

        NSLog("[StreamDetector] Deduplicated qualities: %d -> %d", qualities.count, deduplicated.count)
        return deduplicated
    }

    /// Try to guess resolution from URL patterns
    private func guessResolutionFromURL(_ url: String) -> String? {
        let patterns: [(String, String)] = [
            ("1080", "1080p"),
            ("720", "720p"),
            ("480", "480p"),
            ("360", "360p"),
            ("240", "240p"),
            ("4k", "4K"),
            ("2160", "4K"),
            ("hd", "HD"),
            ("sd", "SD")
        ]

        let lowercased = url.lowercased()
        for (pattern, label) in patterns {
            if lowercased.contains(pattern) {
                return label
            }
        }
        return nil
    }
}
