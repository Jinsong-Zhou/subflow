import SwiftUI

struct FloatingCaptionView: View {
    @Environment(CaptionViewModel.self) private var viewModel
    @Environment(CaptionSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Confirmed captions (faded history)
            ForEach(viewModel.recentCaptions) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.englishText)
                        .font(.system(size: settings.fontSize))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.chineseText)
                        .font(.system(size: settings.fontSize - 1))
                        .foregroundStyle(Color(red: 0.47, green: 0.78, blue: 1.0).opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Current streaming line (bright, actively updating)
            if !viewModel.streamingEnglish.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.streamingEnglish)
                        .font(.system(size: settings.fontSize))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                    if !viewModel.streamingChinese.isEmpty {
                        Text(viewModel.streamingChinese)
                            .font(.system(size: settings.fontSize - 1))
                            .foregroundStyle(Color(red: 0.47, green: 0.78, blue: 1.0).opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentTransition(.numericText())
            }
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.streamingEnglish)
        .animation(.easeInOut(duration: 0.15), value: viewModel.streamingChinese)
        .animation(.easeInOut(duration: 0.2), value: viewModel.recentCaptions.count)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(width: settings.panelWidth, alignment: .leading)
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
