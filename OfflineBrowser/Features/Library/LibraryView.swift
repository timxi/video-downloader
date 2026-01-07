import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var searchText = ""
    @State private var showingCreateFolder = false
    @State private var selectedVideo: Video?
    @State private var showFolderHint = false

    var body: some View {
        ZStack {
        NavigationView {
            Group {
                if viewModel.videos.isEmpty && viewModel.folders.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search videos")
            .onChange(of: searchText) { newValue in
                viewModel.search(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingCreateFolder = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCreateFolder) {
                CreateFolderSheet { name in
                    viewModel.createFolder(name: name)
                }
            }
            .fullScreenCover(item: $selectedVideo) { video in
                PlayerView(video: video)
            }
            .onAppear {
                viewModel.loadData()
                checkFolderHint()
            }
        }

        // Folder hint overlay
        if showFolderHint {
            FolderHintView(onDismiss: {
                showFolderHint = false
                PreferenceRepository.shared.hasSeenFolderHint = true
            })
        }
        }
    }

    private func checkFolderHint() {
        let downloadCount = PreferenceRepository.shared.getInt(.totalDownloadsCount)
        if downloadCount >= 5 && !PreferenceRepository.shared.hasSeenFolderHint {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showFolderHint = true
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        List {
            // Folders section
            if !viewModel.folders.isEmpty {
                Section("Folders") {
                    ForEach(viewModel.folders) { folder in
                        FolderRow(folder: folder, videoCount: viewModel.videoCount(for: folder))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectFolder(folder)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteFolder(folder)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    viewModel.renameFolder(folder)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    viewModel.deleteFolder(folder)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            // Videos section
            Section(viewModel.selectedFolder?.name ?? "All Videos") {
                ForEach(viewModel.filteredVideos) { video in
                    VideoRow(video: video)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedVideo = video
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteVideo(video)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                viewModel.showMoveSheet(for: video)
                            } label: {
                                Label("Move to Folder", systemImage: "folder")
                            }

                            Button(role: .destructive) {
                                viewModel.deleteVideo(video)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Videos Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Downloaded videos will appear here.\nBrowse websites and tap the download button when you find a video.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: Folder
    let videoCount: Int

    var body: some View {
        HStack {
            Image(systemName: folder.isAutoGenerated ? "globe" : "folder.fill")
                .foregroundStyle(folder.isAutoGenerated ? .blue : .yellow)
                .font(.title2)

            VStack(alignment: .leading) {
                Text(folder.name)
                    .font(.body)
                Text("\(videoCount) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Video Row

struct VideoRow: View {
    let video: Video

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: video.thumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(video.formattedDuration)
                    Text("•")
                    Text(video.quality)
                    Text("•")
                    Text(video.formattedFileSize)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if video.playbackPosition > 0 {
                    ProgressView(value: Double(video.playbackPosition), total: Double(video.duration))
                        .tint(.blue)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View Model

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var folders: [Folder] = []
    @Published var selectedFolder: Folder?
    @Published var filteredVideos: [Video] = []

    private var allVideos: [Video] = []

    init() {
        loadData()
    }

    func loadData() {
        do {
            folders = try FolderRepository.shared.fetchAll()
            allVideos = try VideoRepository.shared.fetchAll()
            videos = allVideos
            filteredVideos = allVideos
            print("[LibraryViewModel] Loaded \(folders.count) folders and \(allVideos.count) videos")
        } catch {
            print("[LibraryViewModel] Failed to load library: \(error)")
        }
    }

    func search(query: String) {
        if query.isEmpty {
            filteredVideos = selectedFolder == nil ? allVideos : allVideos.filter { $0.folderID == selectedFolder?.id }
        } else {
            filteredVideos = allVideos.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
    }

    func selectFolder(_ folder: Folder?) {
        selectedFolder = folder
        if let folder = folder {
            filteredVideos = allVideos.filter { $0.folderID == folder.id }
        } else {
            filteredVideos = allVideos
        }
    }

    func videoCount(for folder: Folder) -> Int {
        allVideos.filter { $0.folderID == folder.id }.count
    }

    func createFolder(name: String) {
        let folder = Folder(name: name)
        do {
            try FolderRepository.shared.save(folder)
            loadData()
        } catch {
            print("Failed to create folder: \(error)")
        }
    }

    func renameFolder(_ folder: Folder) {
        // Implement rename sheet
    }

    func deleteFolder(_ folder: Folder) {
        do {
            try FolderRepository.shared.delete(folder)
            loadData()
        } catch {
            print("Failed to delete folder: \(error)")
        }
    }

    func deleteVideo(_ video: Video) {
        do {
            try VideoRepository.shared.delete(video)
            loadData()
        } catch {
            print("Failed to delete video: \(error)")
        }
    }

    func showMoveSheet(for video: Video) {
        // Implement move sheet
    }
}

// MARK: - Create Folder Sheet

struct CreateFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var folderName = ""
    let onSave: (String) -> Void

    var body: some View {
        NavigationView {
            Form {
                TextField("Folder Name", text: $folderName)
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(folderName)
                        dismiss()
                    }
                    .disabled(folderName.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
