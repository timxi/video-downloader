import Foundation
import FirebaseCore
import FirebaseCrashlytics

final class CrashReporter {
    static let shared = CrashReporter()

    private var isFirebaseConfigured: Bool {
        FirebaseApp.app() != nil
    }

    private init() {}

    // MARK: - Non-Fatal Errors

    func logError(_ error: Error, context: [String: Any]? = nil) {
        guard isFirebaseConfigured else { return }

        var userInfo: [String: Any] = context ?? [:]
        userInfo["error_description"] = error.localizedDescription

        let nsError = NSError(
            domain: "OfflineBrowser",
            code: (error as NSError).code,
            userInfo: userInfo as [String: Any]
        )

        Crashlytics.crashlytics().record(error: nsError)
    }

    func logDownloadError(_ error: Error, url: String, retryCount: Int) {
        logError(error, context: [
            "download_url": url,
            "retry_count": retryCount,
            "error_type": "download_failure"
        ])
    }

    func logParseError(_ error: Error, manifestURL: String) {
        logError(error, context: [
            "manifest_url": manifestURL,
            "error_type": "parse_failure"
        ])
    }

    func logMuxError(_ error: Error, segmentCount: Int) {
        logError(error, context: [
            "segment_count": segmentCount,
            "error_type": "mux_failure"
        ])
    }

    func logDatabaseError(_ error: Error, operation: String) {
        logError(error, context: [
            "operation": operation,
            "error_type": "database_failure"
        ])
    }

    // MARK: - Custom Keys

    func setUserProperty(_ key: String, value: String) {
        guard isFirebaseConfigured else { return }
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func setDownloadQueueSize(_ size: Int) {
        setUserProperty("download_queue_size", value: String(size))
    }

    func setVideoCount(_ count: Int) {
        setUserProperty("video_count", value: String(count))
    }

    // MARK: - Breadcrumbs

    func log(_ message: String) {
        guard isFirebaseConfigured else { return }
        Crashlytics.crashlytics().log(message)
    }
}
