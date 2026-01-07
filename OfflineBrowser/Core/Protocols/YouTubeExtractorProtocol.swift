import Foundation

/// Protocol for YouTube video extraction
/// Allows dependency injection and mocking for tests
protocol YouTubeExtractorProtocol {
    /// Check if this extractor can handle the given URL
    func canExtract(url: URL) -> Bool

    /// Extract video ID from a YouTube URL
    func extractVideoId(from url: URL) -> String?

    /// Extract video streams from a YouTube URL
    /// - Parameters:
    ///   - url: The YouTube video URL
    ///   - cookies: Optional cookies from the browser session (for authenticated access)
    ///   - completion: Completion handler with the detected streams or error
    func extract(
        url: URL,
        cookies: [HTTPCookie],
        completion: @escaping (Result<[DetectedStream], Error>) -> Void
    )
}

// MARK: - Default Implementation

extension YouTubeExtractorProtocol {
    /// Extract with empty cookies (convenience method)
    func extract(url: URL, completion: @escaping (Result<[DetectedStream], Error>) -> Void) {
        extract(url: url, cookies: [], completion: completion)
    }
}
