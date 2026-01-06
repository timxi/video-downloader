import Foundation
import GRDB
import Combine

final class DownloadRepository {
    static let shared = DownloadRepository()

    // MARK: - Dependencies

    private let dbPool: DatabasePool
    private let fileStorage: FileStorageManagerProtocol

    // MARK: - Initialization

    init(
        dbPool: DatabasePool = DatabaseManager.shared.databasePool,
        fileStorage: FileStorageManagerProtocol = FileStorageManager.shared
    ) {
        self.dbPool = dbPool
        self.fileStorage = fileStorage
    }

    // MARK: - CRUD Operations

    func save(_ download: Download) throws {
        try dbPool.write { db in
            try download.save(db)
        }
    }

    func update(_ download: Download) throws {
        try dbPool.write { db in
            try download.update(db)
        }
    }

    func delete(_ download: Download) throws {
        try dbPool.write { db in
            _ = try download.delete(db)
        }
        // Clean up temp files
        fileStorage.deleteTempFiles(for: download)
    }

    func deleteCompleted() throws {
        try dbPool.write { db in
            _ = try Download
                .filter(Download.Columns.status == DownloadStatus.completed.rawValue)
                .deleteAll(db)
        }
    }

    // MARK: - Queries

    func fetchAll() throws -> [Download] {
        try dbPool.read { db in
            try Download
                .order(Download.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetch(id: UUID) throws -> Download? {
        try dbPool.read { db in
            try Download.fetchOne(db, key: id)
        }
    }

    func fetchPending() throws -> [Download] {
        try dbPool.read { db in
            try Download
                .filter(Download.Columns.status == DownloadStatus.pending.rawValue)
                .order(Download.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func fetchActive() throws -> [Download] {
        try dbPool.read { db in
            try Download
                .filter([
                    DownloadStatus.downloading.rawValue,
                    DownloadStatus.muxing.rawValue
                ].contains(Download.Columns.status))
                .order(Download.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func fetchFailed() throws -> [Download] {
        try dbPool.read { db in
            try Download
                .filter(Download.Columns.status == DownloadStatus.failed.rawValue)
                .order(Download.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetchNextPending() throws -> Download? {
        try dbPool.read { db in
            try Download
                .filter(Download.Columns.status == DownloadStatus.pending.rawValue)
                .order(Download.Columns.createdAt.asc)
                .fetchOne(db)
        }
    }

    // MARK: - Status Updates

    func updateStatus(_ download: Download, to status: DownloadStatus) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE downloads
                    SET status = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [status.rawValue, Date(), download.id]
            )
        }
    }

    func updateProgress(_ download: Download, progress: Double, segmentsDownloaded: Int) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE downloads
                    SET progress = ?, segmentsDownloaded = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [progress, segmentsDownloaded, Date(), download.id]
            )
        }
    }

    func markFailed(_ download: Download, error: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE downloads
                    SET status = ?, errorMessage = ?, retryCount = retryCount + 1, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [DownloadStatus.failed.rawValue, error, Date(), download.id]
            )
        }
    }

    func resetForRetry(_ download: Download) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE downloads
                    SET status = ?, errorMessage = NULL, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [DownloadStatus.pending.rawValue, Date(), download.id]
            )
        }
    }

    // MARK: - Observation

    func observeAll() -> AnyPublisher<[Download], Error> {
        ValueObservation
            .tracking { db in
                try Download
                    .order(Download.Columns.createdAt.desc)
                    .fetchAll(db)
            }
            .publisher(in: dbPool, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    func observeActive() -> AnyPublisher<[Download], Error> {
        ValueObservation
            .tracking { db in
                try Download
                    .filter([
                        DownloadStatus.pending.rawValue,
                        DownloadStatus.downloading.rawValue,
                        DownloadStatus.muxing.rawValue
                    ].contains(Download.Columns.status))
                    .order(Download.Columns.createdAt.asc)
                    .fetchAll(db)
            }
            .publisher(in: dbPool, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
