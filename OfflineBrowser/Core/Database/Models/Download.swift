import Foundation
import GRDB

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case paused
    case muxing
    case completed
    case failed
}

struct Download: Codable, Identifiable {
    var id: UUID
    var videoURL: String
    var manifestURL: String?
    var pageTitle: String?
    var pageURL: String?
    var sourceDomain: String?
    var status: DownloadStatus
    var progress: Double
    var segmentsDownloaded: Int
    var segmentsTotal: Int
    var retryCount: Int
    var errorMessage: String?
    var quality: String?
    var encryptionKeyURL: String?
    var thumbnailURL: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        videoURL: String,
        manifestURL: String? = nil,
        pageTitle: String? = nil,
        pageURL: String? = nil,
        sourceDomain: String? = nil,
        status: DownloadStatus = .pending,
        progress: Double = 0,
        segmentsDownloaded: Int = 0,
        segmentsTotal: Int = 0,
        retryCount: Int = 0,
        errorMessage: String? = nil,
        quality: String? = nil,
        encryptionKeyURL: String? = nil,
        thumbnailURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.videoURL = videoURL
        self.manifestURL = manifestURL
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.sourceDomain = sourceDomain
        self.status = status
        self.progress = progress
        self.segmentsDownloaded = segmentsDownloaded
        self.segmentsTotal = segmentsTotal
        self.retryCount = retryCount
        self.errorMessage = errorMessage
        self.quality = quality
        self.encryptionKeyURL = encryptionKeyURL
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - GRDB Conformance

extension Download: FetchableRecord, PersistableRecord {
    static let databaseTableName = "downloads"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let videoURL = Column(CodingKeys.videoURL)
        static let manifestURL = Column(CodingKeys.manifestURL)
        static let pageTitle = Column(CodingKeys.pageTitle)
        static let pageURL = Column(CodingKeys.pageURL)
        static let sourceDomain = Column(CodingKeys.sourceDomain)
        static let status = Column(CodingKeys.status)
        static let progress = Column(CodingKeys.progress)
        static let segmentsDownloaded = Column(CodingKeys.segmentsDownloaded)
        static let segmentsTotal = Column(CodingKeys.segmentsTotal)
        static let retryCount = Column(CodingKeys.retryCount)
        static let errorMessage = Column(CodingKeys.errorMessage)
        static let quality = Column(CodingKeys.quality)
        static let encryptionKeyURL = Column(CodingKeys.encryptionKeyURL)
        static let thumbnailURL = Column(CodingKeys.thumbnailURL)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Computed Properties

extension Download {
    var formattedProgress: String {
        String(format: "%.0f%%", progress * 100)
    }

    var isActive: Bool {
        status == .downloading || status == .muxing
    }

    var canRetry: Bool {
        status == .failed && retryCount < 5
    }

    var tempDirectoryURL: URL? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsURL?.appendingPathComponent("temp/\(id.uuidString)")
    }
}

// MARK: - Mutations

extension Download {
    mutating func incrementRetry() {
        retryCount += 1
        updatedAt = Date()
    }

    mutating func updateProgress(_ newProgress: Double, segmentsDownloaded: Int) {
        self.progress = newProgress
        self.segmentsDownloaded = segmentsDownloaded
        self.updatedAt = Date()
    }

    mutating func fail(with error: String) {
        self.status = .failed
        self.errorMessage = error
        self.updatedAt = Date()
    }
}
