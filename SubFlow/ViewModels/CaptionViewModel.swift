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

    private let maxRecentCaptions = 3
    private var audioCaptureService: AudioCaptureService?
    private var moonshineService: MoonshineTranscriptionService?
    private var accumulatorTask: Task<Void, Never>?
    private var completionDisplayTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

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
        while recentCaptions.count > maxRecentCaptions {
            recentCaptions.removeFirst()
        }
        scheduleCleanup()
    }

    func clearHistory() {
        captionHistory = []
        recentCaptions = []
        streamingEnglish = ""
        streamingChinese = ""
        streamingWords = []
        completionDisplayTask?.cancel()
        completionDisplayTask = nil
        cleanupTask?.cancel()
        cleanupTask = nil
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
        completionDisplayTask?.cancel()
        completionDisplayTask = nil

        try? moonshineService?.stopStream()

        let service = audioCaptureService
        Task { await service?.stop() }
        audioCaptureService = nil

        let remainingEnglish = streamingEnglish
        let remainingChinese = streamingChinese
        if !remainingEnglish.isEmpty {
            if !remainingChinese.isEmpty {
                addCaption(english: remainingEnglish, chinese: remainingChinese)
            } else {
                Task {
                    let chinese = (try? await translationService.translate(remainingEnglish)) ?? ""
                    addCaption(english: remainingEnglish, chinese: chinese)
                }
            }
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

            // Flush completed caption still in display phase to history
            if self.completionDisplayTask != nil {
                self.completionDisplayTask?.cancel()
                self.completionDisplayTask = nil
                if !self.streamingChinese.isEmpty {
                    self.addCaption(
                        english: self.streamingEnglish,
                        chinese: self.streamingChinese
                    )
                    self.streamingChinese = ""
                }
            }

            self.streamingEnglish = text
            self.streamingWords = words
            AppLogger.log("Streaming EN: \(text)")
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

                // Show completed bilingual caption at full brightness
                self.streamingEnglish = text
                self.streamingChinese = chinese
                self.streamingWords = []

                // After reading time, move to faded history
                self.completionDisplayTask = Task {
                    let displayTime = Self.estimateReadingTime(
                        english: text, chinese: chinese
                    )
                    try? await Task.sleep(for: .seconds(displayTime))
                    guard !Task.isCancelled else { return }
                    self.addCaption(english: text, chinese: chinese)
                    self.streamingEnglish = ""
                    self.streamingChinese = ""
                }
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

    // MARK: - Display Timing

    private func scheduleCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task {
            while !recentCaptions.isEmpty {
                guard let oldest = recentCaptions.first else { break }
                let readingTime = Self.estimateReadingTime(
                    english: oldest.englishText,
                    chinese: oldest.chineseText
                )
                let age = Date.now.timeIntervalSince(oldest.timestamp)
                let remaining = readingTime - age

                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                    if Task.isCancelled { break }
                }

                if !recentCaptions.isEmpty {
                    recentCaptions.removeFirst()
                }
            }
        }
    }

    /// Estimate comfortable reading time based on subtitle length.
    /// ~15 chars/sec for bilingual subtitles, clamped to 3–8 seconds.
    private static func estimateReadingTime(english: String, chinese: String) -> TimeInterval {
        let totalChars = Double(english.count + chinese.count)
        return min(max(totalChars / 15.0, 3.0), 8.0)
    }
}
