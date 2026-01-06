import XCTest
import GRDB
@testable import OfflineBrowser

final class VideoRepositoryTests: XCTestCase {

    var dbPool: DatabasePool!
    var sut: VideoRepository!
    var mockFileStorage: MockFileStorageManager!

    override func setUp() {
        super.setUp()
        dbPool = try! TestDatabaseManager.makeInMemoryDatabasePool()
        mockFileStorage = MockFileStorageManager()
        sut = VideoRepository(dbPool: dbPool, fileStorage: mockFileStorage)
    }

    override func tearDown() {
        sut = nil
        mockFileStorage = nil
        dbPool = nil
        super.tearDown()
    }

    // MARK: - Save Tests

    func testSave_insertsVideoIntoDatabase() throws {
        let video = TestFixtures.makeVideo(title: "Test Video")

        try sut.save(video)

        let fetched = try sut.fetch(id: video.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test Video")
    }

    func testSave_multipleVideos_allPersisted() throws {
        let video1 = TestFixtures.makeVideo(title: "Video 1")
        let video2 = TestFixtures.makeVideo(title: "Video 2")
        let video3 = TestFixtures.makeVideo(title: "Video 3")

        try sut.save(video1)
        try sut.save(video2)
        try sut.save(video3)

        let all = try sut.fetchAll()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Update Tests

    func testUpdate_modifiesExistingVideo() throws {
        var video = TestFixtures.makeVideo(title: "Original Title")
        try sut.save(video)

        video.title = "Updated Title"
        try sut.update(video)

        let fetched = try sut.fetch(id: video.id)
        XCTAssertEqual(fetched?.title, "Updated Title")
    }

    func testUpdate_playbackPosition_updatesCorrectly() throws {
        let video = TestFixtures.makeVideo(playbackPosition: 0)
        try sut.save(video)

        try sut.updatePlaybackPosition(videoID: video.id, position: 120)

        let fetched = try sut.fetch(id: video.id)
        XCTAssertEqual(fetched?.playbackPosition, 120)
        XCTAssertNotNil(fetched?.lastPlayedAt)
    }

    // MARK: - Delete Tests

    func testDelete_removesVideoFromDatabase() throws {
        let video = TestFixtures.makeVideo()
        try sut.save(video)

        try sut.delete(video)

        let fetched = try sut.fetch(id: video.id)
        XCTAssertNil(fetched)
    }

    func testDelete_callsFileStorageToDeleteFiles() throws {
        let video = TestFixtures.makeVideo()
        try sut.save(video)

        try sut.delete(video)

        XCTAssertEqual(mockFileStorage.deletedVideos.count, 1)
        XCTAssertEqual(mockFileStorage.deletedVideos.first?.id, video.id)
    }

    func testDeleteAll_removesAllVideos() throws {
        try sut.save(TestFixtures.makeVideo())
        try sut.save(TestFixtures.makeVideo())
        try sut.save(TestFixtures.makeVideo())

        try sut.deleteAll()

        let all = try sut.fetchAll()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Fetch Tests

    func testFetchAll_returnsAllVideos() throws {
        try sut.save(TestFixtures.makeVideo(title: "A"))
        try sut.save(TestFixtures.makeVideo(title: "B"))

        let all = try sut.fetchAll()

        XCTAssertEqual(all.count, 2)
    }

    func testFetchAll_orderedByCreatedAtDescending() throws {
        let older = TestFixtures.makeVideo(title: "Older", createdAt: Date().addingTimeInterval(-100))
        let newer = TestFixtures.makeVideo(title: "Newer", createdAt: Date())

        try sut.save(older)
        try sut.save(newer)

        let all = try sut.fetchAll()

        XCTAssertEqual(all.first?.title, "Newer")
        XCTAssertEqual(all.last?.title, "Older")
    }

    func testFetch_withInvalidID_returnsNil() throws {
        let result = try sut.fetch(id: UUID())
        XCTAssertNil(result)
    }

    // MARK: - Folder Query Tests

    func testFetchVideosInFolder_returnsOnlyVideosInFolder() throws {
        // Create folder first (foreign key constraint)
        let folder = TestFixtures.makeFolder()
        try dbPool.write { db in try folder.save(db) }

        let videoInFolder = TestFixtures.makeVideo(title: "In Folder", folderID: folder.id)
        let videoNotInFolder = TestFixtures.makeVideo(title: "Not In Folder", folderID: nil)

        try sut.save(videoInFolder)
        try sut.save(videoNotInFolder)

        let result = try sut.fetchVideos(inFolder: folder.id)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "In Folder")
    }

    func testFetchVideosInFolder_withNilFolder_returnsAllVideos() throws {
        // Create folder first (foreign key constraint)
        let folder = TestFixtures.makeFolder()
        try dbPool.write { db in try folder.save(db) }

        try sut.save(TestFixtures.makeVideo(folderID: folder.id))
        try sut.save(TestFixtures.makeVideo(folderID: nil))

        let result = try sut.fetchVideos(inFolder: nil)

        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Search Tests

    func testSearch_findsByTitle() throws {
        try sut.save(TestFixtures.makeVideo(title: "Swift Tutorial"))
        try sut.save(TestFixtures.makeVideo(title: "Python Basics"))

        let results = try sut.search(query: "Swift")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Swift Tutorial")
    }

    func testSearch_caseInsensitive() throws {
        try sut.save(TestFixtures.makeVideo(title: "Swift Tutorial"))

        let results = try sut.search(query: "swift")

        XCTAssertEqual(results.count, 1)
    }

    func testSearch_partialMatch() throws {
        try sut.save(TestFixtures.makeVideo(title: "Advanced Swift Programming"))

        let results = try sut.search(query: "Swift")

        XCTAssertEqual(results.count, 1)
    }

    func testSearch_noMatch_returnsEmpty() throws {
        try sut.save(TestFixtures.makeVideo(title: "Swift Tutorial"))

        let results = try sut.search(query: "JavaScript")

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Recent Videos Tests

    func testFetchRecent_orderedByLastPlayedAt() throws {
        let playedLongAgo = TestFixtures.makeVideo(title: "Old", lastPlayedAt: Date().addingTimeInterval(-1000))
        let playedRecently = TestFixtures.makeVideo(title: "Recent", lastPlayedAt: Date())

        try sut.save(playedLongAgo)
        try sut.save(playedRecently)

        let recent = try sut.fetchRecent(limit: 10)

        XCTAssertEqual(recent.first?.title, "Recent")
    }

    func testFetchRecent_respectsLimit() throws {
        for i in 0..<10 {
            try sut.save(TestFixtures.makeVideo(title: "Video \(i)", lastPlayedAt: Date()))
        }

        let recent = try sut.fetchRecent(limit: 5)

        XCTAssertEqual(recent.count, 5)
    }

    // MARK: - Domain Query Tests

    func testFetchByDomain_returnsOnlyMatchingDomain() throws {
        try sut.save(TestFixtures.makeVideo(title: "YouTube Video", sourceDomain: "youtube.com"))
        try sut.save(TestFixtures.makeVideo(title: "Vimeo Video", sourceDomain: "vimeo.com"))

        let results = try sut.fetchByDomain("youtube.com")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "YouTube Video")
    }

    // MARK: - Statistics Tests

    func testTotalStorageUsed_sumsFileSizes() throws {
        try sut.save(TestFixtures.makeVideo(fileSize: 1_000_000))
        try sut.save(TestFixtures.makeVideo(fileSize: 2_000_000))
        try sut.save(TestFixtures.makeVideo(fileSize: 3_000_000))

        let total = try sut.totalStorageUsed()

        XCTAssertEqual(total, 6_000_000)
    }

    func testTotalStorageUsed_emptyDatabase_returnsZero() throws {
        let total = try sut.totalStorageUsed()

        XCTAssertEqual(total, 0)
    }

    func testVideoCount_returnsCorrectCount() throws {
        try sut.save(TestFixtures.makeVideo())
        try sut.save(TestFixtures.makeVideo())

        let count = try sut.videoCount()

        XCTAssertEqual(count, 2)
    }

    func testVideoCount_emptyDatabase_returnsZero() throws {
        let count = try sut.videoCount()

        XCTAssertEqual(count, 0)
    }
}
