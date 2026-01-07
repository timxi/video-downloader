import Foundation
@testable import OfflineBrowser

/// A mock DownloadTask that can be controlled in tests
final class MockDownloadTask: DownloadTaskProtocol {

    // MARK: - DownloadTaskProtocol

    weak var delegate: DownloadTaskDelegate?
    let download: Download

    // MARK: - Control Properties

    var shouldSucceed: Bool = true
    var simulatedError: Error?
    var simulatedVideoURL: URL?
    var progressUpdates: [(Double, Int)] = [(0.5, 50), (1.0, 100)]
    var autoComplete: Bool = true

    // MARK: - Tracking

    private(set) var startCalled = false
    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var cancelCalled = false

    // MARK: - Initialization

    init(download: Download, cookies: [HTTPCookie] = []) {
        self.download = download
    }

    // MARK: - DownloadTaskProtocol Methods

    func start() {
        startCalled = true
        if autoComplete {
            // Simulate async completion
            DispatchQueue.main.async { [weak self] in
                self?.simulateCompletion()
            }
        }
    }

    func pause() {
        pauseCalled = true
    }

    func resume() {
        resumeCalled = true
    }

    func cancel() {
        cancelCalled = true
    }

    // MARK: - Simulation

    func simulateCompletion() {
        // Send progress updates
        for (progress, segments) in progressUpdates {
            delegate?.downloadTask(self, didUpdateProgress: progress, segmentsDownloaded: segments)
        }

        if shouldSucceed {
            let url = simulatedVideoURL ?? URL(fileURLWithPath: "/tmp/test_video.mp4")
            delegate?.downloadTask(self, didCompleteWithURL: url)
        } else {
            let error = simulatedError ?? NSError(domain: "MockDownloadTask", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
            delegate?.downloadTask(self, didFailWithError: error)
        }
    }

    func simulateProgressUpdate(progress: Double, segmentsDownloaded: Int) {
        delegate?.downloadTask(self, didUpdateProgress: progress, segmentsDownloaded: segmentsDownloaded)
    }

    func simulateSuccess(url: URL) {
        delegate?.downloadTask(self, didCompleteWithURL: url)
    }

    func simulateFailure(error: Error) {
        delegate?.downloadTask(self, didFailWithError: error)
    }
}

/// A factory that creates MockDownloadTasks for testing
final class MockDownloadTaskFactory: DownloadTaskFactoryProtocol {

    // MARK: - Tracking

    private(set) var createdTasks: [MockDownloadTask] = []

    // MARK: - Configuration

    var shouldSucceed: Bool = true
    var simulatedError: Error?
    var simulatedVideoURL: URL?
    var autoComplete: Bool = true

    // MARK: - DownloadTaskFactoryProtocol

    func makeDownloadTask(download: Download, cookies: [HTTPCookie]) -> DownloadTaskProtocol {
        let task = MockDownloadTask(download: download, cookies: cookies)
        task.shouldSucceed = shouldSucceed
        task.simulatedError = simulatedError
        task.simulatedVideoURL = simulatedVideoURL
        task.autoComplete = autoComplete

        createdTasks.append(task)
        return task
    }

    // MARK: - Helpers

    var lastCreatedTask: MockDownloadTask? {
        createdTasks.last
    }

    func reset() {
        createdTasks.removeAll()
        shouldSucceed = true
        simulatedError = nil
        simulatedVideoURL = nil
        autoComplete = true
    }
}
