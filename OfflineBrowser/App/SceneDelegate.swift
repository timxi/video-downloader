import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)

        let tabBarController = MainTabBarController()
        window.rootViewController = tabBarController

        // Apply saved theme
        ThemeManager.shared.applyTheme(to: window)

        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Save any pending state
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Resume downloads if needed
        DownloadManager.shared.resumePendingDownloads(completion: nil)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Pause non-essential work
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Refresh UI if needed
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Save state and schedule background tasks
        scheduleBackgroundDownloadTask()
    }

    // MARK: - Private Methods

    private func scheduleBackgroundDownloadTask() {
        guard DownloadManager.shared.hasPendingDownloads else { return }

        let request = BGProcessingTaskRequest(identifier: "com.offlinebrowser.download")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
}

import BackgroundTasks
