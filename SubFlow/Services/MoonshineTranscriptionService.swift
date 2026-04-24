import Foundation
import MoonshineVoice

struct WordTimestamp {
    let word: String
    let start: Float
    let end: Float
    let confidence: Float
}

final class MoonshineTranscriptionService: @unchecked Sendable {
    private var transcriber: Transcriber?
    private var stream: MoonshineVoice.Stream?

    var onTextChanged: (@MainActor @Sendable (String, [WordTimestamp]) -> Void)?
    var onLineCompleted: (@MainActor @Sendable (String, [WordTimestamp]) -> Void)?

    private init() {}

    /// Ensures the model is on disk (downloading if necessary) and returns a
    /// loaded transcription service.
    ///
    /// - Parameters:
    ///   - modelId: e.g. `"small-streaming-en"` or `"medium-streaming-en"`.
    ///   - onDownloadProgress: Called with `[0.0, 1.0]` during any required
    ///     download. Not called when the model is already cached.
    static func load(
        modelId: String,
        onDownloadProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> MoonshineTranscriptionService {
        let modelDir = try await ModelDownloader.ensureModel(
            modelId, onProgress: onDownloadProgress
        )

        let modelArch: ModelArch
        switch modelId {
        case "small-streaming-en": modelArch = .smallStreaming
        case "medium-streaming-en": modelArch = .mediumStreaming
        default: modelArch = .mediumStreaming
        }

        let options = [TranscriberOption(name: "word_timestamps", value: "true")]
        AppLogger.log("Loading Moonshine model: \(modelId) at \(modelDir.path)")
        let service = MoonshineTranscriptionService()
        service.transcriber = try Transcriber(
            modelPath: modelDir.path,
            modelArch: modelArch,
            options: options
        )
        AppLogger.log("Moonshine model loaded (word_timestamps enabled)")
        return service
    }

    func startStream(updateInterval: TimeInterval = 0.5) throws {
        stream = try transcriber?.createStream(updateInterval: updateInterval)
        stream?.addListener { [weak self] event in
            guard let self else { return }
            switch event {
            case let e as LineTextChanged:
                let text = e.line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                let words = Self.extractWords(from: e.line)
                let callback = self.onTextChanged
                Task { @MainActor in callback?(text, words) }
            case let e as LineCompleted:
                let text = e.line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                let words = Self.extractWords(from: e.line)
                let callback = self.onLineCompleted
                Task { @MainActor in callback?(text, words) }
            case let e as MoonshineVoice.TranscriptError:
                AppLogger.log("Moonshine error: \(e.error.localizedDescription)")
            default:
                break
            }
        }
        try stream?.start()
    }

    func addAudio(_ samples: [Float], sampleRate: Int32 = 16000) throws {
        try stream?.addAudio(samples, sampleRate: sampleRate)
    }

    func stopStream() throws {
        try stream?.stop()
    }

    func close() {
        stream?.close()
        transcriber?.close()
        stream = nil
        transcriber = nil
    }

    private static func extractWords(from line: TranscriptLine) -> [WordTimestamp] {
        line.words.map { w in
            WordTimestamp(word: w.word, start: w.start, end: w.end, confidence: w.confidence)
        }
    }
}
