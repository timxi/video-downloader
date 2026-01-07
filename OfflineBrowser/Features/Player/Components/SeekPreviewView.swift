import SwiftUI

struct SeekPreviewView: View {
    let seekOffset: TimeInterval
    let previewTime: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            // Offset indicator (+5s or -3s)
            Text(formatOffset(seekOffset))
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundColor(seekOffset >= 0 ? .green : .red)

            // Preview time (1:23)
            Text(formatTime(previewTime))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatOffset(_ offset: TimeInterval) -> String {
        let sign = offset >= 0 ? "+" : ""
        let absOffset = abs(offset)
        if absOffset >= 60 {
            let minutes = Int(absOffset) / 60
            let seconds = Int(absOffset) % 60
            return "\(sign)\(minutes):\(String(format: "%02d", seconds))"
        }
        return "\(sign)\(Int(offset))s"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
