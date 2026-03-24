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

    // Streaming state — updates every ~0.3s as audio accumulates
    var streamingEnglish = ""
    var streamingChinese = ""

    // Confirmed captions (finalized after silence or sentence boundary)
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

        if !streamingEnglish.isEmpty {
            addCaption(english: streamingEnglish, chinese: streamingChinese)
        }
        streamingEnglish = ""
        streamingChinese = ""
        audioBuffer = []
        consecutiveSilentSamples = 0
    }

    // MARK: - Text Analysis

    private func isSilent(_ samples: [Float], threshold: Float = 0.01) -> Bool {
        guard !samples.isEmpty else { return true }
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        return rms < threshold
    }

    /// Strip bracketed hallucination markers like [BLANK_AUDIO], (speaking foreign language)
    private func cleanTranscription(_ text: String) -> String {
        var cleaned = text
        // Remove [anything] patterns
        cleaned = cleaned.replacingOccurrences(
            of: "\\[[^\\]]*\\]",
            with: "",
            options: .regularExpression
        )
        // Remove (audio description) patterns
        cleaned = cleaned.replacingOccurrences(
            of: "\\([^)]*(?:audio|language|music|silence|laughter|applause)[^)]*\\)",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Collapse multiple spaces
        cleaned = cleaned.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let hallucinations = [
            "you", "thank you", "thanks for watching", "bye",
            "thanks for listening", "see you next time", "subscribe",
            "...", "",
        ]
        return hallucinations.contains(lower) || lower.count < 3
    }

    /// Find the last sentence boundary (". " / "? " / "! ") that splits text into
    /// completed sentences + a remaining fragment. Returns nil if no split point.
    private func splitAtLastSentenceBoundary(_ text: String) -> (completed: String, remainder: String)? {
        let sentenceEnders: [(String, Int)] = [
            (". ", 2), ("? ", 2), ("! ", 2),   // period/question/exclamation + space
        ]
        var bestIndex = -1
        for (ender, len) in sentenceEnders {
            if let range = text.range(of: ender, options: .backwards) {
                let idx = text.distance(from: text.startIndex, to: range.lowerBound) + len
                if idx > bestIndex && idx < text.count {
                    bestIndex = idx
                }
            }
        }
        guard bestIndex > 3 else { return nil }  // need at least a few chars before boundary

        let completed = String(text.prefix(bestIndex)).trimmingCharacters(in: .whitespaces)
        let remainder = String(text.suffix(text.count - bestIndex)).trimmingCharacters(in: .whitespaces)
        guard !completed.isEmpty, !remainder.isEmpty else { return nil }
        return (completed, remainder)
    }

    // MARK: - Streaming Pipeline

    private func runStreamingPipeline(audioStream: AsyncStream<[Float]>) {
        let sampleRate = 16000

        // Timing thresholds
        let silenceForFinalize = Int(1.5 * Double(sampleRate))  // 1.5s silence → commit text
        let silenceForPurge = sampleRate * 2                     // 2s silence + no text → purge buffer
        let sentenceSplitThreshold = sampleRate * 4              // 4s → start splitting at sentence boundaries
        let maxBufferSize = sampleRate * 15                      // 15s absolute safety cap

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

        // Task 2: Adaptive transcription with sentence-aware finalization
        pipelineTask = Task {
            guard let transcription = self.transcriptionService else { return }
            var lastTranscription = ""
            var lastTranscribeBufferSize = 0
            let minNewSamples = sampleRate / 4

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { break }

                // ── Silence purge: 2s+ silence with no streaming → clear everything ──
                // Prevents hallucination after long silence periods
                if self.consecutiveSilentSamples >= silenceForPurge
                    && self.streamingEnglish.isEmpty
                {
                    self.audioBuffer.removeAll()
                    lastTranscription = ""
                    lastTranscribeBufferSize = 0
                    continue
                }

                // ── Silence finalize: 1.5s silence with active text → commit ──
                if self.consecutiveSilentSamples >= silenceForFinalize
                    && !self.streamingEnglish.isEmpty
                {
                    await self.finalizeCurrentCaption()
                    self.audioBuffer.removeAll()  // full clear after silence (no hallucination risk)
                    self.consecutiveSilentSamples = 0
                    lastTranscription = ""
                    lastTranscribeBufferSize = 0
                    continue
                }

                // ── Max buffer safety: hard finalize at 15s ──
                if self.audioBuffer.count >= maxBufferSize && !self.streamingEnglish.isEmpty {
                    AppLogger.log("Max buffer reached, force finalize")
                    await self.finalizeCurrentCaption()
                    // Keep 2s of audio for context continuity
                    self.audioBuffer = Array(self.audioBuffer.suffix(sampleRate * 2))
                    self.consecutiveSilentSamples = 0
                    lastTranscription = ""
                    lastTranscribeBufferSize = self.audioBuffer.count
                    continue
                }

                // ── Skip if not enough new audio ──
                let newSamples = self.audioBuffer.count - lastTranscribeBufferSize
                guard newSamples >= minNewSamples else { continue }

                // ── Skip if silent and nothing streaming ──
                let recentChunk = Array(self.audioBuffer.suffix(sampleRate / 3))
                if self.isSilent(recentChunk) && self.streamingEnglish.isEmpty { continue }

                // ── Transcribe full buffer ──
                let snapshot = self.audioBuffer
                lastTranscribeBufferSize = self.audioBuffer.count

                do {
                    var english = try await transcription.transcribe(audioBuffer: snapshot)

                    // Clean bracketed hallucination markers
                    english = self.cleanTranscription(english)

                    guard !self.isHallucination(english) else { continue }
                    guard english != lastTranscription else { continue }

                    lastTranscription = english

                    // ── Mid-stream sentence split (buffer > 4s) ──
                    // Commit completed sentences so reader sees stable text
                    if self.audioBuffer.count >= sentenceSplitThreshold,
                       let (completed, remainder) = self.splitAtLastSentenceBoundary(english)
                    {
                        // Translate and commit completed sentences
                        let chinese = (try? await self.translationService.translate(completed)) ?? ""
                        AppLogger.log("Sentence split EN: \(completed)")
                        AppLogger.log("Sentence split ZH: \(chinese)")
                        self.addCaption(english: completed, chinese: chinese)

                        // Show remainder as ongoing streaming
                        self.streamingEnglish = remainder
                        let remainderZH = (try? await self.translationService.translate(remainder)) ?? ""
                        self.streamingChinese = remainderZH
                        AppLogger.log("Streaming EN: \(remainder)")
                        AppLogger.log("Streaming ZH: \(remainderZH)")

                        // Trim buffer: estimate how much audio the remainder covers
                        let ratio = max(Double(remainder.count) / Double(english.count), 0.2)
                        let keepSamples = Int(Double(self.audioBuffer.count) * ratio) + sampleRate
                        self.audioBuffer = Array(self.audioBuffer.suffix(min(keepSamples, self.audioBuffer.count)))
                        lastTranscribeBufferSize = self.audioBuffer.count
                        lastTranscription = ""  // reset: trimmed buffer will produce different text
                        continue
                    }

                    // ── Normal streaming update ──
                    self.streamingEnglish = english
                    AppLogger.log("Streaming EN: \(english)")

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
