import SwiftUI

struct MainWindowView: View {
    @Environment(CaptionViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        VStack(spacing: 0) {
            toolbar
            Divider()
            transcriptList
        }
        .frame(minWidth: 500, minHeight: 300)
        .preferredColorScheme(.dark)
    }

    private var toolbar: some View {
        HStack {
            Button(action: { viewModel.toggleCapture() }) {
                HStack(spacing: 6) {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Circle()
                            .fill(viewModel.isRecording ? .green : .gray)
                            .frame(width: 8, height: 8)
                    }
                    Text(toolbarButtonLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.isRecording
                              ? Color.green.opacity(0.15)
                              : Color.gray.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("Cmd+Shift+T")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var toolbarButtonLabel: String {
        if viewModel.isLoading { return "Loading..." }
        if viewModel.isRecording { return "Recording" }
        return "Start"
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.captionHistory) { entry in
                        CaptionRow(entry: entry)
                            .id(entry.id)
                    }

                    // Current streaming line (live)
                    if !viewModel.streamingEnglish.isEmpty {
                        StreamingRow(
                            english: viewModel.streamingEnglish,
                            chinese: viewModel.streamingChinese
                        )
                        .id("streaming")
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.captionHistory.count) {
                if let last = viewModel.captionHistory.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingEnglish) {
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }
}

private struct CaptionRow: View {
    let entry: CaptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(entry.englishText)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))
            Text(entry.chineseText)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.47, green: 0.78, blue: 1.0).opacity(0.8))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct StreamingRow: View {
    let english: String
    let chinese: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.8))
            }
            Text(english)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            if !chinese.isEmpty {
                Text(chinese)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.47, green: 0.78, blue: 1.0))
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.15), value: english)
        .animation(.easeInOut(duration: 0.15), value: chinese)
    }
}
