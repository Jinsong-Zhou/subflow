import Foundation
import SwiftUI
import Translation

@MainActor
@Observable
final class CaptionViewModel {
    var isRecording = false
    var currentEnglish = ""
    var currentChinese = ""
    var captionHistory: [CaptionEntry] = []
    var recentCaptions: [CaptionEntry] = []

    let translationService = TranslationService()

    private let maxRecentCaptions = 3
    private var audioCaptureService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var pipelineTask: Task<Void, Never>?

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
        if isRecording {
            stopCapture()
        } else {
            Task { await startCapture() }
        }
    }

    func startCapture() async {
        guard !isRecording else { return }

        do {
            let audioService = AudioCaptureService()
            let transcription = try await TranscriptionService.load()

            self.audioCaptureService = audioService
            self.transcriptionService = transcription
            self.isRecording = true

            try await audioService.start()
            runPipeline(audioService: audioService, transcription: transcription, translation: translationService)
        } catch {
            print("Failed to start capture: \(error)")
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
        transcriptionService = nil
    }

    private func runPipeline(
        audioService: AudioCaptureService,
        transcription: TranscriptionService,
        translation: TranslationService
    ) {
        pipelineTask = Task {
            var audioBuffer: [Float] = []
            let samplesPerChunk = 16000 * 3 // 3 seconds at 16kHz

            for await samples in audioService.audioStream {
                if Task.isCancelled { break }

                audioBuffer.append(contentsOf: samples)

                guard audioBuffer.count >= samplesPerChunk else { continue }

                let chunk = Array(audioBuffer.prefix(samplesPerChunk))
                audioBuffer.removeFirst(samplesPerChunk)

                do {
                    let english = try await transcription.transcribe(audioBuffer: chunk)
                    guard !english.isEmpty else { continue }

                    self.currentEnglish = english

                    let chinese = try await translation.translate(english)
                    self.currentChinese = chinese
                    self.addCaption(english: english, chinese: chinese)
                } catch {
                    print("Pipeline error: \(error)")
                }
            }
        }
    }
}
