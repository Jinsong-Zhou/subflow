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
    var currentEnglish = ""
    var currentChinese = ""
    var captionHistory: [CaptionEntry] = []
    var recentCaptions: [CaptionEntry] = []

    let translationService = TranslationService()

    private let maxRecentCaptions = 3
    private var audioCaptureService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var pipelineTask: Task<Void, Never>?

    /// Call once on app launch to pre-load WhisperKit model in background
    func preloadModel() {
        guard !isModelReady, !isLoading else { return }
        isLoading = true
        statusMessage = "Loading speech model..."

        Task {
            do {
                AppLogger.log(" Loading WhisperKit model...")
                let transcription = try await TranscriptionService.load()
                self.transcriptionService = transcription
                self.isModelReady = true
                self.statusMessage = ""
                AppLogger.log(" Model loaded successfully")
            } catch {
                AppLogger.log(" Model load failed: \(error.localizedDescription)")
                self.statusMessage = "Model load failed: \(error.localizedDescription)"
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
        currentEnglish = ""
        currentChinese = ""
    }

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

        // Wait for model if still loading
        if !isModelReady {
            preloadModel()
            // Wait until model is ready
            while isLoading { try? await Task.sleep(for: .milliseconds(100)) }
            guard isModelReady else { return }
        }

        guard let transcription = transcriptionService else {
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
            AppLogger.log(" Audio capture started, running pipeline")
            runPipeline(audioStream: audioStream, transcription: transcription, translation: translationService)
        } catch {
            AppLogger.log(" Failed to start capture: \(error.localizedDescription)")
            statusMessage = "Error: \(error.localizedDescription)"
            isRecording = false
        }
    }

    func stopCapture() {
        isRecording = false
        pipelineTask?.cancel()
        pipelineTask = nil
        let service = audioCaptureService
        Task { await service?.stop() }
        audioCaptureService = nil
        // Keep transcriptionService alive — don't nil it
    }

    /// Check if audio chunk is mostly silence (RMS below threshold)
    private func isSilent(_ samples: [Float], threshold: Float = 0.01) -> Bool {
        guard !samples.isEmpty else { return true }
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        return rms < threshold
    }

    /// Filter out WhisperKit hallucinations on silence
    private func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let hallucinations = ["you", "thank you", "thanks for watching", "bye", "...", ""]
        return hallucinations.contains(lower) || lower.count < 3
    }

    private func runPipeline(
        audioStream: AsyncStream<[Float]>,
        transcription: TranscriptionService,
        translation: TranslationService
    ) {
        pipelineTask = Task {
            var audioBuffer: [Float] = []
            let samplesPerChunk = 16000 * 3 // 3 seconds for better sentence coherence

            for await samples in audioStream {
                if Task.isCancelled { break }

                audioBuffer.append(contentsOf: samples)

                guard audioBuffer.count >= samplesPerChunk else { continue }

                let chunk = audioBuffer
                audioBuffer = []

                // Skip silent chunks to avoid hallucinations
                if isSilent(chunk) { continue }

                do {
                    let english = try await transcription.transcribe(audioBuffer: chunk)

                    // Filter hallucinated outputs
                    guard !isHallucination(english) else { continue }

                    AppLogger.log(" Transcribed: \(english)")
                    self.currentEnglish = english

                    let chinese = try await translation.translate(english)
                    AppLogger.log(" Translated: \(chinese)")
                    self.currentChinese = chinese
                    self.addCaption(english: english, chinese: chinese)
                } catch {
                    AppLogger.log(" Pipeline error: \(error.localizedDescription)")
                }
            }
        }
    }
}
