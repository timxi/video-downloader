import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingClearAlert = false
    @State private var showingClearCookiesAlert = false

    var body: some View {
        NavigationView {
            Form {
                downloadSection
                playbackSection
                appearanceSection
                storageSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Download Section

    private var downloadSection: some View {
        Section {
            Picker("Preferred Quality", selection: $viewModel.preferredQuality) {
                Text("Highest Available").tag("highest")
                Text("1080p").tag("1080p")
                Text("720p").tag("720p")
                Text("Lowest (Save Data)").tag("lowest")
            }

            Toggle("Allow Cellular Downloads", isOn: $viewModel.allowCellular)
        } header: {
            Text("Downloads")
        } footer: {
            Text("Cellular downloads may use significant mobile data.")
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        Section("Playback") {
            Picker("Default Speed", selection: $viewModel.defaultPlaybackSpeed) {
                Text("0.5x").tag(0.5)
                Text("0.75x").tag(0.75)
                Text("1x (Normal)").tag(1.0)
                Text("1.25x").tag(1.25)
                Text("1.5x").tag(1.5)
                Text("2x").tag(2.0)
            }

            Toggle("Background Audio", isOn: $viewModel.backgroundAudio)
            Toggle("Remember Playback Position", isOn: $viewModel.rememberPosition)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $viewModel.themeMode) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .onChange(of: viewModel.themeMode) { newValue in
                ThemeManager.shared.setTheme(newValue)
            }
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            HStack {
                Text("Storage Used")
                Spacer()
                Text(viewModel.storageUsed)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                showingClearAlert = true
            } label: {
                Text("Clear All Downloads")
            }
            .alert("Clear All Downloads?", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    viewModel.clearAllDownloads()
                }
            } message: {
                Text("This will permanently delete all downloaded videos. This action cannot be undone.")
            }
        } header: {
            Text("Storage")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section("Privacy") {
            Button("Clear Browsing Data") {
                viewModel.clearBrowsingData()
            }

            Button("Clear Cookies") {
                showingClearCookiesAlert = true
            }
            .alert("Clear Cookies?", isPresented: $showingClearCookiesAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    viewModel.clearCookies()
                }
            } message: {
                Text("This will log you out of all websites.")
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundStyle(.secondary)
            }

            NavigationLink("Licenses") {
                LicensesView()
            }
        }
    }
}

// MARK: - View Model

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var preferredQuality: String {
        didSet { PreferenceRepository.shared.preferredQuality = preferredQuality }
    }
    @Published var allowCellular: Bool {
        didSet {
            PreferenceRepository.shared.allowCellularDownload = allowCellular
            BackgroundSessionManager.shared.updateCellularAccess()
        }
    }
    @Published var defaultPlaybackSpeed: Double {
        didSet { PreferenceRepository.shared.defaultPlaybackSpeed = defaultPlaybackSpeed }
    }
    @Published var backgroundAudio: Bool {
        didSet { PreferenceRepository.shared.backgroundAudioEnabled = backgroundAudio }
    }
    @Published var rememberPosition: Bool {
        didSet { PreferenceRepository.shared.rememberPlaybackPosition = rememberPosition }
    }
    @Published var themeMode: String {
        didSet { PreferenceRepository.shared.themeMode = themeMode }
    }
    @Published var storageUsed: String = "Calculating..."

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    init() {
        preferredQuality = PreferenceRepository.shared.preferredQuality
        allowCellular = PreferenceRepository.shared.allowCellularDownload
        defaultPlaybackSpeed = PreferenceRepository.shared.defaultPlaybackSpeed
        backgroundAudio = PreferenceRepository.shared.backgroundAudioEnabled
        rememberPosition = PreferenceRepository.shared.rememberPlaybackPosition
        themeMode = PreferenceRepository.shared.themeMode

        calculateStorageUsed()
    }

    func calculateStorageUsed() {
        storageUsed = FileStorageManager.shared.formattedTotalStorageUsed
    }

    func clearAllDownloads() {
        do {
            try VideoRepository.shared.deleteAll()
            FileStorageManager.shared.deleteAllVideos()
            calculateStorageUsed()
        } catch {
            print("Failed to clear downloads: \(error)")
        }
    }

    func clearBrowsingData() {
        // This would need a reference to the webview
        // For now, just clear website data
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {}
        }
    }

    func clearCookies() {
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: [WKWebsiteDataTypeCookies]) { records in
            dataStore.removeData(ofTypes: [WKWebsiteDataTypeCookies], for: records) {}
        }
    }
}

import WebKit

// MARK: - Licenses View

struct LicensesView: View {
    var body: some View {
        List {
            Section {
                LicenseRow(name: "GRDB.swift", license: "MIT License")
                LicenseRow(name: "Firebase", license: "Apache 2.0 License")
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicenseRow: View {
    let name: String
    let license: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.body)
            Text(license)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
