import UIKit
import SwiftUI

class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
        setupAppearance()
    }

    private func setupTabs() {
        // Browser Tab
        let browserVC = BrowserViewController()
        let browserNav = UINavigationController(rootViewController: browserVC)
        browserNav.tabBarItem = UITabBarItem(
            title: "Browser",
            image: UIImage(systemName: "globe"),
            selectedImage: UIImage(systemName: "globe.fill")
        )
        browserNav.isNavigationBarHidden = true

        // Library Tab
        let libraryView = LibraryView()
        let libraryVC = UIHostingController(rootView: libraryView)
        libraryVC.tabBarItem = UITabBarItem(
            title: "Library",
            image: UIImage(systemName: "folder"),
            selectedImage: UIImage(systemName: "folder.fill")
        )

        // Downloads Tab (shows active/queued downloads)
        let downloadsView = DownloadsView()
        let downloadsVC = UIHostingController(rootView: downloadsView)
        downloadsVC.tabBarItem = UITabBarItem(
            title: "Downloads",
            image: UIImage(systemName: "arrow.down.circle"),
            selectedImage: UIImage(systemName: "arrow.down.circle.fill")
        )

        // Settings Tab
        let settingsView = SettingsView()
        let settingsVC = UIHostingController(rootView: settingsView)
        settingsVC.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gear"),
            selectedImage: UIImage(systemName: "gear.circle.fill")
        )

        viewControllers = [browserNav, libraryVC, downloadsVC, settingsVC]
    }

    private func setupAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }
}
