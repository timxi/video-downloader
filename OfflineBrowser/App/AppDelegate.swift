import UIKit
import BackgroundTasks
import UserNotifications
import AVFoundation
import FirebaseCore
import FirebaseCrashlytics

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - Background Session Completion Handler
    var backgroundSessionCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize Firebase (only if GoogleService-Info.plist exists)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()

            // Enable Crashlytics - disabled in DEBUG builds
            #if DEBUG
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            #else
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            #endif
        } else {
            print("[AppDelegate] GoogleService-Info.plist not found - Firebase disabled")
        }

        // Initialize database
        DatabaseManager.shared.initialize()

        // Cleanup old thumbnails
        FileStorageManager.shared.cleanupOldThumbnails()

        // Register background tasks
        registerBackgroundTasks()

        // Configure audio session for background playback
        configureAudioSession()

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Handle discarded scenes
    }

    // MARK: - Background URL Session

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        backgroundSessionCompletionHandler = completionHandler
        BackgroundSessionManager.shared.handleBackgroundSessionEvents(identifier: identifier)
    }

    // MARK: - Private Methods

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.offlinebrowser.download",
            using: nil
        ) { task in
            self.handleBackgroundDownloadTask(task: task as! BGProcessingTask)
        }
    }

    private func handleBackgroundDownloadTask(task: BGProcessingTask) {
        task.expirationHandler = {
            DownloadManager.shared.pauseAllDownloads()
        }

        DownloadManager.shared.resumePendingDownloads { success in
            task.setTaskCompleted(success: success)
        }
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Memory Warning

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()

        // Clear image cache
        ImageCache.shared.clearCache()

        print("[AppDelegate] Memory warning - cleared caches")
    }
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

        if categoryIdentifier == NotificationManager.downloadCompleteCategory ||
           categoryIdentifier == NotificationManager.downloadFailedCategory {
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
