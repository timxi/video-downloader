import Foundation
import Combine

enum SleepTimerDuration: CaseIterable, Identifiable {
    case minutes15
    case minutes30
    case minutes45
    case hour1
    case hour2
    case endOfVideo

    var id: Self { self }

    var displayName: String {
        switch self {
        case .minutes15: return "15 minutes"
        case .minutes30: return "30 minutes"
        case .minutes45: return "45 minutes"
        case .hour1: return "1 hour"
        case .hour2: return "2 hours"
        case .endOfVideo: return "End of video"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .minutes15: return 15 * 60
        case .minutes30: return 30 * 60
        case .minutes45: return 45 * 60
        case .hour1: return 60 * 60
        case .hour2: return 120 * 60
        case .endOfVideo: return nil
        }
    }
}

@MainActor
final class SleepTimerManager: ObservableObject {
    @Published var isActive = false
    @Published var remainingTime: TimeInterval = 0
    @Published var selectedDuration: SleepTimerDuration?

    var onTimerFired: (() -> Void)?

    private var timer: Timer?
    private var endTime: Date?

    var formattedRemainingTime: String {
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return String(format: "%d:%02d:%02d", hours, mins, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    func start(duration: SleepTimerDuration, videoDuration: TimeInterval? = nil) {
        cancel()

        selectedDuration = duration

        let totalSeconds: TimeInterval
        if duration == .endOfVideo {
            guard let videoDuration = videoDuration, videoDuration > 0 else { return }
            totalSeconds = videoDuration
        } else {
            guard let seconds = duration.seconds else { return }
            totalSeconds = seconds
        }

        remainingTime = totalSeconds
        endTime = Date().addingTimeInterval(totalSeconds)
        isActive = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingTime = 0
        endTime = nil
        selectedDuration = nil
    }

    private func tick() {
        guard let endTime = endTime else {
            cancel()
            return
        }

        remainingTime = max(0, endTime.timeIntervalSinceNow)

        if remainingTime <= 0 {
            cancel()
            onTimerFired?()
        }
    }
}
