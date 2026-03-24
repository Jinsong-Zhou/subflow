import SwiftUI

struct MenuBarView: View {
    @Environment(CaptionViewModel.self) private var viewModel
    var onToggleCapture: () -> Void
    var onOpenTranscript: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(viewModel.isRecording ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("Cmd+Shift+T")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button(action: onToggleCapture) {
                Text(buttonLabel)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(viewModel.isLoading && !viewModel.isModelReady)

            Divider()

            Button("Open Transcript", action: onOpenTranscript)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 220)
    }

    private var statusLabel: String {
        if viewModel.isLoading { return viewModel.statusMessage.isEmpty ? "Loading model..." : viewModel.statusMessage }
        if viewModel.isRecording { return "Recording" }
        if viewModel.isModelReady { return "Ready" }
        return "Idle"
    }

    private var buttonLabel: String {
        if viewModel.isRecording { return "Stop" }
        if viewModel.isLoading { return "Loading..." }
        return "Start"
    }
}
