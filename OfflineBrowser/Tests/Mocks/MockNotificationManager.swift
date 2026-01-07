import Foundation
@testable import OfflineBrowser

final class MockNotificationManager: NotificationManagerProtocol {

    // MARK: - Tracking

    private(set) var startedTitles: [String] = []
    private(set) var completedTitles: [String] = []
    private(set) var failedTitles: [String] = []

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

    // MARK: - Helpers

    func reset() {
        startedTitles.removeAll()
        completedTitles.removeAll()
        failedTitles.removeAll()
    }
}
