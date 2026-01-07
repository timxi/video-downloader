import SwiftUI

struct GestureHintView: View {
    var onDismiss: () -> Void
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Gesture Controls")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 16) {
                    gestureRow(icon: "hand.draw.fill", text: "Swipe left/right to seek")
                    gestureRow(icon: "sun.max.fill", text: "Swipe up/down on left for brightness")
                    gestureRow(icon: "speaker.wave.2.fill", text: "Swipe up/down on right for volume")
                    gestureRow(icon: "hand.tap.fill", text: "Double-tap to play/pause")
                }

                Text("Tap anywhere to dismiss")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gesture controls. Swipe left or right to seek. Swipe up or down on left side for brightness. Swipe up or down on right side for volume. Double tap to play or pause.")
            .accessibilityAddTraits(.isModal)
            .accessibilityHint("Tap to dismiss")
        }
        .opacity(opacity)
        .onTapGesture { dismiss() }
        .onAppear {
            if reduceMotion {
                opacity = 1
            } else {
                withAnimation(.easeIn(duration: 0.3)) { opacity = 1 }
            }
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if opacity > 0 { dismiss() }
            }
        }
    }

    private func gestureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            Text(text)
                .foregroundColor(.white)
        }
    }

    private func dismiss() {
        if reduceMotion {
            opacity = 0
            onDismiss()
        } else {
            withAnimation(.easeOut(duration: 0.2)) { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
        }
    }
}
