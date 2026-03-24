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

    // Streaming state — updates every ~0.7s as audio accumulates
    var streamingEnglish = ""
    var streamingChinese = ""

    // Confirmed captions (finalized after silence or max buffer)
    var captionHistory: [CaptionEntry] = []
    var recentCaptions: [CaptionEntry] = []

    let translationService = TranslationService()

    private let maxRecentCaptions = 2
    private var audioCaptureService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var pipelineTask: Task<Void, Never>?
    private var accumulatorTask: Task<Void, Never>?

    // Shared audio buffer (safe: both tasks run on MainActor)
    private var audioBuffer: [Float] = []
    private var consecutiveSilentSamples = 0

    // MARK: - Lifecycle

    func preloadModel() {
        guard !isModelReady, !isLoading else { return }
        isLoading = true
        statusMessage = "Loading speech model..."

        Task {
            do {
                AppLogger.log("Loading WhisperKit model...")
                let transcription = try await TranscriptionService.load()
                self.transcriptionService = transcription
                self.isModelReady = true
                self.statusMessage = ""
                AppLogger.log("Model loaded successfully")
            } catch {
                AppLogger.log("Model load failed: \(error.localizedDescription)")
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
        streamingEnglish = ""
        streamingChinese = ""
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

        guard transcriptionService != nil else {
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
            AppLogger.log("Audio capture started, running streaming pipeline")
            runStreamingPipeline(audioStream: audioStream)
        } catch {
            AppLogger.log("Failed to start capture: \(error.localizedDescription)")
            statusMessage = "Error: \(error.localizedDescription)"
            isRecording = false
        }
    }

    func stopCapture() {
        isRecording = false
        pipelineTask?.cancel()
        accumulatorTask?.cancel()
        pipelineTask = nil
        accumulatorTask = nil

        let service = audioCaptureService
        Task { await service?.stop() }
        audioCaptureService = nil

        // Finalize any remaining streaming text
        if !streamingEnglish.isEmpty {
            addCaption(english: streamingEnglish, chinese: streamingChinese)
        }
        streamingEnglish = ""
        streamingChinese = ""
        audioBuffer = []
        consecutiveSilentSamples = 0
    }

    // MARK: - Audio Analysis

    private func isSilent(_ samples: [Float], threshold: Float = 0.01) -> Bool {
        guard !samples.isEmpty else { return true }
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        return rms < threshold
    }

    private func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let hallucinations = [
            "you", "thank you", "thanks for watching", "bye", "...", "",
            "[blank_audio]", "(blank audio)", "[silence]",
        ]
        return hallucinations.contains(lower)
            || lower.count < 3
            || lower.hasPrefix("[") && lower.hasSuffix("]")
            || lower.hasPrefix("(") && lower.hasSuffix(")")
    }

    // MARK: - Streaming Pipeline

    private func runStreamingPipeline(audioStream: AsyncStream<[Float]>) {
        let sampleRate = 16000
        let silenceLimit = Int(1.5 * Double(sampleRate))   // 1.5s silence → finalize
        let maxBufferSize = sampleRate * 6                  // 6s max before forced finalize
        let overlapSamples = sampleRate / 2                 // 0.5s overlap on finalize

        // Task 1: Accumulate audio into shared buffer
        accumulatorTask = Task {
            for await samples in audioStream {
                if Task.isCancelled { break }
                self.audioBuffer.append(contentsOf: samples)

                if self.isSilent(samples) {
                    self.consecutiveSilentSamples += samples.count
                } else {
                    self.consecutiveSilentSamples = 0
                }
            }
        }

        // Task 2: Adaptive transcription — polls quickly, fires when enough new audio
        pipelineTask = Task {
            guard let transcription = self.transcriptionService else { return }
            var lastTranscription = ""
            var lastTranscribeBufferSize = 0
            let minNewSamples = sampleRate / 4  // need at least ~0.25s of new audio

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { break }

                // --- Finalize check ---
                let shouldFinalize = !self.streamingEnglish.isEmpty && (
                    self.consecutiveSilentSamples >= silenceLimit ||
                    self.audioBuffer.count >= maxBufferSize
                )

                if shouldFinalize {
                    await self.finalizeCurrentCaption()
                    let overlap = min(self.audioBuffer.count, overlapSamples)
                    self.audioBuffer = Array(self.audioBuffer.suffix(overlap))
                    self.consecutiveSilentSamples = 0
                    lastTranscription = ""
                    lastTranscribeBufferSize = self.audioBuffer.count
                    continue
                }

                // --- Skip if not enough new audio since last transcription ---
                let newSamples = self.audioBuffer.count - lastTranscribeBufferSize
                guard newSamples >= minNewSamples else { continue }

                // --- Skip if recent audio is silent and nothing streaming ---
                let recentChunk = Array(self.audioBuffer.suffix(sampleRate / 3))
                if self.isSilent(recentChunk) && self.streamingEnglish.isEmpty { continue }

                // --- Transcribe full buffer ---
                let snapshot = self.audioBuffer

                lastTranscribeBufferSize = self.audioBuffer.count

                do {
                    let english = try await transcription.transcribe(audioBuffer: snapshot)

                    guard !self.isHallucination(english) else { continue }
                    guard english != lastTranscription else { continue }

                    lastTranscription = english
                    self.streamingEnglish = english
                    AppLogger.log("Streaming EN: \(english)")

                    // Translate sequentially (Apple Translation is ~100ms, fast enough)
                    do {
                        let chinese = try await self.translationService.translate(english)
                        self.streamingChinese = chinese
                        AppLogger.log("Streaming ZH: \(chinese)")
                    } catch {
                        AppLogger.log("Translation error: \(error.localizedDescription)")
                    }
                } catch {
                    AppLogger.log("Transcription error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func finalizeCurrentCaption() async {
        let english = streamingEnglish
        guard !english.isEmpty else { return }

        var chinese = streamingChinese
        if chinese.isEmpty {
            chinese = (try? await translationService.translate(english)) ?? ""
        }

        AppLogger.log("Finalized: \(english) -> \(chinese)")
        addCaption(english: english, chinese: chinese)

        streamingEnglish = ""
        streamingChinese = ""
    }
}
