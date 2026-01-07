import Foundation
@testable import OfflineBrowser

final class MockNotificationManager: NotificationManagerProtocol {

    // MARK: - Tracking

    private(set) var startedTitles: [String] = []
    private(set) var completedTitles: [String] = []
    private(set) var failedTitles: [String] = []
    private(set) var storageFullCount: Int = 0

    // MARK: - NotificationManagerProtocol

    func showDownloadStarted(title: String) {
        startedTitles.append(title)
    }

    func showDownloadCompleted(title: String) {
        completedTitles.append(title)
    }

    func showDownloadFailed(title: String) {
        failedTitles.append(title)
    }

    func showStorageFull() {
        storageFullCount += 1
    }

    // MARK: - Assertions

    var didNotifyStarted: Bool {
        !startedTitles.isEmpty
    }

    var didNotifyCompleted: Bool {
        !completedTitles.isEmpty
    }

    var didNotifyFailed: Bool {
        !failedTitles.isEmpty
    }

    var didNotifyStorageFull: Bool {
        storageFullCount > 0
    }

    // MARK: - Helpers

    func reset() {
        startedTitles.removeAll()
        completedTitles.removeAll()
        failedTitles.removeAll()
        storageFullCount = 0
    }
}
