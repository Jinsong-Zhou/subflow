import WhisperKit

final class TranscriptionService: @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    static func load() async throws -> TranscriptionService {
        let kit = try await WhisperKit(model: "large-v3-turbo")
        return TranscriptionService(whisperKit: kit)
    }

    func transcribe(audioBuffer: [Float]) async throws -> String {
        let results = try await whisperKit.transcribe(audioArray: audioBuffer)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}
