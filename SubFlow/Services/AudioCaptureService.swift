import AVFoundation
import ScreenCaptureKit

final class AudioCaptureService: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var _audioStream: AsyncStream<[Float]>?

    /// Must be accessed BEFORE calling start() to set up the continuation
    func makeAudioStream() -> AsyncStream<[Float]> {
        let stream = AsyncStream<[Float]> { continuation in
            self.continuation = continuation
        }
        _audioStream = stream
        return stream
    }

    func start() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = 1
        config.sampleRate = 16000
        config.width = 2
        config.height = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        continuation?.finish()
        continuation = nil
    }
}

extension AudioCaptureService: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard let blockBuffer = sampleBuffer.dataBuffer else { return }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        var data = Data(count: length)
        data.withUnsafeMutableBytes { rawBuffer in
            CMBlockBufferCopyDataBytes(
                blockBuffer, atOffset: 0, dataLength: length,
                destination: rawBuffer.baseAddress!
            )
        }

        let floatCount = length / MemoryLayout<Float>.size
        let floats = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self).prefix(floatCount))
        }

        if !floats.isEmpty {
            continuation?.yield(floats)
        }
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case noDisplayFound

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for audio capture"
        }
    }
}
