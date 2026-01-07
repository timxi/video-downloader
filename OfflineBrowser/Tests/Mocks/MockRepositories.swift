import Foundation
import Combine
@testable import OfflineBrowser

// MARK: - Mock Video Repository

final class MockVideoRepository: VideoRepositoryProtocol {

    // MARK: - In-Memory Storage

    private var videos: [UUID: Video] = [:]

    // MARK: - Tracking

    private(set) var savedVideos: [Video] = []
    private(set) var updatedVideos: [Video] = []
    private(set) var deletedVideos: [Video] = []
    private(set) var playbackPositionUpdates: [(videoID: UUID, position: Int)] = []

    // MARK: - Error Simulation

    var shouldThrowOnSave = false
    var shouldThrowOnUpdate = false
    var shouldThrowOnDelete = false

    // MARK: - Publishers

    private let videosSubject = CurrentValueSubject<[Video], Error>([])

    // MARK: - CRUD

    func save(_ video: Video) throws {
        if shouldThrowOnSave {
            throw NSError(domain: "MockVideoRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save video"])
        }
        savedVideos.append(video)
        videos[video.id] = video
        publishUpdate()
    }

    func update(_ video: Video) throws {
        if shouldThrowOnUpdate {
            throw NSError(domain: "MockVideoRepository", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to update video"])
        }
        updatedVideos.append(video)
        videos[video.id] = video
        publishUpdate()
    }

    func delete(_ video: Video) throws {
        if shouldThrowOnDelete {
            throw NSError(domain: "MockVideoRepository", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to delete video"])
        }
        deletedVideos.append(video)
        videos.removeValue(forKey: video.id)
        publishUpdate()
    }

    func deleteAll() throws {
        videos.removeAll()
        publishUpdate()
    }

    // MARK: - Queries

    func fetchAll() throws -> [Video] {
        Array(videos.values).sorted { $0.createdAt > $1.createdAt }
    }

    func fetch(id: UUID) throws -> Video? {
        videos[id]
    }

    func fetchVideos(inFolder folderID: UUID?) throws -> [Video] {
        videos.values.filter { $0.folderID == folderID }.sorted { $0.createdAt > $1.createdAt }
    }

    func search(query: String) throws -> [Video] {
        let lowercased = query.lowercased()
        return videos.values.filter { $0.title.lowercased().contains(lowercased) }
    }

    func fetchRecent(limit: Int) throws -> [Video] {
        Array(videos.values.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }.prefix(limit))
    }

    func fetchByDomain(_ domain: String) throws -> [Video] {
        videos.values.filter { $0.sourceDomain == domain }
    }

    // MARK: - Playback

    func updatePlaybackPosition(videoID: UUID, position: Int) throws {
        playbackPositionUpdates.append((videoID: videoID, position: position))
        if var video = videos[videoID] {
            video.playbackPosition = position
            video.lastPlayedAt = Date()
            videos[videoID] = video
        }
    }

    // MARK: - Statistics

    func totalStorageUsed() throws -> Int64 {
        videos.values.reduce(0) { $0 + $1.fileSize }
    }

    func videoCount() throws -> Int {
        videos.count
    }

    // MARK: - Observation

    func observeAll() -> AnyPublisher<[Video], Error> {
        videosSubject.eraseToAnyPublisher()
    }

    func observeVideos(inFolder folderID: UUID?) -> AnyPublisher<[Video], Error> {
        videosSubject
            .map { videos in videos.filter { $0.folderID == folderID } }
            .eraseToAnyPublisher()
    }

    // MARK: - Helpers

    private func publishUpdate() {
        videosSubject.send(Array(videos.values))
    }

    func reset() {
        videos.removeAll()
        savedVideos.removeAll()
        updatedVideos.removeAll()
        deletedVideos.removeAll()
        playbackPositionUpdates.removeAll()
        shouldThrowOnSave = false
        shouldThrowOnUpdate = false
        shouldThrowOnDelete = false
        videosSubject.send([])
    }

    func addVideo(_ video: Video) {
        videos[video.id] = video
        publishUpdate()
    }
}

// MARK: - Mock Download Repository

final class MockDownloadRepository: DownloadRepositoryProtocol {

    // MARK: - In-Memory Storage

    var downloads: [Download] = []

    // MARK: - Configurable Returns (for tests to set expected values)

    var pendingDownloads: [Download] = []
    var activeDownloads: [Download] = []

    // MARK: - Tracking

    private(set) var savedDownloads: [Download] = []
    private(set) var updatedDownloads: [Download] = []
    private(set) var deletedDownloads: [Download] = []
    private(set) var statusUpdates: [(download: Download, status: DownloadStatus)] = []
    private(set) var progressUpdates: [(download: Download, progress: Double, segmentsDownloaded: Int)] = []
    private(set) var failedDownloads: [Download] = []
    private(set) var resetDownloads: [Download] = []

    // MARK: - Error Simulation

    var shouldThrowOnSave = false

    // MARK: - Publishers

    private let downloadsSubject = CurrentValueSubject<[Download], Error>([])

    // MARK: - CRUD

    func save(_ download: Download) throws {
        if shouldThrowOnSave {
            throw NSError(domain: "MockDownloadRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save download"])
        }
        savedDownloads.append(download)
        downloads.append(download)
        publishUpdate()
    }

    func update(_ download: Download) throws {
        updatedDownloads.append(download)
        if let index = downloads.firstIndex(where: { $0.id == download.id }) {
            downloads[index] = download
        }
        publishUpdate()
    }

    func delete(_ download: Download) throws {
        deletedDownloads.append(download)
        downloads.removeAll { $0.id == download.id }
        publishUpdate()
    }

    func deleteCompleted() throws {
        downloads.removeAll { $0.status == .completed }
        publishUpdate()
    }

    // MARK: - Queries

    func fetchAll() throws -> [Download] {
        downloads.sorted { $0.createdAt > $1.createdAt }
    }

    func fetch(id: UUID) throws -> Download? {
        downloads.first { $0.id == id }
    }

    func fetchPending() throws -> [Download] {
        // Return configured pendingDownloads if set, otherwise filter from downloads
        if !pendingDownloads.isEmpty {
            return pendingDownloads
        }
        return downloads.filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt }
    }

    func fetchActive() throws -> [Download] {
        // Return configured activeDownloads if set, otherwise filter from downloads
        if !activeDownloads.isEmpty {
            return activeDownloads
        }
        return downloads.filter { $0.status == .downloading || $0.status == .muxing }.sorted { $0.createdAt < $1.createdAt }
    }

    func fetchFailed() throws -> [Download] {
        downloads.filter { $0.status == .failed }.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchNextPending() throws -> Download? {
        if !pendingDownloads.isEmpty {
            return pendingDownloads.first
        }
        return downloads.filter { $0.status == .pending }.min { $0.createdAt < $1.createdAt }
    }

    // MARK: - Status Updates

    func updateStatus(_ download: Download, to status: DownloadStatus) throws {
        statusUpdates.append((download: download, status: status))
        if let index = downloads.firstIndex(where: { $0.id == download.id }) {
            var d = downloads[index]
            d.status = status
            downloads[index] = d
        }
        publishUpdate()
    }

    func updateProgress(_ download: Download, progress: Double, segmentsDownloaded: Int) throws {
        progressUpdates.append((download: download, progress: progress, segmentsDownloaded: segmentsDownloaded))
        if let index = downloads.firstIndex(where: { $0.id == download.id }) {
            var d = downloads[index]
            d.progress = progress
            d.segmentsDownloaded = segmentsDownloaded
            downloads[index] = d
        }
        publishUpdate()
    }

    func markFailed(_ download: Download, error: String) throws {
        failedDownloads.append(download)
        if let index = downloads.firstIndex(where: { $0.id == download.id }) {
            var d = downloads[index]
            d.status = .failed
            d.errorMessage = error
            d.retryCount += 1
            downloads[index] = d
        }
        publishUpdate()
    }

    func resetForRetry(_ download: Download) throws {
        resetDownloads.append(download)
        if let index = downloads.firstIndex(where: { $0.id == download.id }) {
            var d = downloads[index]
            d.status = .pending
            d.errorMessage = nil
            downloads[index] = d
        }
        publishUpdate()
    }

    // MARK: - Observation

    func observeAll() -> AnyPublisher<[Download], Error> {
        downloadsSubject.eraseToAnyPublisher()
    }

    func observeActive() -> AnyPublisher<[Download], Error> {
        downloadsSubject
            .map { downloads in
                downloads.filter { [.pending, .downloading, .muxing].contains($0.status) }
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Helpers

    private func publishUpdate() {
        downloadsSubject.send(downloads)
    }

    func reset() {
        downloads.removeAll()
        pendingDownloads.removeAll()
        activeDownloads.removeAll()
        savedDownloads.removeAll()
        updatedDownloads.removeAll()
        deletedDownloads.removeAll()
        statusUpdates.removeAll()
        progressUpdates.removeAll()
        failedDownloads.removeAll()
        resetDownloads.removeAll()
        shouldThrowOnSave = false
        downloadsSubject.send([])
    }

    func addDownload(_ download: Download) {
        downloads.append(download)
        publishUpdate()
    }
}

// MARK: - Mock Folder Repository

final class MockFolderRepository: FolderRepositoryProtocol {

    // MARK: - In-Memory Storage

    private var folders: [UUID: Folder] = [:]

    // MARK: - Tracking

    private(set) var savedFolders: [Folder] = []
    private(set) var updatedFolders: [Folder] = []
    private(set) var deletedFolders: [Folder] = []
    private(set) var renamedFolders: [(folder: Folder, newName: String)] = []
    private(set) var autoFolderDomains: [String] = []

    // MARK: - Publishers

    private let foldersSubject = CurrentValueSubject<[Folder], Error>([])

    // MARK: - Video Count Configuration

    var videoCounts: [UUID: Int] = [:]

    // MARK: - CRUD

    func save(_ folder: Folder) throws {
        savedFolders.append(folder)
        folders[folder.id] = folder
        publishUpdate()
    }

    func update(_ folder: Folder) throws {
        updatedFolders.append(folder)
        folders[folder.id] = folder
        publishUpdate()
    }

    func delete(_ folder: Folder) throws {
        deletedFolders.append(folder)
        folders.removeValue(forKey: folder.id)
        publishUpdate()
    }

    // MARK: - Queries

    func fetchAll() throws -> [Folder] {
        Array(folders.values).sorted { $0.name < $1.name }
    }

    func fetch(id: UUID) throws -> Folder? {
        folders[id]
    }

    func fetchAutoGeneratedFolders() throws -> [Folder] {
        folders.values.filter { $0.isAutoGenerated }.sorted { $0.name < $1.name }
    }

    func fetchUserFolders() throws -> [Folder] {
        folders.values.filter { !$0.isAutoGenerated }.sorted { $0.name < $1.name }
    }

    func fetchOrCreateAutoFolder(for domain: String) throws -> Folder {
        autoFolderDomains.append(domain)

        // Check for existing auto folder with this name
        if let existing = folders.values.first(where: { $0.name == domain && $0.isAutoGenerated }) {
            return existing
        }

        // Create new auto folder
        let folder = Folder.autoFolder(for: domain)
        folders[folder.id] = folder
        publishUpdate()
        return folder
    }

    func rename(_ folder: Folder, to newName: String) throws {
        renamedFolders.append((folder: folder, newName: newName))
        if var f = folders[folder.id] {
            f.name = newName
            folders[folder.id] = f
        }
        publishUpdate()
    }

    // MARK: - Statistics

    func videoCount(in folder: Folder) throws -> Int {
        videoCounts[folder.id] ?? 0
    }

    // MARK: - Observation

    func observeAll() -> AnyPublisher<[Folder], Error> {
        foldersSubject.eraseToAnyPublisher()
    }

    // MARK: - Helpers

    private func publishUpdate() {
        foldersSubject.send(Array(folders.values))
    }

    func reset() {
        folders.removeAll()
        savedFolders.removeAll()
        updatedFolders.removeAll()
        deletedFolders.removeAll()
        renamedFolders.removeAll()
        autoFolderDomains.removeAll()
        videoCounts.removeAll()
        foldersSubject.send([])
    }

    func addFolder(_ folder: Folder) {
        folders[folder.id] = folder
        publishUpdate()
    }
}
