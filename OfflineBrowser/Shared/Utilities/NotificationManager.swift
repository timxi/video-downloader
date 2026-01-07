import UserNotifications
import UIKit

final class NotificationManager {
    static let shared = NotificationManager()

    // Notification categories
    static let downloadCompleteCategory = "DOWNLOAD_COMPLETE"
    static let downloadFailedCategory = "DOWNLOAD_FAILED"

    private init() {
        registerCategories()
    }

    // MARK: - Setup

    private func registerCategories() {
        let completeCategory = UNNotificationCategory(
            identifier: Self.downloadCompleteCategory,
            actions: [],
            intentIdentifiers: []
        )

        let failedCategory = UNNotificationCategory(
            identifier: Self.downloadFailedCategory,
            actions: [],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            completeCategory,
            failedCategory
        ])
    }

    // MARK: - Authorization

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
            print("Notification authorization granted: \(granted)")
        }
    }

    // MARK: - Download Notifications

    func showDownloadStarted(title: String) {
        // Optionally show a local notification or just update badge
    }

    func showDownloadCompleted(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Self.downloadCompleteCategory

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    func showDownloadFailed(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Failed"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Self.downloadFailedCategory

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Badge Management

    func updateBadge(count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = count
    }

    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}
