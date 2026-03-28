import SwiftUI

struct FloatingCaptionView: View {
    @Environment(CaptionViewModel.self) private var viewModel
    @Environment(CaptionSettings.self) private var settings

    private static let chineseColor = Color(red: 0.47, green: 0.78, blue: 1.0)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    // All completed captions (scrollable history)
                    ForEach(viewModel.captionHistory) { entry in
                        captionPair(
                            english: entry.englishText,
                            chinese: entry.chineseText,
                            englishOpacity: 0.55,
                            chineseOpacity: 0.5
                        )
                        .id(entry.id)
                    }

                    // Current streaming / completed line
                    if !viewModel.streamingEnglish.isEmpty {
                        captionPair(
                            english: viewModel.streamingEnglish,
                            chinese: viewModel.streamingChinese,
                            englishOpacity: viewModel.streamingChinese.isEmpty ? 0.7 : 0.95,
                            chineseOpacity: 0.9
                        )
                        .id("streaming")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            // Smooth scroll to bottom when new completed caption arrives
            .onChange(of: viewModel.captionHistory.count) {
                withAnimation(.easeOut(duration: 0.5)) {
                    if !viewModel.streamingEnglish.isEmpty {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    } else if let last = viewModel.captionHistory.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            // Keep streaming visible (no animation to avoid lag)
            .onChange(of: viewModel.streamingEnglish) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
        .frame(width: settings.panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func captionPair(
        english: String,
        chinese: String,
        englishOpacity: Double,
        chineseOpacity: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(english)
                .font(.system(size: settings.fontSize))
                .foregroundStyle(.white.opacity(englishOpacity))
                .fixedSize(horizontal: false, vertical: true)
            if !chinese.isEmpty {
                Text(chinese)
                    .font(.system(size: settings.fontSize - 1))
                    .foregroundStyle(Self.chineseColor.opacity(chineseOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
