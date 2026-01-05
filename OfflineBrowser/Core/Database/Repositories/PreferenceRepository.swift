import Foundation
import GRDB

final class PreferenceRepository {
    static let shared = PreferenceRepository()
    private let dbPool: DatabasePool

    private init() {
        self.dbPool = DatabaseManager.shared.databasePool
    }

    // MARK: - Get/Set

    func get(_ key: PreferenceKey) -> String {
        do {
            return try dbPool.read { db in
                try Preference.fetchOne(db, key: key.rawValue)?.value ?? key.defaultValue
            }
        } catch {
            return key.defaultValue
        }
    }

    func set(_ key: PreferenceKey, value: String) {
        do {
            try dbPool.write { db in
                let preference = Preference(key: key.rawValue, value: value)
                try preference.save(db, onConflict: .replace)
            }
        } catch {
            print("Failed to save preference: \(error)")
        }
    }

    // MARK: - Typed Accessors

    func getBool(_ key: PreferenceKey) -> Bool {
        get(key) == "true"
    }

    func setBool(_ key: PreferenceKey, value: Bool) {
        set(key, value: value ? "true" : "false")
    }

    func getDouble(_ key: PreferenceKey) -> Double {
        Double(get(key)) ?? Double(key.defaultValue) ?? 0
    }

    func setDouble(_ key: PreferenceKey, value: Double) {
        set(key, value: String(value))
    }

    func getInt(_ key: PreferenceKey) -> Int {
        Int(get(key)) ?? Int(key.defaultValue) ?? 0
    }

    func setInt(_ key: PreferenceKey, value: Int) {
        set(key, value: String(value))
    }

    // MARK: - Convenience Properties

    var preferredQuality: String {
        get { get(.preferredQuality) }
        set { set(.preferredQuality, value: newValue) }
    }

    var allowCellularDownload: Bool {
        get { getBool(.allowCellularDownload) }
        set { setBool(.allowCellularDownload, value: newValue) }
    }

    var defaultPlaybackSpeed: Double {
        get { getDouble(.defaultPlaybackSpeed) }
        set { setDouble(.defaultPlaybackSpeed, value: newValue) }
    }

    var backgroundAudioEnabled: Bool {
        get { getBool(.backgroundAudioEnabled) }
        set { setBool(.backgroundAudioEnabled, value: newValue) }
    }

    var rememberPlaybackPosition: Bool {
        get { getBool(.rememberPlaybackPosition) }
        set { setBool(.rememberPlaybackPosition, value: newValue) }
    }

    var themeMode: String {
        get { get(.themeMode) }
        set { set(.themeMode, value: newValue) }
    }

    // MARK: - Hints

    var hasSeenDownloadPillHint: Bool {
        get { getBool(.hasSeenDownloadPillHint) }
        set { setBool(.hasSeenDownloadPillHint, value: newValue) }
    }

    var hasSeenGestureHint: Bool {
        get { getBool(.hasSeenGestureHint) }
        set { setBool(.hasSeenGestureHint, value: newValue) }
    }

    var hasSeenFolderHint: Bool {
        get { getBool(.hasSeenFolderHint) }
        set { setBool(.hasSeenFolderHint, value: newValue) }
    }
}
