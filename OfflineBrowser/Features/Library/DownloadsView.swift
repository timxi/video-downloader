import SwiftUI

struct DownloadsView: View {
    @StateObject private var viewModel = DownloadsViewModel()

    var body: some View {
        NavigationView {
            Group {
                if viewModel.downloads.isEmpty {
                    emptyStateView
                } else {
                    downloadsList
                }
            }
            .navigationTitle("Downloads")
        }
        .navigationViewStyle(.stack)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Active Downloads")
                .font(.title2)
                .fontWeight(.semibold)

            Text("When you start downloading a video, it will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var downloadsList: some View {
        List {
            ForEach(viewModel.downloads) { download in
                DownloadRow(download: download)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.cancelDownload(download)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if download.status == .failed {
                            Button {
                                viewModel.retryDownload(download)
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Download Row

struct DownloadRow: View {
    let download: Download

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(download.pageTitle ?? "Downloading...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                statusBadge
            }

            if download.status == .downloading || download.status == .muxing {
                ProgressView(value: download.progress)
                    .tint(download.status == .muxing ? .orange : .blue)

                HStack {
                    Text(download.formattedProgress)
                    Spacer()
                    if download.segmentsTotal > 0 {
                        Text("\(download.segmentsDownloaded)/\(download.segmentsTotal) segments")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = download.errorMessage, download.status == .failed {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(download.sourceDomain ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(accessibilityHintText)
    }

    private var accessibilityDescription: String {
        let title = download.pageTitle ?? "Video"
        let status = statusText
        let progress = download.status == .downloading ? ", \(download.formattedProgress)" : ""
        return "\(title), \(status)\(progress)"
    }

    private var statusText: String {
        switch download.status {
        case .pending: return "queued"
        case .downloading: return "downloading"
        case .muxing: return "processing"
        case .paused: return "paused"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }

    private var accessibilityHintText: String {
        switch download.status {
        case .failed: return "Swipe right to retry, swipe left to cancel"
        default: return "Swipe left to cancel"
        }
    }

    private var statusBadge: some View {
        Group {
            switch download.status {
            case .pending:
                Label("Queued", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading:
                Label("Downloading", systemImage: "arrow.down")
                    .font(.caption)
                    .foregroundStyle(.blue)
            case .muxing:
                Label("Processing", systemImage: "gear")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .paused:
                Label("Paused", systemImage: "pause")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .completed:
                Label("Done", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - View Model

@MainActor
class DownloadsViewModel: ObservableObject {
    @Published var downloads: [Download] = []

    private var refreshTimer: Timer?

    init() {
        loadDownloads()
        startRefreshTimer()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func loadDownloads() {
        do {
            downloads = try DownloadRepository.shared.fetchAll()
                .filter { $0.status != .completed }
        } catch {
            print("Failed to load downloads: \(error)")
        }
    }

    func cancelDownload(_ download: Download) {
        DownloadManager.shared.cancelDownload(download)
        loadDownloads()
    }

    func retryDownload(_ download: Download) {
        DownloadManager.shared.retryDownload(download)
        loadDownloads()
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.loadDownloads()
            }
        }
    }
}
