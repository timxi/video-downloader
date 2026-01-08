# Phase 12: Notifications & Crashlytics

**Status**: ✅ Complete

## Overview

Complete Phase 12 by fixing local notification gaps and adding Firebase Crashlytics for crash reporting.

**Final State** (100% complete):
- ✅ NotificationManager singleton with notification categories
- ✅ `showDownloadCompleted()` / `showDownloadFailed()` with category identifiers
- ✅ Badge management implemented
- ✅ `requestAuthorization()` called on first download
- ✅ Tapping notification navigates to Library (UNUserNotificationCenterDelegate)
- ✅ Firebase Crashlytics initialized (conditional - requires GoogleService-Info.plist)
- ✅ CrashReporter utility for non-fatal error logging
- ✅ Error logging integrated in DownloadManager, HLSParser, FFmpegMuxer

---

## Part 1: Local Notifications Fixes

### Issue 1: Permission Never Requested

`NotificationManager.requestAuthorization()` exists but is never called.

**Fix**: Call on first download attempt.

**Modify**: `OfflineBrowser/Features/Download/Engine/DownloadManager.swift`

```swift
private func createAndQueueDownload(stream: DetectedStream, pageTitle: String?, pageURL: URL?, thumbnailURL: String? = nil, cookies: [HTTPCookie]) {
    // Request notification permission on first download
    if !PreferenceRepository.shared.getBool(.hasRequestedNotificationPermission) {
        NotificationManager.shared.requestAuthorization()
        PreferenceRepository.shared.setBool(.hasRequestedNotificationPermission, value: true)
    }

    // ... existing code
}
```

**Modify**: `OfflineBrowser/Core/Database/Models/Preference.swift`

Add preference key:
```swift
case hasRequestedNotificationPermission = "notifications.hasRequestedPermission"
```

---

### Issue 2: Notification Tap Doesn't Navigate

Tapping a download notification should open the Library tab.

**Solution**: Implement `UNUserNotificationCenterDelegate` in AppDelegate.

**Modify**: `OfflineBrowser/App/AppDelegate.swift`

```swift
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // ... existing code

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // ... existing methods
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Handle notification tap when app is in background/terminated
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier

        if categoryIdentifier == "DOWNLOAD_COMPLETE" || categoryIdentifier == "DOWNLOAD_FAILED" {
            // Navigate to Library tab
            navigateToLibrary()
        }

        completionHandler()
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func navigateToLibrary() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first,
                  let tabBarController = window.rootViewController as? UITabBarController else {
                return
            }
            tabBarController.selectedIndex = 1 // Library tab
        }
    }
}
```

**Modify**: `OfflineBrowser/Shared/Utilities/NotificationManager.swift`

Add category identifiers:
```swift
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

    // ... existing requestAuthorization()

    func showDownloadCompleted(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Self.downloadCompleteCategory

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
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

    // ... existing badge methods
}
```

---

## Part 2: Firebase Crashlytics

### Prerequisites

1. **Create Firebase Project**: Go to [Firebase Console](https://console.firebase.google.com)
2. **Add iOS App**: Bundle ID `com.offlinebrowser.app`
3. **Download `GoogleService-Info.plist`**: Place in `OfflineBrowser/Resources/`

### Step 2.1: Add GoogleService-Info.plist to Project

**Modify**: `OfflineBrowser/project.yml`

Add to resources:
```yaml
resources:
  - path: Resources/Assets.xcassets
  - path: Resources/NetworkInterceptor.js
  - path: Resources/GoogleService-Info.plist
```

### Step 2.2: Initialize Firebase

**Modify**: `OfflineBrowser/App/AppDelegate.swift`

```swift
import UIKit
import BackgroundTasks
import UserNotifications
import FirebaseCore
import FirebaseCrashlytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var backgroundSessionCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize Firebase
        FirebaseApp.configure()

        // Enable Crashlytics debug logging in debug builds
        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif

        // Initialize database
        DatabaseManager.shared.initialize()

        // Register background tasks
        registerBackgroundTasks()

        // Configure audio session for background playback
        configureAudioSession()

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // ... rest of existing methods
}
```

### Step 2.3: Add Non-Fatal Error Logging

Create a crash reporting helper for consistent error logging.

**Create**: `OfflineBrowser/Shared/Utilities/CrashReporter.swift`

```swift
import Foundation
import FirebaseCrashlytics

final class CrashReporter {
    static let shared = CrashReporter()

    private init() {}

    // MARK: - Non-Fatal Errors

    func logError(_ error: Error, context: [String: Any]? = nil) {
        var userInfo = context ?? [:]
        userInfo["error_description"] = error.localizedDescription

        let nsError = NSError(
            domain: "OfflineBrowser",
            code: (error as NSError).code,
            userInfo: userInfo
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
        Crashlytics.crashlytics().log(message)
    }
}
```

### Step 2.4: Integrate Error Logging

**Modify**: `OfflineBrowser/Features/Download/Engine/DownloadManager.swift`

Add error logging in failure cases:
```swift
// In downloadTask(_:didFailWithError:)
func downloadTask(_ task: DownloadTaskProtocol, didFailWithError error: Error) {
    guard let download = activeDownload else { return }

    // Log to Crashlytics
    CrashReporter.shared.logDownloadError(
        error,
        url: download.videoURL,
        retryCount: download.retryCount
    )

    try? downloadRepository.markFailed(download, error: error.localizedDescription)
    // ... rest of existing code
}
```

**Modify**: `OfflineBrowser/Features/Browser/Detection/HLSParser.swift`

Add error logging:
```swift
// In parse error handling
catch {
    CrashReporter.shared.logParseError(error, manifestURL: url.absoluteString)
    throw error
}
```

**Modify**: `OfflineBrowser/Features/Download/Muxing/FFmpegMuxer.swift`

Add error logging:
```swift
// In mux failure
if returnCode != 0 {
    let error = NSError(domain: "FFmpeg", code: Int(returnCode), userInfo: nil)
    CrashReporter.shared.logMuxError(error, segmentCount: segmentPaths.count)
    // ... existing error handling
}
```

### Step 2.5: Disable Crashlytics in Tests

**Modify**: `OfflineBrowser/Tests/Helpers/TestSetup.swift` (create if needed)

```swift
import XCTest
import FirebaseCrashlytics

class BaseTestCase: XCTestCase {
    override class func setUp() {
        super.setUp()
        // Disable Crashlytics during tests
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
    }
}
```

---

## Implementation Order

| Step | Task | File(s) | Complexity |
|------|------|---------|------------|
| 1 | Add notification permission preference key | Preference.swift | Low |
| 2 | Request permission on first download | DownloadManager.swift | Low |
| 3 | Add notification categories | NotificationManager.swift | Low |
| 4 | Add UNUserNotificationCenterDelegate | AppDelegate.swift | Medium |
| 5 | Create GoogleService-Info.plist | Resources/ (manual) | Low |
| 6 | Add plist to project.yml resources | project.yml | Low |
| 7 | Initialize Firebase in AppDelegate | AppDelegate.swift | Low |
| 8 | Create CrashReporter utility | CrashReporter.swift (new) | Medium |
| 9 | Integrate error logging in DownloadManager | DownloadManager.swift | Low |
| 10 | Integrate error logging in HLSParser | HLSParser.swift | Low |
| 11 | Integrate error logging in FFmpegMuxer | FFmpegMuxer.swift | Low |
| 12 | Disable Crashlytics in tests | TestSetup.swift | Low |

---

## Testing Checklist

### Local Notifications
- [ ] First download triggers permission request
- [ ] Subsequent downloads don't re-request
- [ ] Download complete notification appears
- [ ] Download failed notification appears
- [ ] Tapping notification opens Library tab
- [ ] Notifications show when app is in foreground (banner)

### Firebase Crashlytics
- [ ] App launches without crash after Firebase init
- [ ] Test crash appears in Firebase console (debug only)
- [ ] Non-fatal errors logged for download failures
- [ ] Non-fatal errors logged for parse failures
- [ ] Custom keys visible in crash reports
- [ ] Crashlytics disabled in unit tests

---

## Files Summary

| Action | File | Description |
|--------|------|-------------|
| **Create** | `Resources/GoogleService-Info.plist` | Firebase config (manual download) |
| **Create** | `Shared/Utilities/CrashReporter.swift` | Crashlytics wrapper |
| **Modify** | `Core/Database/Models/Preference.swift` | Add permission key |
| **Modify** | `App/AppDelegate.swift` | Firebase init + notification delegate |
| **Modify** | `Shared/Utilities/NotificationManager.swift` | Categories + tap handling |
| **Modify** | `Features/Download/Engine/DownloadManager.swift` | Permission request + error logging |
| **Modify** | `Features/Browser/Detection/HLSParser.swift` | Error logging |
| **Modify** | `Features/Download/Muxing/FFmpegMuxer.swift` | Error logging |
| **Modify** | `project.yml` | Add GoogleService-Info.plist resource |

---

## Notes

### Firebase Setup Required
Before implementation, you must:
1. Create a Firebase project at https://console.firebase.google.com
2. Add an iOS app with bundle ID `com.offlinebrowser.app`
3. Download `GoogleService-Info.plist`
4. Place it in `OfflineBrowser/Resources/`

### Privacy Considerations
- Crashlytics collects crash data automatically
- No PII is logged (no user IDs, emails, etc.)
- Custom keys only contain non-identifying metrics (queue size, video count)
- Collection is disabled in DEBUG builds
