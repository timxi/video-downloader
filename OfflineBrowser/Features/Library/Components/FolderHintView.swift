import SwiftUI

struct FolderHintView: View {
    var onDismiss: () -> Void
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text("Organize Your Videos")
                    .font(.headline)

                Text("Create folders to group your downloads by topic, series, or any way you like.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Got it!") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(32)
        }
        .opacity(opacity)
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { opacity = 1 }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}
