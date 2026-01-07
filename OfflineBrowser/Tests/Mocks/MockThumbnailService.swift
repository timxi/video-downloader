import Foundation
@testable import OfflineBrowser

final class MockThumbnailService: ThumbnailServiceProtocol {

    // MARK: - Configuration

    /// URL to return from downloadThumbnail. If nil, completion returns nil.
    var downloadResult: URL?

    /// Whether to call completion synchronously (default) or asynchronously
    var callsCompletionAsync = false

    // MARK: - Call Tracking

    var downloadThumbnailCalls: [String] = []

    var downloadThumbnailCallCount: Int {
        downloadThumbnailCalls.count
    }

    // MARK: - ThumbnailServiceProtocol

    func downloadThumbnail(from urlString: String, completion: @escaping (URL?) -> Void) {
        downloadThumbnailCalls.append(urlString)

        if callsCompletionAsync {
            DispatchQueue.main.async { [weak self] in
                completion(self?.downloadResult)
            }
        } else {
            completion(downloadResult)
        }
    }
}
