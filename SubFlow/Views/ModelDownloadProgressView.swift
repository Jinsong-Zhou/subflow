import SwiftUI

/// Modal shown while the Moonshine model zip is downloading.
/// Dismisses automatically when `CaptionViewModel.downloadProgress` returns to `nil`.
struct ModelDownloadProgressView: View {
    @Environment(CaptionViewModel.self) private var viewModel
    let modelName: String

    var body: some View {
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
        .padding(24)
        .frame(width: 380)
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
