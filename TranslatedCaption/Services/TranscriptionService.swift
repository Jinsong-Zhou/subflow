import Foundation
import WhisperKit

final class TranscriptionService: @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    static func load() async throws -> TranscriptionService {
        // Persistent model cache in Application Support so models survive rebuilds
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("TranslatedCaption/Models")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let config = WhisperKitConfig(
            model: "openai_whisper-base",
            downloadBase: modelDir,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            useBackgroundDownloadSession: false
        )
        let kit = try await WhisperKit(config)
        return TranscriptionService(whisperKit: kit)
    }

    func transcribe(audioBuffer: [Float]) async throws -> String {
        let options = DecodingOptions(
            language: "en",
            skipSpecialTokens: true,
            withoutTimestamps: true,
            clipTimestamps: []
        )
        let results = try await whisperKit.transcribe(
            audioArray: audioBuffer,
            decodeOptions: options
        )
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}
