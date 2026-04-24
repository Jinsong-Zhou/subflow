import SwiftUI

/// Shown while the Moonshine model zip is downloading, and kept on screen
/// afterwards if the download or load fails, so the error never disappears
/// behind an auto-dismissing window.
///
/// Dismiss behaviour:
/// - Progress only (`downloadError == nil`) → window is managed by the app
///   delegate and auto-closes when `downloadProgress` returns to `nil`.
/// - Error present (`downloadError != nil`) → user must click **Dismiss**,
///   which clears the error and closes the window. Clicking **Retry** also
///   clears the error and starts another `preloadModel` attempt.
struct ModelDownloadProgressView: View {
    @Environment(CaptionViewModel.self) private var viewModel
    @Environment(CaptionSettings.self) private var settings
    let modelName: String

    var body: some View {
        VStack(spacing: 16) {
            if let error = viewModel.downloadError {
                errorContent(error: error)
            } else {
                progressContent
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private var progressContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 4) {
                Text("Downloading \(modelName)")
                    .font(.headline)
                Text("First launch only. The model will be cached for next time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView(value: viewModel.downloadProgress ?? 0, total: 1.0)
                .progressViewStyle(.linear)

            HStack {
                Text(percentageLabel)
                    .monospacedDigit()
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func errorContent(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            VStack(spacing: 4) {
                Text("Model download failed")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Dismiss", action: viewModel.clearDownloadError)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Retry") {
                    viewModel.clearDownloadError()
                    viewModel.preloadModel(modelId: settings.selectedModelId)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var percentageLabel: String {
        guard let p = viewModel.downloadProgress else { return "--%" }
        return "\(Int(p * 100))%"
    }

    private var statusLabel: String {
        if let p = viewModel.downloadProgress, p >= 1.0 {
            return "Extracting…"
        }
        return viewModel.statusMessage
    }
}
