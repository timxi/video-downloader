import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel
    @StateObject private var sleepTimer = SleepTimerManager()
    @State private var showSleepTimerSheet = false
    @State private var showGestureHint = false

    init(video: Video) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(video: video))
    }

    private func setOrientation(_ orientation: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }

        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        } else {
            let orientationValue: UIInterfaceOrientation = orientation == .landscape ? .landscapeRight : .portrait
            UIDevice.current.setValue(orientationValue.rawValue, forKey: "orientation")
        }
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
                VideoPlayerView(player: viewModel.player, viewModel: viewModel)
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

                // Horizontal seek preview
                if viewModel.isHorizontalSeeking {
                    SeekPreviewView(
                        seekOffset: viewModel.seekOffset,
                        previewTime: viewModel.seekPreviewTime
                    )
                }

                // Subtitle overlay
                if let subtitle = viewModel.currentSubtitle {
                    VStack {
                        Spacer()
                        SubtitleView(text: subtitle)
                    }
                }

                // Gesture hint overlay
                if showGestureHint {
                    GestureHintView(onDismiss: {
                        showGestureHint = false
                        PreferenceRepository.shared.hasSeenGestureHint = true
                    })
                }
            }
        }
        .onAppear {
            setOrientation(.landscape)
            if !viewModel.hasError {
                viewModel.play()
            }
            sleepTimer.onTimerFired = { [weak viewModel] in
                viewModel?.pause()
            }
            // Show gesture hint on first play
            if !PreferenceRepository.shared.hasSeenGestureHint {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showGestureHint = true
                }
            }
        }
        .onDisappear {
            setOrientation(.portrait)
            viewModel.savePosition()
            sleepTimer.cancel()
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet(
                sleepTimer: sleepTimer,
                videoDuration: viewModel.player.currentItem?.duration.seconds
            )
        }
        .alert("Resume Playback", isPresented: $viewModel.showResumePrompt) {
            Button("Resume from \(viewModel.formattedResumeTime)") {
                viewModel.resumeFromSavedPosition()
            }
            Button("Start Over", role: .cancel) {
                viewModel.startFromBeginning()
            }
        } message: {
            Text("Continue where you left off?")
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
                    Button {
                        viewModel.subtitlesEnabled.toggle()
                    } label: {
                        Label(
                            viewModel.subtitlesEnabled ? "Hide Subtitles" : "Show Subtitles",
                            systemImage: viewModel.subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble"
                        )
                    }
                    Button {
                        showSleepTimerSheet = true
                    } label: {
                        Label(
                            sleepTimer.isActive ? "Sleep Timer (\(sleepTimer.formattedRemainingTime))" : "Sleep Timer",
                            systemImage: sleepTimer.isActive ? "moon.fill" : "moon"
                        )
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
    let viewModel: PlayerViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        context.coordinator.playerViewController = controller
        context.coordinator.setupPiP(player: player)

        // Set coordinator reference on view model
        DispatchQueue.main.async {
            viewModel.pipCoordinator = context.coordinator
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    class Coordinator: NSObject, AVPlayerViewControllerDelegate, AVPictureInPictureControllerDelegate {
        weak var viewModel: PlayerViewModel?
        weak var playerViewController: AVPlayerViewController?
        var pipController: AVPictureInPictureController?

        init(viewModel: PlayerViewModel) {
            self.viewModel = viewModel
        }

        func setupPiP(player: AVPlayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            let playerLayer = AVPlayerLayer(player: player)
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.delegate = self
        }

        func startPiP() {
            pipController?.startPictureInPicture()
        }

        func stopPiP() {
            pipController?.stopPictureInPicture()
        }

        // MARK: - AVPictureInPictureControllerDelegate

        func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor in
                viewModel?.isPiPActive = true
            }
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor in
                viewModel?.isPiPActive = false
            }
        }

        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
    }
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

    // Horizontal seek state
    @Published var isHorizontalSeeking = false
    @Published var seekOffset: TimeInterval = 0
    @Published var seekPreviewTime: TimeInterval = 0

    @Published var hasError = false
    @Published var errorMessage = ""

    // Resume prompt state
    @Published var showResumePrompt = false
    private var savedPlaybackPosition: Int = 0

    // PiP state
    @Published var isPiPActive = false
    var pipCoordinator: VideoPlayerView.Coordinator?

    // Subtitle state
    @Published var currentSubtitle: String?
    @Published var subtitlesEnabled = true
    private var subtitleCues: [SubtitleCue] = []

    private var timeObserver: Any?
    private var controlsTimer: Timer?
    private var dragStartBrightness: CGFloat = 0
    private var dragStartVolume: Float = 0
    private var dragStartTime: TimeInterval = 0

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

        // Check for saved position
        if PreferenceRepository.shared.rememberPlaybackPosition && video.playbackPosition > 0 {
            savedPlaybackPosition = video.playbackPosition
            // Show prompt for positions > 10 seconds
            if video.playbackPosition > 10 {
                showResumePrompt = true
            } else {
                // Auto-seek for small positions
                let time = CMTime(seconds: Double(video.playbackPosition), preferredTimescale: 1)
                player.seek(to: time)
            }
        }

        // Set default playback speed
        playbackSpeed = PreferenceRepository.shared.defaultPlaybackSpeed
        player.rate = Float(playbackSpeed)

        setupTimeObserver()
        startControlsTimer()
        loadSubtitles()
    }

    private func loadSubtitles() {
        guard let subtitleURL = video.subtitleFileURL else { return }
        let parser = WebVTTParser()
        do {
            subtitleCues = try parser.parse(fileURL: subtitleURL)
        } catch {
            // Silently fail - subtitles are optional
        }
    }

    private func updateSubtitle(for time: TimeInterval) {
        guard subtitlesEnabled, !subtitleCues.isEmpty else {
            currentSubtitle = nil
            return
        }

        // Find cue that matches current time
        let matchingCue = subtitleCues.first { cue in
            time >= cue.startTime && time <= cue.endTime
        }

        currentSubtitle = matchingCue?.text
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
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if isPiPActive {
            pipCoordinator?.stopPiP()
        } else {
            pipCoordinator?.startPiP()
        }
    }

    // MARK: - Resume Playback

    var formattedResumeTime: String {
        formatTime(Double(savedPlaybackPosition))
    }

    func resumeFromSavedPosition() {
        let time = CMTime(seconds: Double(savedPlaybackPosition), preferredTimescale: 1)
        player.seek(to: time)
        showResumePrompt = false
    }

    func startFromBeginning() {
        player.seek(to: .zero)
        showResumePrompt = false
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

        // Determine drag direction with threshold
        let isHorizontal = abs(translation.width) > abs(translation.height) * 1.5

        // Horizontal drag - seek
        if isHorizontal && abs(translation.width) > 20 {
            if !isHorizontalSeeking {
                // Start horizontal seeking
                isHorizontalSeeking = true
                dragStartTime = player.currentTime().seconds
            }

            // Calculate seek offset: 100px = 1 second
            let offset = translation.width / 100.0
            seekOffset = offset

            // Calculate preview time
            guard let duration = player.currentItem?.duration.seconds, duration > 0 else { return }
            let previewTime = max(0, min(duration, dragStartTime + offset))
            seekPreviewTime = previewTime
            return
        }

        // If already in horizontal seeking mode, continue it
        if isHorizontalSeeking {
            let offset = translation.width / 100.0
            seekOffset = offset
            guard let duration = player.currentItem?.duration.seconds, duration > 0 else { return }
            let previewTime = max(0, min(duration, dragStartTime + offset))
            seekPreviewTime = previewTime
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
        if isHorizontalSeeking {
            // Apply the seek
            let time = CMTime(seconds: seekPreviewTime, preferredTimescale: 1)
            player.seek(to: time)

            // Reset horizontal seek state
            isHorizontalSeeking = false
            seekOffset = 0
            seekPreviewTime = 0
            return
        }

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
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isSeeking else { return }
            let currentTime = time.seconds
            if let duration = self.player.currentItem?.duration.seconds, duration > 0 {
                self.currentProgress = currentTime / duration
            }
            self.updateSubtitle(for: currentTime)
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
