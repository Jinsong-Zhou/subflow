import Foundation
import SwiftUI
import Translation

@MainActor
@Observable
final class CaptionViewModel {
    var isRecording = false
    var isLoading = false
    var isModelReady = false
    var statusMessage = ""

    var streamingEnglish = ""
    var streamingChinese = ""
    var streamingWords: [WordTimestamp] = []

    var captionHistory: [CaptionEntry] = []
    var recentCaptions: [CaptionEntry] = []

    let translationService = TranslationService()

    private let maxRecentCaptions = 2
    private var audioCaptureService: AudioCaptureService?
    private var moonshineService: MoonshineTranscriptionService?
    private var accumulatorTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func preloadModel(modelId: String = ASRModel.defaultModel.id) {
        guard !isModelReady, !isLoading else { return }
        let modelName = ASRModel.available.first { $0.id == modelId }?.name ?? "model"
        isLoading = true
        statusMessage = "Loading \(modelName)..."

        Task {
            do {
                AppLogger.log("Loading Moonshine model: \(modelId)")
                let service = try MoonshineTranscriptionService.load(modelId: modelId)
                self.moonshineService = service
                self.isModelReady = true
                self.statusMessage = ""
                AppLogger.log("Model loaded successfully: \(modelId)")
            } catch {
                AppLogger.log("Model load failed: \(error.localizedDescription)")
                self.statusMessage = "Model load failed: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    func switchModel(to modelId: String) {
        guard !isLoading else { return }

        if isRecording {
            stopCapture()
        }

        moonshineService?.close()
        moonshineService = nil
        isModelReady = false
        isLoading = true
        let modelName = ASRModel.available.first { $0.id == modelId }?.name ?? "model"
        statusMessage = "Loading \(modelName)..."

        Task {
            do {
                AppLogger.log("Switching to model: \(modelId)")
                let service = try MoonshineTranscriptionService.load(modelId: modelId)
                self.moonshineService = service
                self.isModelReady = true
                self.statusMessage = ""
                AppLogger.log("Model switched successfully: \(modelId)")
            } catch {
                AppLogger.log("Model switch failed: \(error.localizedDescription)")
                self.statusMessage = "Failed: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    func setTranslationSession(_ session: TranslationSession) {
        translationService.setSession(session)
    }

    func addCaption(english: String, chinese: String) {
        let entry = CaptionEntry(
            timestamp: .now,
            englishText: english,
            chineseText: chinese
        )
        captionHistory.append(entry)
        recentCaptions.append(entry)
        if recentCaptions.count > maxRecentCaptions {
            recentCaptions.removeFirst()
        }
    }

    func clearHistory() {
        captionHistory = []
        recentCaptions = []
        streamingEnglish = ""
        streamingChinese = ""
        streamingWords = []
    }

    // MARK: - Capture Control

    func toggleCapture() {
        AppLogger.log("toggleCapture called, isRecording=\(isRecording), isModelReady=\(isModelReady)")
        if isRecording {
            stopCapture()
        } else {
            Task { await startCapture() }
        }
    }

    func startCapture() async {
        guard !isRecording else { return }

        if !isModelReady {
            preloadModel()
            while isLoading { try? await Task.sleep(for: .milliseconds(100)) }
            guard isModelReady else { return }
        }

        guard moonshineService != nil else {
            statusMessage = "Model not available"
            return
        }

        do {
            let audioService = AudioCaptureService()
            let audioStream = audioService.makeAudioStream()

            self.audioCaptureService = audioService
            self.isRecording = true
            self.statusMessage = ""

            try await audioService.start()
            AppLogger.log("Audio capture started")
            runPipeline(audioStream: audioStream)
        } catch {
            AppLogger.log("Failed to start capture: \(error.localizedDescription)")
            statusMessage = "Error: \(error.localizedDescription)"
            isRecording = false
        }
    }

    func stopCapture() {
        isRecording = false
        accumulatorTask?.cancel()
        accumulatorTask = nil

        try? moonshineService?.stopStream()

        let service = audioCaptureService
        Task { await service?.stop() }
        audioCaptureService = nil

        if !streamingEnglish.isEmpty {
            addCaption(english: streamingEnglish, chinese: streamingChinese)
        }
        streamingEnglish = ""
        streamingChinese = ""
        streamingWords = []
    }

    // MARK: - Moonshine Streaming Pipeline

    private func runPipeline(audioStream: AsyncStream<[Float]>) {
        guard let moonshine = moonshineService else { return }

        moonshine.onTextChanged = { [weak self] text, words in
            guard let self else { return }
            self.streamingEnglish = text
            self.streamingWords = words

            if !words.isEmpty {
                let wordInfo = words.map { "\($0.word)[\(String(format: "%.2f", $0.start))-\(String(format: "%.2f", $0.end))]" }.joined(separator: " ")
                AppLogger.log("Streaming words: \(wordInfo)")
            }
            AppLogger.log("Streaming EN: \(text)")

            Task {
                do {
                    let chinese = try await self.translationService.translate(text)
                    self.streamingChinese = chinese
                    AppLogger.log("Streaming ZH: \(chinese)")
                } catch {
                    AppLogger.log("Translation error: \(error.localizedDescription)")
                }
            }
        }

        moonshine.onLineCompleted = { [weak self] text, words in
            guard let self else { return }
            AppLogger.log("Completed EN: \(text)")

            if !words.isEmpty {
                let wordInfo = words.map { "\($0.word)[\(String(format: "%.2f", $0.confidence))]" }.joined(separator: " ")
                AppLogger.log("Completed words: \(wordInfo)")
            }

            Task {
                let chinese = (try? await self.translationService.translate(text)) ?? ""
                AppLogger.log("Completed ZH: \(chinese)")
                self.addCaption(english: text, chinese: chinese)
                self.streamingEnglish = ""
                self.streamingChinese = ""
                self.streamingWords = []
            }
        }

        do {
            try moonshine.startStream(updateInterval: 0.5)
        } catch {
            AppLogger.log("Failed to start Moonshine stream: \(error.localizedDescription)")
            statusMessage = "Stream error: \(error.localizedDescription)"
            return
        }

        accumulatorTask = Task {
            for await samples in audioStream {
                if Task.isCancelled { break }
                do {
                    try moonshine.addAudio(samples, sampleRate: 16000)
                } catch {
                    AppLogger.log("Moonshine addAudio error: \(error.localizedDescription)")
                }
            }
        }
    }
}
