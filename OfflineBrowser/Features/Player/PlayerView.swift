import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel

    init(video: Video) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(video: video))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.hasError {
                // Error state
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundStyle(.yellow)

                    Text("Unable to Play Video")
                        .font(.title2)
                        .foregroundStyle(.white)

                    Text(viewModel.errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            } else {
                VideoPlayerView(player: viewModel.player)
                    .ignoresSafeArea()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            viewModel.handleDrag(translation: value.translation, location: value.location)
                        }
                        .onEnded { _ in
                            viewModel.endDrag()
                        }
                )
                .onTapGesture(count: 2) {
                    viewModel.handleDoubleTap()
                }
                .onTapGesture(count: 1) {
                    viewModel.toggleControls()
                }

                // Controls overlay
                if viewModel.showControls {
                    controlsOverlay
                }

                // Seek indicator
                if let seekDirection = viewModel.seekDirection {
                    seekIndicator(direction: seekDirection)
                }

                // Volume/Brightness indicator
                if let adjustmentType = viewModel.adjustmentType {
                    adjustmentIndicator(type: adjustmentType, value: viewModel.adjustmentValue)
                }
            }
        }
        .onAppear {
            if !viewModel.hasError {
                viewModel.play()
            }
        }
        .onDisappear {
            viewModel.savePosition()
        }
        .statusBarHidden(true)
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding()
                }

                Spacer()

                Text(viewModel.video.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Menu {
                    speedMenu
                    Button {
                        viewModel.togglePiP()
                    } label: {
                        Label("Picture in Picture", systemImage: "pip")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding()
                }
            }
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            // Center controls
            HStack(spacing: 60) {
                Button {
                    viewModel.skip(seconds: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }

                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                }

                Button {
                    viewModel.skip(seconds: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            // Bottom bar
            VStack(spacing: 8) {
                // Progress bar
                Slider(value: $viewModel.currentProgress, in: 0...1) { editing in
                    viewModel.isSeeking = editing
                    if !editing {
                        viewModel.seekToProgress()
                    }
                }
                .tint(.white)

                // Time labels
                HStack {
                    Text(viewModel.currentTimeString)
                    Spacer()
                    Text(viewModel.durationString)
                }
                .font(.caption)
                .foregroundStyle(.white)
            }
            .padding()
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var speedMenu: some View {
        Menu("Playback Speed") {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                Button {
                    viewModel.setSpeed(speed)
                } label: {
                    HStack {
                        Text("\(speed, specifier: "%.2g")x")
                        if viewModel.playbackSpeed == speed {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Indicators

    private func seekIndicator(direction: SeekDirection) -> some View {
        HStack {
            if direction == .backward {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            Spacer()
            if direction == .forward {
                Image(systemName: "goforward.10")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 60)
    }

    private func adjustmentIndicator(type: AdjustmentType, value: Double) -> some View {
        VStack {
            Image(systemName: type == .brightness ? "sun.max.fill" : "speaker.wave.2.fill")
                .font(.title)
            ProgressView(value: value)
                .frame(width: 100)
                .tint(.white)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Video Player View (UIKit wrapper)

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

// MARK: - Enums

enum SeekDirection {
    case forward, backward
}

enum AdjustmentType {
    case brightness, volume
}

// MARK: - View Model

@MainActor
class PlayerViewModel: ObservableObject {
    let video: Video
    let player: AVPlayer

    @Published var isPlaying = false
    @Published var showControls = true
    @Published var currentProgress: Double = 0
    @Published var playbackSpeed: Double = 1.0
    @Published var isSeeking = false

    @Published var seekDirection: SeekDirection?
    @Published var adjustmentType: AdjustmentType?
    @Published var adjustmentValue: Double = 0

    @Published var hasError = false
    @Published var errorMessage = ""

    private var timeObserver: Any?
    private var controlsTimer: Timer?
    private var dragStartBrightness: CGFloat = 0
    private var dragStartVolume: Float = 0

    var currentTimeString: String {
        formatTime(player.currentTime().seconds)
    }

    var durationString: String {
        formatTime(player.currentItem?.duration.seconds ?? 0)
    }

    init(video: Video) {
        self.video = video

        guard let url = video.videoFileURL else {
            player = AVPlayer()
            hasError = true
            errorMessage = "Video file path is invalid"
            return
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            player = AVPlayer()
            hasError = true
            errorMessage = "Video file not found at:\n\(url.lastPathComponent)"
            return
        }

        player = AVPlayer(url: url)

        // Resume from saved position
        if PreferenceRepository.shared.rememberPlaybackPosition && video.playbackPosition > 0 {
            let time = CMTime(seconds: Double(video.playbackPosition), preferredTimescale: 1)
            player.seek(to: time)
        }

        // Set default playback speed
        playbackSpeed = PreferenceRepository.shared.defaultPlaybackSpeed
        player.rate = Float(playbackSpeed)

        setupTimeObserver()
        startControlsTimer()
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        controlsTimer?.invalidate()
    }

    // MARK: - Playback Controls

    func play() {
        player.play()
        player.rate = Float(playbackSpeed)
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func skip(seconds: Double) {
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1))
        player.seek(to: newTime)
    }

    func seekToProgress() {
        guard let duration = player.currentItem?.duration.seconds, duration > 0 else { return }
        let time = CMTime(seconds: currentProgress * duration, preferredTimescale: 1)
        player.seek(to: time)
    }

    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = Float(speed)
        }
    }

    func togglePiP() {
        // PiP implementation would go here
    }

    // MARK: - Gestures

    func toggleControls() {
        showControls.toggle()
        if showControls {
            startControlsTimer()
        }
    }

    func handleDoubleTap() {
        // Double tap to toggle play/pause
        togglePlayPause()
    }

    func handleDrag(translation: CGSize, location: CGPoint) {
        let screenWidth = UIScreen.main.bounds.width

        // Horizontal drag - seek
        if abs(translation.width) > abs(translation.height) {
            // Implement horizontal seek if desired
            return
        }

        // Vertical drag
        if location.x < screenWidth / 2 {
            // Left side - brightness
            adjustmentType = .brightness
            let change = -translation.height / 200
            let newBrightness = max(0, min(1, UIScreen.main.brightness + change))
            UIScreen.main.brightness = newBrightness
            adjustmentValue = newBrightness
        } else {
            // Right side - volume
            adjustmentType = .volume
            // Volume control would need MPVolumeView
        }
    }

    func endDrag() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.adjustmentType = nil
        }
    }

    // MARK: - Position Saving

    func savePosition() {
        let position = Int(player.currentTime().seconds)
        try? VideoRepository.shared.updatePlaybackPosition(videoID: video.id, position: position)
    }

    // MARK: - Private Methods

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            if let duration = self.player.currentItem?.duration.seconds, duration > 0 {
                self.currentProgress = time.seconds / duration
            }
        }
    }

    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.isPlaying == true {
                    self.showControls = false
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
