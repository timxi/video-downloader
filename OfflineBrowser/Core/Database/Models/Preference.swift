import Foundation
import GRDB

struct Preference: Codable {
    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

// MARK: - GRDB Conformance

extension Preference: FetchableRecord, PersistableRecord {
    static let databaseTableName = "preferences"
}

// MARK: - Preference Keys

enum PreferenceKey: String {
    // Download settings
    case preferredQuality = "download.preferredQuality"
    case allowCellularDownload = "download.allowCellular"

    // Playback settings
    case defaultPlaybackSpeed = "playback.defaultSpeed"
    case backgroundAudioEnabled = "playback.backgroundAudio"
    case rememberPlaybackPosition = "playback.rememberPosition"

    // Appearance
    case themeMode = "appearance.theme" // "light", "dark", "system"

    // Onboarding hints
    case hasSeenDownloadPillHint = "hints.downloadPill"
    case hasSeenGestureHint = "hints.gestures"
    case hasSeenFolderHint = "hints.folders"

    // Statistics
    case totalDownloadsCount = "stats.downloadCount"
}

// MARK: - Default Values

extension PreferenceKey {
    var defaultValue: String {
        switch self {
        case .preferredQuality:
            return "highest"
        case .allowCellularDownload:
            return "false"
        case .defaultPlaybackSpeed:
            return "1.0"
        case .backgroundAudioEnabled:
            return "true"
        case .rememberPlaybackPosition:
            return "true"
        case .themeMode:
            return "system"
        case .hasSeenDownloadPillHint,
             .hasSeenGestureHint,
             .hasSeenFolderHint:
            return "false"
        case .totalDownloadsCount:
            return "0"
        }
    }
}
