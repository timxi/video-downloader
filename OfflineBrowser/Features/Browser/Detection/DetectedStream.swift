import Foundation

enum StreamType: String, Codable {
    case hls
    case dash
    case direct
    case unknown
}

struct DetectedStream: Identifiable, Equatable {
    let id: UUID
    let url: String
    let type: StreamType
    let detectedAt: Date

    // Parsed metadata (populated after fetching manifest)
    var qualities: [StreamQuality]?
    var isLive: Bool?
    var isDRMProtected: Bool?
    var hasSubtitles: Bool?
    var duration: TimeInterval?

    init(
        id: UUID = UUID(),
        url: String,
        type: StreamType,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.type = type
        self.detectedAt = detectedAt
    }

    static func == (lhs: DetectedStream, rhs: DetectedStream) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Stream Quality

struct StreamQuality: Identifiable, Equatable {
    let id: UUID
    let resolution: String  // e.g., "1080p", "720p"
    let bandwidth: Int      // bits per second
    let url: String        // URL for this quality variant
    let codecs: String?

    var formattedBandwidth: String {
        let mbps = Double(bandwidth) / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }

    var estimatedFileSize: String? {
        // Rough estimate based on bandwidth and typical duration
        // This is just an approximation
        guard bandwidth > 0 else { return nil }
        let bytesPerSecond = Double(bandwidth) / 8
        let assumedDuration: Double = 300 // 5 minutes as placeholder
        let estimatedBytes = bytesPerSecond * assumedDuration
        return ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }

    init(
        id: UUID = UUID(),
        resolution: String,
        bandwidth: Int,
        url: String,
        codecs: String? = nil
    ) {
        self.id = id
        self.resolution = resolution
        self.bandwidth = bandwidth
        self.url = url
        self.codecs = codecs
    }
}

// MARK: - Quality Sorting

extension Array where Element == StreamQuality {
    var sortedByQuality: [StreamQuality] {
        sorted { $0.bandwidth > $1.bandwidth }
    }

    var highest: StreamQuality? {
        max(by: { $0.bandwidth < $1.bandwidth })
    }

    var lowest: StreamQuality? {
        min(by: { $0.bandwidth < $1.bandwidth })
    }

    func quality(matching preference: String) -> StreamQuality? {
        switch preference {
        case "highest":
            return highest
        case "lowest":
            return lowest
        case "720p":
            return first { $0.resolution.contains("720") } ?? highest
        case "1080p":
            return first { $0.resolution.contains("1080") } ?? highest
        default:
            return highest
        }
    }
}
