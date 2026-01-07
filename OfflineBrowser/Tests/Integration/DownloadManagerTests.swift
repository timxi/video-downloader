import XCTest
import GRDB
@testable import OfflineBrowser

final class DownloadManagerTests: XCTestCase {

    var dbPool: DatabasePool!
    var mockDownloadRepo: MockDownloadRepository!
    var mockVideoRepo: MockVideoRepository!
    var mockFolderRepo: MockFolderRepository!
    var mockFileStorage: MockFileStorageManager!
    var mockTaskFactory: MockDownloadTaskFactory!
    var mockNotificationManager: MockNotificationManager!
    var mockThumbnailService: MockThumbnailService!
    var sut: DownloadManager!

    override func setUp() {
        super.setUp()
        dbPool = try! TestDatabaseManager.makeInMemoryDatabasePool()
        mockDownloadRepo = MockDownloadRepository()
        mockVideoRepo = MockVideoRepository()
        mockFolderRepo = MockFolderRepository()
        mockFileStorage = MockFileStorageManager()
        mockTaskFactory = MockDownloadTaskFactory()
        mockTaskFactory.autoComplete = false // Control timing manually
        mockNotificationManager = MockNotificationManager()
        mockThumbnailService = MockThumbnailService()

        sut = DownloadManager(
            downloadRepository: mockDownloadRepo,
            videoRepository: mockVideoRepo,
            folderRepository: mockFolderRepo,
            fileStorage: mockFileStorage,
            taskFactory: mockTaskFactory,
            notificationManager: mockNotificationManager,
            thumbnailService: mockThumbnailService,
            skipLoadPending: true
        )
    }

    override func tearDown() {
        sut = nil
        mockDownloadRepo = nil
        mockVideoRepo = nil
        mockFolderRepo = nil
        mockFileStorage = nil
        mockTaskFactory = nil
        mockNotificationManager = nil
        mockThumbnailService = nil
        dbPool = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_noActiveDownload() {
        XCTAssertNil(sut.activeDownload)
    }

    func testInitialState_emptyQueue() {
        XCTAssertTrue(sut.downloadQueue.isEmpty)
    }

    func testInitialState_hasPendingDownloads_returnsFalse() {
        XCTAssertFalse(sut.hasPendingDownloads)
    }

    // MARK: - Cancel Download Tests

    func testCancelDownload_removesFromQueue() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.downloads = [download]

        sut.cancelDownload(download)

        XCTAssertTrue(mockDownloadRepo.deletedDownloads.contains { $0.id == download.id })
    }

    func testCancelDownload_cancelsActiveDownload() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        if let activeDownload = sut.activeDownload {
            sut.cancelDownload(activeDownload)
            XCTAssertNil(sut.activeDownload)
        }
    }

    // MARK: - Retry Download Tests

    func testRetryDownload_resetsForRetry() {
        let download = TestFixtures.makeDownload(status: .failed)
        mockDownloadRepo.downloads = [download]

        sut.retryDownload(download)

        XCTAssertTrue(mockDownloadRepo.resetDownloads.contains { $0.id == download.id })
    }

    // MARK: - Pause/Resume Tests

    func testPauseAllDownloads_updatesStatus() {
        let download = TestFixtures.makeDownload(status: .downloading)
        mockDownloadRepo.downloads = [download]

        sut.pauseAllDownloads()
    }

    func testResumePendingDownloads_triggersProcessNext() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]

        var completionCalled = false
        sut.resumePendingDownloads { success in
            completionCalled = true
            XCTAssertTrue(success)
        }

        XCTAssertTrue(completionCalled)
    }

    // MARK: - Download Lifecycle Tests

    func testDownloadLifecycle_statusUpdatedToDownloading() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]
        mockDownloadRepo.downloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp = self.expectation(description: "Wait for status update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockDownloadRepo.statusUpdates.contains { $0.status == .downloading })
    }

    func testDownloadLifecycle_taskCreatedWithCorrectDownload() {
        let download = TestFixtures.makeDownload(pageTitle: "Test Video")
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(mockTaskFactory.createdTasks.count, 1)
        XCTAssertEqual(mockTaskFactory.lastCreatedTask?.download.pageTitle, "Test Video")
    }

    func testDownloadLifecycle_taskStarted() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp = self.expectation(description: "Wait for task start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockTaskFactory.lastCreatedTask?.startCalled ?? false)
    }

    // MARK: - Progress Update Tests

    func testProgressUpdate_updatesActiveDownload() {
        let download = TestFixtures.makeDownload(progress: 0)
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        if let task = mockTaskFactory.lastCreatedTask {
            task.simulateProgressUpdate(progress: 0.5, segmentsDownloaded: 50)
        }

        let exp2 = self.expectation(description: "Wait for progress update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(sut.activeDownload?.progress ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(sut.activeDownload?.segmentsDownloaded, 50)
    }

    func testProgressUpdate_persistsToRepository() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateProgressUpdate(progress: 0.75, segmentsDownloaded: 75)

        let exp2 = self.expectation(description: "Wait for progress persist")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockDownloadRepo.progressUpdates.contains { abs($0.progress - 0.75) < 0.01 })
    }

    // MARK: - Completion Tests

    func testDownloadCompletion_createsVideo() {
        let download = TestFixtures.makeDownload(pageTitle: "Test Video")
        mockDownloadRepo.pendingDownloads = [download]
        mockFileStorage.fileExistsResult = true
        mockFileStorage.fileSizeResult = 1_000_000

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        let videoURL = URL(fileURLWithPath: "/tmp/test_video.mp4")
        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: videoURL)

        let exp2 = self.expectation(description: "Wait for completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockVideoRepo.savedVideos.contains { $0.title == "Test Video" })
    }

    func testDownloadCompletion_notifiesSuccess() {
        let download = TestFixtures.makeDownload(pageTitle: "My Video")
        mockDownloadRepo.pendingDownloads = [download]
        mockFileStorage.fileExistsResult = true

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: URL(fileURLWithPath: "/tmp/test.mp4"))

        let exp2 = self.expectation(description: "Wait for notification")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockNotificationManager.didNotifyCompleted)
    }

    func testDownloadCompletion_clearsActiveDownload() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]
        mockFileStorage.fileExistsResult = true

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: URL(fileURLWithPath: "/tmp/test.mp4"))

        let exp2 = self.expectation(description: "Wait for cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertNil(sut.activeDownload)
    }

    func testDownloadCompletion_deletesDownloadRecord() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]
        mockDownloadRepo.downloads = [download]
        mockFileStorage.fileExistsResult = true

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: URL(fileURLWithPath: "/tmp/test.mp4"))

        let exp2 = self.expectation(description: "Wait for delete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockDownloadRepo.deletedDownloads.contains { $0.id == download.id })
    }

    func testDownloadCompletion_cleansTempFiles() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]
        mockFileStorage.fileExistsResult = true

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: URL(fileURLWithPath: "/tmp/test.mp4"))

        let exp2 = self.expectation(description: "Wait for cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockFileStorage.deletedDownloads.contains { $0.id == download.id })
    }

    // MARK: - Failure Tests

    func testDownloadFailure_marksAsFailed() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        mockTaskFactory.lastCreatedTask?.simulateFailure(error: error)

        let exp2 = self.expectation(description: "Wait for failure handling")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockDownloadRepo.failedDownloads.contains { $0.id == download.id })
    }

    func testDownloadFailure_notifiesFailure() {
        let download = TestFixtures.makeDownload(pageTitle: "Failed Video")
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateFailure(error: NSError(domain: "Test", code: 1))

        let exp2 = self.expectation(description: "Wait for notification")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(mockNotificationManager.didNotifyFailed)
    }

    func testDownloadFailure_clearsActiveDownload() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateFailure(error: NSError(domain: "Test", code: 1))

        let exp2 = self.expectation(description: "Wait for cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertNil(sut.activeDownload)
    }

    // MARK: - Queue FIFO Tests

    func testQueueProcessing_fifoOrder() {
        let download1 = TestFixtures.makeDownload(pageTitle: "First")
        let download2 = TestFixtures.makeDownload(pageTitle: "Second")
        mockDownloadRepo.pendingDownloads = [download1, download2]

        sut.resumePendingDownloads(completion: nil)

        let exp = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(mockTaskFactory.createdTasks.first?.download.pageTitle, "First")
    }

    func testQueueProcessing_processesNextAfterCompletion() {
        let download1 = TestFixtures.makeDownload(pageTitle: "First")
        let download2 = TestFixtures.makeDownload(pageTitle: "Second")
        mockDownloadRepo.pendingDownloads = [download1, download2]
        mockFileStorage.fileExistsResult = true

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for first task")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: URL(fileURLWithPath: "/tmp/test.mp4"))

        let exp2 = self.expectation(description: "Wait for second task")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(mockTaskFactory.createdTasks.count, 2)
        XCTAssertEqual(mockTaskFactory.createdTasks.last?.download.pageTitle, "Second")
    }

    // MARK: - Has Pending Downloads Tests

    func testHasPendingDownloads_withQueuedDownloads_returnsTrue() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]

        sut.resumePendingDownloads(completion: nil)

        let exp = self.expectation(description: "Wait for queue update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertTrue(sut.hasPendingDownloads)
    }

    func testHasPendingDownloads_afterAllCompleted_returnsFalse() {
        let download = TestFixtures.makeDownload()
        mockDownloadRepo.pendingDownloads = [download]
        mockFileStorage.fileExistsResult = true

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: URL(fileURLWithPath: "/tmp/test.mp4"))

        let exp2 = self.expectation(description: "Wait for completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertFalse(sut.hasPendingDownloads)
    }

    // MARK: - Auto Folder Creation Tests

    func testDownloadCompletion_createsAutoFolderForDomain() {
        let download = TestFixtures.makeDownload(sourceDomain: "example.com")
        mockDownloadRepo.pendingDownloads = [download]
        mockFileStorage.fileExistsResult = true

        sut.resumePendingDownloads(completion: nil)

        let exp1 = self.expectation(description: "Wait for task creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        waitForExpectations(timeout: 1)

        mockTaskFactory.lastCreatedTask?.simulateSuccess(url: URL(fileURLWithPath: "/tmp/test.mp4"))

        let exp2 = self.expectation(description: "Wait for folder creation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(mockFolderRepo.autoFolderDomains.first, "example.com")
    }
}
