import Foundation
@testable import OfflineBrowser

final class MockDownloadTaskDelegate: DownloadTaskDelegate {

    // MARK: - Tracking

    private(set) var progressUpdates: [(progress: Double, segmentsDownloaded: Int)] = []
    private(set) var completedURLs: [URL] = []
    private(set) var errors: [Error] = []

    // MARK: - Expectations

    var onProgressUpdate: ((Double, Int) -> Void)?
    var onComplete: ((URL) -> Void)?
    var onFail: ((Error) -> Void)?

    // MARK: - DownloadTaskDelegate

    func downloadTask(_ task: DownloadTaskProtocol, didUpdateProgress progress: Double, segmentsDownloaded: Int) {
        progressUpdates.append((progress: progress, segmentsDownloaded: segmentsDownloaded))
        onProgressUpdate?(progress, segmentsDownloaded)
    }

    func downloadTask(_ task: DownloadTaskProtocol, didCompleteWithURL url: URL) {
        completedURLs.append(url)
        onComplete?(url)
    }

    func downloadTask(_ task: DownloadTaskProtocol, didFailWithError error: Error) {
        errors.append(error)
        onFail?(error)
    }

    // MARK: - Assertions

    var didComplete: Bool {
        !completedURLs.isEmpty
    }

    var didFail: Bool {
        !errors.isEmpty
    }

    var lastProgress: Double? {
        progressUpdates.last?.progress
    }

    var lastSegmentsDownloaded: Int? {
        progressUpdates.last?.segmentsDownloaded
    }

    var lastError: Error? {
        errors.last
    }

    var lastCompletedURL: URL? {
        completedURLs.last
    }

    // MARK: - Helpers

    func reset() {
        progressUpdates.removeAll()
        completedURLs.removeAll()
        errors.removeAll()
        onProgressUpdate = nil
        onComplete = nil
        onFail = nil
    }
}
