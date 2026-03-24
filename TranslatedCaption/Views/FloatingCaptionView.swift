import SwiftUI

struct FloatingCaptionView: View {
    @Environment(CaptionViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.recentCaptions) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.englishText)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(entry.chineseText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.47, green: 0.78, blue: 1.0).opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
        )
    }
}
