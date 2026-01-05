import Foundation

struct HLSParsedInfo {
    var qualities: [StreamQuality]
    var isLive: Bool
    var isDRMProtected: Bool
    var hasSubtitles: Bool
    var segments: [HLSSegment]?
    var encryptionKeyURL: String?
}

struct HLSSegment {
    let url: String
    let duration: Double
    let index: Int
}

final class HLSParser {

    enum ParseError: Error {
        case invalidURL
        case networkError(Error)
        case invalidManifest
        case noContent
    }

    // MARK: - Public Methods

    func parse(url: URL, completion: @escaping (Result<HLSParsedInfo, ParseError>) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data, let content = String(data: data, encoding: .utf8) else {
                completion(.failure(.noContent))
                return
            }

            self?.parseManifest(content: content, baseURL: url, completion: completion)
        }.resume()
    }

    func parseManifest(content: String, baseURL: URL, completion: @escaping (Result<HLSParsedInfo, ParseError>) -> Void) {
        let lines = content.components(separatedBy: .newlines)

        guard lines.first?.contains("#EXTM3U") == true else {
            completion(.failure(.invalidManifest))
            return
        }

        // Check if this is a master playlist or media playlist
        if content.contains("#EXT-X-STREAM-INF") {
            parseMasterPlaylist(lines: lines, baseURL: baseURL, completion: completion)
        } else {
            parseMediaPlaylist(lines: lines, baseURL: baseURL, completion: completion)
        }
    }

    // MARK: - Master Playlist Parsing

    private func parseMasterPlaylist(lines: [String], baseURL: URL, completion: @escaping (Result<HLSParsedInfo, ParseError>) -> Void) {
        var qualities: [StreamQuality] = []
        var hasSubtitles = false
        var isDRMProtected = false

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Check for subtitles
            if line.hasPrefix("#EXT-X-MEDIA") && line.contains("TYPE=SUBTITLES") {
                hasSubtitles = true
            }

            // Check for DRM
            if line.hasPrefix("#EXT-X-KEY") {
                if line.contains("METHOD=SAMPLE-AES") ||
                   line.contains("com.apple.streamingkeydelivery") ||
                   line.contains("com.widevine") {
                    isDRMProtected = true
                }
            }

            // Parse quality variants
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                let bandwidth = extractAttribute(from: line, key: "BANDWIDTH")
                let resolution = extractAttribute(from: line, key: "RESOLUTION")
                let codecs = extractAttribute(from: line, key: "CODECS")

                // Get the URL on the next line
                i += 1
                if i < lines.count {
                    let urlLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if !urlLine.isEmpty && !urlLine.hasPrefix("#") {
                        let qualityURL = resolveURL(urlLine, baseURL: baseURL)

                        let quality = StreamQuality(
                            resolution: formatResolution(resolution),
                            bandwidth: Int(bandwidth ?? "0") ?? 0,
                            url: qualityURL,
                            codecs: codecs
                        )
                        qualities.append(quality)
                    }
                }
            }

            i += 1
        }

        let info = HLSParsedInfo(
            qualities: qualities.sortedByQuality,
            isLive: false,
            isDRMProtected: isDRMProtected,
            hasSubtitles: hasSubtitles,
            segments: nil,
            encryptionKeyURL: nil
        )

        completion(.success(info))
    }

    // MARK: - Media Playlist Parsing

    private func parseMediaPlaylist(lines: [String], baseURL: URL, completion: @escaping (Result<HLSParsedInfo, ParseError>) -> Void) {
        var segments: [HLSSegment] = []
        var isLive = true
        var isDRMProtected = false
        var encryptionKeyURL: String?

        var currentDuration: Double = 0
        var segmentIndex = 0

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Check for live vs VOD
            if trimmedLine.hasPrefix("#EXT-X-ENDLIST") {
                isLive = false
            }

            // Check for encryption
            if trimmedLine.hasPrefix("#EXT-X-KEY") {
                if trimmedLine.contains("METHOD=SAMPLE-AES") ||
                   trimmedLine.contains("com.apple.streamingkeydelivery") {
                    isDRMProtected = true
                } else if trimmedLine.contains("METHOD=AES-128") {
                    // AES-128 encryption - we can handle this
                    if let uri = extractAttribute(from: trimmedLine, key: "URI") {
                        encryptionKeyURL = resolveURL(uri.replacingOccurrences(of: "\"", with: ""), baseURL: baseURL)
                    }
                }
            }

            // Parse segment duration
            if trimmedLine.hasPrefix("#EXTINF:") {
                if let durationString = trimmedLine.dropFirst("#EXTINF:".count).split(separator: ",").first {
                    currentDuration = Double(durationString) ?? 0
                }
            }

            // Segment URL
            if !trimmedLine.hasPrefix("#") && !trimmedLine.isEmpty && trimmedLine.contains(".") {
                let segmentURL = resolveURL(trimmedLine, baseURL: baseURL)
                let segment = HLSSegment(url: segmentURL, duration: currentDuration, index: segmentIndex)
                segments.append(segment)
                segmentIndex += 1
                currentDuration = 0
            }
        }

        let info = HLSParsedInfo(
            qualities: [],
            isLive: isLive,
            isDRMProtected: isDRMProtected,
            hasSubtitles: false,
            segments: segments,
            encryptionKeyURL: encryptionKeyURL
        )

        completion(.success(info))
    }

    // MARK: - Helpers

    private func extractAttribute(from line: String, key: String) -> String? {
        let pattern = "\(key)=([^,\\s]+|\"[^\"]+\")"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range]).replacingOccurrences(of: "\"", with: "")
    }

    private func resolveURL(_ urlString: String, baseURL: URL) -> String {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return urlString
        }

        if urlString.hasPrefix("/") {
            // Absolute path
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = urlString
            components?.query = nil
            return components?.url?.absoluteString ?? urlString
        }

        // Relative path - need to handle query strings properly
        // Don't use appendingPathComponent as it URL-encodes special characters like ?
        let base = baseURL.deletingLastPathComponent()

        // Construct URL manually to preserve query parameters in segment URL
        var baseString = base.absoluteString
        if !baseString.hasSuffix("/") {
            baseString += "/"
        }

        // Remove any query string from the base URL before appending
        if let queryStart = baseString.firstIndex(of: "?") {
            baseString = String(baseString[..<queryStart])
            if !baseString.hasSuffix("/") {
                baseString += "/"
            }
        }

        return baseString + urlString
    }

    private func formatResolution(_ resolution: String?) -> String {
        guard let resolution = resolution else { return "Unknown" }

        let parts = resolution.split(separator: "x")
        if parts.count == 2, let height = Int(parts[1]) {
            return "\(height)p"
        }

        return resolution
    }
}
