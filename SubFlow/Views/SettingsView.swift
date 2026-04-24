import SwiftUI

struct SettingsView: View {
    @Environment(CaptionSettings.self) private var settings
    @Environment(CaptionViewModel.self) private var viewModel

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Display") {
                LabeledContent("Panel Width") {
                    HStack {
                        Slider(value: $settings.panelWidth, in: 400...1000, step: 20)
                        Text("\(Int(settings.panelWidth))pt")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }

                LabeledContent("Font Size") {
                    HStack {
                        Slider(value: $settings.fontSize, in: 10...24, step: 1)
                        Text("\(Int(settings.fontSize))pt")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }

            Section("ASR Model") {
                Picker("Model", selection: $settings.selectedModelId) {
                    ForEach(ASRModel.available) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                            Text("\(model.size) · \(model.speed) · \(model.accuracy)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                }
                .pickerStyle(.radioGroup)

                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isRecording {
                    Text("Stop recording before switching models")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Translation Language") {
                Picker("Chinese variant", selection: $settings.translationTarget) {
                    ForEach(TranslationTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(viewModel.isRecording)

                if viewModel.isRecording {
                    Text("Stop recording before switching languages")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 420)
        .onChange(of: settings.selectedModelId) { _, newModelId in
            guard !viewModel.isRecording, !viewModel.isLoading else { return }
            viewModel.switchModel(to: newModelId)
        }
    }
}
