import UIKit
import BackgroundTasks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - Background Session Completion Handler
    var backgroundSessionCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize database
        DatabaseManager.shared.initialize()

        // Register background tasks
        registerBackgroundTasks()

        // Configure audio session for background playback
        configureAudioSession()

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
}

import AVFoundation
