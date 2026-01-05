import UIKit

final class ThemeManager {
    static let shared = ThemeManager()

    private init() {}

    // MARK: - Public Methods

    func setTheme(_ mode: String) {
        PreferenceRepository.shared.themeMode = mode

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        for window in windowScene.windows {
            applyTheme(to: window)
        }
    }

    func applyTheme(to window: UIWindow) {
        let mode = PreferenceRepository.shared.themeMode

        switch mode {
        case "light":
            window.overrideUserInterfaceStyle = .light
        case "dark":
            window.overrideUserInterfaceStyle = .dark
        default:
            window.overrideUserInterfaceStyle = .unspecified
        }
    }

    var currentTheme: String {
        PreferenceRepository.shared.themeMode
    }
}
