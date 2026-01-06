import XCTest
import GRDB
@testable import OfflineBrowser

final class DownloadRepositoryTests: XCTestCase {

    var dbPool: DatabasePool!
    var sut: DownloadRepository!
    var mockFileStorage: MockFileStorageManager!

    override func setUp() {
        super.setUp()
        dbPool = try! TestDatabaseManager.makeInMemoryDatabasePool()
        mockFileStorage = MockFileStorageManager()
        sut = DownloadRepository(dbPool: dbPool, fileStorage: mockFileStorage)
    }

    override func tearDown() {
        sut = nil
        mockFileStorage = nil
        dbPool = nil
        super.tearDown()
    }

    // MARK: - Save Tests

    func testSave_insertsDownloadIntoDatabase() throws {
        let download = TestFixtures.makeDownload(pageTitle: "Test Download")

        try sut.save(download)

        let fetched = try sut.fetch(id: download.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.pageTitle, "Test Download")
    }

    func testSave_multipleDownloads_allPersisted() throws {
        try sut.save(TestFixtures.makeDownload())
        try sut.save(TestFixtures.makeDownload())
        try sut.save(TestFixtures.makeDownload())

        let all = try sut.fetchAll()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Update Tests

    func testUpdate_modifiesExistingDownload() throws {
        var download = TestFixtures.makeDownload(status: .pending)
        try sut.save(download)

        download.status = .downloading
        try sut.update(download)

        let fetched = try sut.fetch(id: download.id)
        XCTAssertEqual(fetched?.status, .downloading)
    }

    // MARK: - Delete Tests

    func testDelete_removesDownloadFromDatabase() throws {
        let download = TestFixtures.makeDownload()
        try sut.save(download)

        try sut.delete(download)

        let fetched = try sut.fetch(id: download.id)
        XCTAssertNil(fetched)
    }

    func testDelete_callsFileStorageToDeleteTempFiles() throws {
        let download = TestFixtures.makeDownload()
        try sut.save(download)

        try sut.delete(download)

        XCTAssertEqual(mockFileStorage.deletedDownloads.count, 1)
        XCTAssertEqual(mockFileStorage.deletedDownloads.first?.id, download.id)
    }

    func testDeleteCompleted_removesOnlyCompletedDownloads() throws {
        try sut.save(TestFixtures.makeDownload(status: .completed))
        try sut.save(TestFixtures.makeDownload(status: .pending))
        try sut.save(TestFixtures.makeDownload(status: .failed))

        try sut.deleteCompleted()

        let all = try sut.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.status != .completed })
    }

    // MARK: - Fetch Tests

    func testFetchAll_returnsAllDownloads() throws {
        try sut.save(TestFixtures.makeDownload())
        try sut.save(TestFixtures.makeDownload())

        let all = try sut.fetchAll()

        XCTAssertEqual(all.count, 2)
    }

    func testFetchAll_orderedByCreatedAtDescending() throws {
        let older = TestFixtures.makeDownload(createdAt: Date().addingTimeInterval(-100))
        let newer = TestFixtures.makeDownload(createdAt: Date())

        try sut.save(older)
        try sut.save(newer)

        let all = try sut.fetchAll()

        XCTAssertEqual(all.first?.id, newer.id)
    }

    func testFetch_withInvalidID_returnsNil() throws {
        let result = try sut.fetch(id: UUID())
        XCTAssertNil(result)
    }

    // MARK: - Status Filter Tests

    func testFetchPending_returnsOnlyPendingDownloads() throws {
        try sut.save(TestFixtures.makeDownload(status: .pending))
        try sut.save(TestFixtures.makeDownload(status: .downloading))
        try sut.save(TestFixtures.makeDownload(status: .completed))

        let pending = try sut.fetchPending()

        XCTAssertEqual(pending.count, 1)
        XCTAssertTrue(pending.allSatisfy { $0.status == .pending })
    }

    func testFetchPending_orderedByCreatedAtAscending() throws {
        let first = TestFixtures.makeDownload(status: .pending, createdAt: Date().addingTimeInterval(-100))
        let second = TestFixtures.makeDownload(status: .pending, createdAt: Date())

        try sut.save(second)
        try sut.save(first)

        let pending = try sut.fetchPending()

        XCTAssertEqual(pending.first?.id, first.id)
    }

    func testFetchActive_returnsDownloadingAndMuxing() throws {
        try sut.save(TestFixtures.makeDownload(status: .pending))
        try sut.save(TestFixtures.makeDownload(status: .downloading))
        try sut.save(TestFixtures.makeDownload(status: .muxing))
        try sut.save(TestFixtures.makeDownload(status: .completed))

        let active = try sut.fetchActive()

        XCTAssertEqual(active.count, 2)
        XCTAssertTrue(active.allSatisfy { $0.status == .downloading || $0.status == .muxing })
    }

    func testFetchFailed_returnsOnlyFailedDownloads() throws {
        try sut.save(TestFixtures.makeDownload(status: .pending))
        try sut.save(TestFixtures.makeDownload(status: .failed, errorMessage: "Network error"))
        try sut.save(TestFixtures.makeDownload(status: .failed, errorMessage: "Timeout"))

        let failed = try sut.fetchFailed()

        XCTAssertEqual(failed.count, 2)
        XCTAssertTrue(failed.allSatisfy { $0.status == .failed })
    }

    func testFetchNextPending_returnsOldestPending() throws {
        let first = TestFixtures.makeDownload(status: .pending, createdAt: Date().addingTimeInterval(-100))
        let second = TestFixtures.makeDownload(status: .pending, createdAt: Date())

        try sut.save(second)
        try sut.save(first)

        let next = try sut.fetchNextPending()

        XCTAssertEqual(next?.id, first.id)
    }

    func testFetchNextPending_noPending_returnsNil() throws {
        try sut.save(TestFixtures.makeDownload(status: .completed))

        let next = try sut.fetchNextPending()

        XCTAssertNil(next)
    }

    // MARK: - Status Update Tests

    func testUpdateStatus_changesStatus() throws {
        let download = TestFixtures.makeDownload(status: .pending)
        try sut.save(download)

        try sut.updateStatus(download, to: .downloading)

        let fetched = try sut.fetch(id: download.id)
        XCTAssertEqual(fetched?.status, .downloading)
    }

    func testUpdateProgress_updatesProgressAndSegments() throws {
        let download = TestFixtures.makeDownload(progress: 0, segmentsDownloaded: 0)
        try sut.save(download)

        try sut.updateProgress(download, progress: 0.5, segmentsDownloaded: 50)

        let fetched = try sut.fetch(id: download.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched!.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(fetched?.segmentsDownloaded, 50)
    }

    func testMarkFailed_setsStatusAndError() throws {
        let download = TestFixtures.makeDownload(status: .downloading, retryCount: 0)
        try sut.save(download)

        try sut.markFailed(download, error: "Connection timeout")

        let fetched = try sut.fetch(id: download.id)
        XCTAssertEqual(fetched?.status, .failed)
        XCTAssertEqual(fetched?.errorMessage, "Connection timeout")
        XCTAssertEqual(fetched?.retryCount, 1)
    }

    func testMarkFailed_incrementsRetryCount() throws {
        let download = TestFixtures.makeDownload(status: .downloading, retryCount: 2)
        try sut.save(download)

        try sut.markFailed(download, error: "Error")

        let fetched = try sut.fetch(id: download.id)
        XCTAssertEqual(fetched?.retryCount, 3)
    }

    func testResetForRetry_setsPendingAndClearsError() throws {
        let download = TestFixtures.makeDownload(status: .failed, errorMessage: "Previous error")
        try sut.save(download)

        try sut.resetForRetry(download)

        let fetched = try sut.fetch(id: download.id)
        XCTAssertEqual(fetched?.status, .pending)
        XCTAssertNil(fetched?.errorMessage)
    }

    // MARK: - Edge Cases

    func testSave_withAllOptionalFieldsNil() throws {
        let download = TestFixtures.makeDownload(
            manifestURL: nil,
            pageTitle: nil,
            pageURL: nil,
            sourceDomain: nil,
            errorMessage: nil,
            quality: nil,
            encryptionKeyURL: nil
        )

        try sut.save(download)

        let fetched = try sut.fetch(id: download.id)
        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched?.manifestURL)
        XCTAssertNil(fetched?.pageTitle)
    }
}
