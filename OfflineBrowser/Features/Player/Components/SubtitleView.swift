import SwiftUI

struct SubtitleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.75))
            .cornerRadius(8)
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
    }
}
