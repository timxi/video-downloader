import Foundation
import GRDB

struct Video: Codable, Identifiable {
    var id: UUID
    var title: String
    var sourceURL: String
    var sourceDomain: String
    var filePath: String
    var thumbnailPath: String?
    var subtitlePath: String?
    var duration: Int
    var fileSize: Int64
    var quality: String
    var folderID: UUID?
    var createdAt: Date
    var lastPlayedAt: Date?
    var playbackPosition: Int

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: String,
        sourceDomain: String,
        filePath: String,
        thumbnailPath: String? = nil,
        subtitlePath: String? = nil,
        duration: Int = 0,
        fileSize: Int64 = 0,
        quality: String,
        folderID: UUID? = nil,
        createdAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        playbackPosition: Int = 0
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceDomain = sourceDomain
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.subtitlePath = subtitlePath
        self.duration = duration
        self.fileSize = fileSize
        self.quality = quality
        self.folderID = folderID
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
        self.playbackPosition = playbackPosition
    }
}

// MARK: - GRDB Conformance

extension Video: FetchableRecord, PersistableRecord {
    static let databaseTableName = "videos"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let sourceURL = Column(CodingKeys.sourceURL)
        static let sourceDomain = Column(CodingKeys.sourceDomain)
        static let filePath = Column(CodingKeys.filePath)
        static let thumbnailPath = Column(CodingKeys.thumbnailPath)
        static let subtitlePath = Column(CodingKeys.subtitlePath)
        static let duration = Column(CodingKeys.duration)
        static let fileSize = Column(CodingKeys.fileSize)
        static let quality = Column(CodingKeys.quality)
        static let folderID = Column(CodingKeys.folderID)
        static let createdAt = Column(CodingKeys.createdAt)
        static let lastPlayedAt = Column(CodingKeys.lastPlayedAt)
        static let playbackPosition = Column(CodingKeys.playbackPosition)
    }
}

// MARK: - Relationships

extension Video {
    static let folder = belongsTo(Folder.self)
    var folder: QueryInterfaceRequest<Folder> {
        request(for: Video.folder)
    }
}

// MARK: - Computed Properties

extension Video {
    var formattedDuration: String {
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var videoFileURL: URL? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsURL?.appendingPathComponent(filePath)
    }

    var thumbnailURL: URL? {
        guard let thumbnailPath = thumbnailPath else { return nil }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsURL?.appendingPathComponent(thumbnailPath)
    }

    var subtitleFileURL: URL? {
        guard let subtitlePath = subtitlePath else { return nil }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsURL?.appendingPathComponent(subtitlePath)
    }
}
