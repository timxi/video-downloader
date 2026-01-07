import SwiftUI

struct SleepTimerSheet: View {
    @ObservedObject var sleepTimer: SleepTimerManager
    var videoDuration: TimeInterval?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if sleepTimer.isActive {
                    activeTimerSection
                } else {
                    durationOptionsSection
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var activeTimerSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    Text("Time remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(sleepTimer.formattedRemainingTime)
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                }

                Spacer()

                Button(role: .destructive) {
                    sleepTimer.cancel()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 8)
        } header: {
            if let duration = sleepTimer.selectedDuration {
                Text(duration.displayName)
            }
        }
    }

    private var durationOptionsSection: some View {
        Section {
            ForEach(SleepTimerDuration.allCases) { duration in
                Button {
                    sleepTimer.start(duration: duration, videoDuration: videoDuration)
                    dismiss()
                } label: {
                    HStack {
                        Text(duration.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(duration == .endOfVideo && (videoDuration == nil || videoDuration == 0))
            }
        } footer: {
            Text("Playback will pause when the timer ends.")
        }
    }
}
