import Foundation
import GRDB
import Combine

final class VideoRepository {
    static let shared = VideoRepository()
    private let dbPool: DatabasePool

    private init() {
        self.dbPool = DatabaseManager.shared.databasePool
    }

    // MARK: - CRUD Operations

    func save(_ video: Video) throws {
        try dbPool.write { db in
            try video.save(db)
        }
    }

    func update(_ video: Video) throws {
        try dbPool.write { db in
            try video.update(db)
        }
    }

    func delete(_ video: Video) throws {
        try dbPool.write { db in
            _ = try video.delete(db)
        }
        // Also delete associated files
        FileStorageManager.shared.deleteVideoFiles(for: video)
    }

    func deleteAll() throws {
        try dbPool.write { db in
            _ = try Video.deleteAll(db)
        }
    }

    // MARK: - Queries

    func fetchAll() throws -> [Video] {
        try dbPool.read { db in
            try Video
                .order(Video.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetch(id: UUID) throws -> Video? {
        try dbPool.read { db in
            try Video.fetchOne(db, key: id)
        }
    }

    func fetchVideos(inFolder folderID: UUID?) throws -> [Video] {
        try dbPool.read { db in
            if let folderID = folderID {
                return try Video
                    .filter(Video.Columns.folderID == folderID)
                    .order(Video.Columns.createdAt.desc)
                    .fetchAll(db)
            } else {
                return try Video
                    .order(Video.Columns.createdAt.desc)
                    .fetchAll(db)
            }
        }
    }

    func search(query: String) throws -> [Video] {
        try dbPool.read { db in
            try Video
                .filter(Video.Columns.title.like("%\(query)%"))
                .order(Video.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetchRecent(limit: Int = 20) throws -> [Video] {
        try dbPool.read { db in
            try Video
                .order(Video.Columns.lastPlayedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchByDomain(_ domain: String) throws -> [Video] {
        try dbPool.read { db in
            try Video
                .filter(Video.Columns.sourceDomain == domain)
                .order(Video.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Playback Position

    func updatePlaybackPosition(videoID: UUID, position: Int) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE videos
                    SET playbackPosition = ?, lastPlayedAt = ?
                    WHERE id = ?
                    """,
                arguments: [position, Date(), videoID]
            )
        }
    }

    // MARK: - Statistics

    func totalStorageUsed() throws -> Int64 {
        try dbPool.read { db in
            try Video.select(sum(Video.Columns.fileSize)).fetchOne(db) ?? 0
        }
    }

    func videoCount() throws -> Int {
        try dbPool.read { db in
            try Video.fetchCount(db)
        }
    }

    // MARK: - Observation

    func observeAll() -> AnyPublisher<[Video], Error> {
        ValueObservation
            .tracking { db in
                try Video
                    .order(Video.Columns.createdAt.desc)
                    .fetchAll(db)
            }
            .publisher(in: dbPool, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    func observeVideos(inFolder folderID: UUID?) -> AnyPublisher<[Video], Error> {
        ValueObservation
            .tracking { db in
                if let folderID = folderID {
                    return try Video
                        .filter(Video.Columns.folderID == folderID)
                        .order(Video.Columns.createdAt.desc)
                        .fetchAll(db)
                } else {
                    return try Video
                        .order(Video.Columns.createdAt.desc)
                        .fetchAll(db)
                }
            }
            .publisher(in: dbPool, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
