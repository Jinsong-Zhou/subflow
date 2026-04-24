import Foundation

/// Where to fetch a Moonshine model's files from.
///
/// All eight required artifacts live under `<baseURL>/<filename>` on
/// `download.moonshine.ai` — Moonshine's own public CDN. Because the CDN is
/// upstream-controlled, there is no self-hosted asset SubFlow has to keep in
/// sync with model version bumps, and no integrity hash to maintain on our
/// side (the HTTPS channel is the trust boundary).
struct ModelSource: Sendable {
    let baseURL: URL
}

enum ModelDownloadError: LocalizedError {
    case noSource(String)
    case httpError(String, Int)
    case missingContentLength(String)
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .noSource(let id):
            return "No download URL configured for model '\(id)'. " +
                   "Open ModelDownloader.swift and add a case in ModelSource.source(for:)."
        case .httpError(let file, let code):
            return "Download of \(file) failed (HTTP \(code)). " +
                   "Check your internet connection and that download.moonshine.ai is reachable."
        case .missingContentLength(let file):
            return "Server did not return Content-Length for \(file). " +
                   "The upstream CDN (download.moonshine.ai) behaviour may have changed."
        case .invalidArchive(let msg):
            return "Model files downloaded but validation failed: \(msg)"
        }
    }
}

/// Downloads Moonshine ORT model files on demand.
///
/// Layout on disk:
///   ~/Library/Application Support/SubFlow/MoonshineModels/<modelId>/
///     ├── adapter.ort
///     ├── cross_kv.ort
///     ├── decoder_kv.ort
///     ├── decoder_kv_with_attention.ort
///     ├── encoder.ort
///     ├── frontend.ort
///     ├── streaming_config.json
///     └── tokenizer.bin
enum ModelDownloader {

    /// Files that every model directory must contain to be considered complete.
    static let requiredFiles: [String] = [
        "adapter.ort",
        "cross_kv.ort",
        "decoder_kv.ort",
        "decoder_kv_with_attention.ort",
        "encoder.ort",
        "frontend.ort",
        "streaming_config.json",
        "tokenizer.bin",
    ]

    /// Root directory for all locally cached models.
    static var modelsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SubFlow/MoonshineModels", isDirectory: true)
    }

    /// Returns `true` if every required file for `modelId` exists and is non-empty.
    /// Non-empty catches aborted downloads that created a zero-byte placeholder.
    static func isModelInstalled(_ modelId: String, inside root: URL? = nil) -> Bool {
        let dir = (root ?? modelsDirectory)
            .appendingPathComponent(modelId, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return false }
        for name in requiredFiles {
            let file = dir.appendingPathComponent(name).path
            guard let attrs = try? fm.attributesOfItem(atPath: file),
                  let size = attrs[.size] as? NSNumber,
                  size.int64Value > 0 else { return false }
        }
        return true
    }

    /// Ensures the model is available on disk. If missing, downloads each file
    /// from the upstream Moonshine CDN sequentially into a staging directory,
    /// then atomically renames staging → final. An aborted download leaves a
    /// staging dir (never the final dir), so the next attempt starts clean.
    ///
    /// - Parameters:
    ///   - modelId: e.g. `"small-streaming-en"`.
    ///   - onProgress: Called with aggregate download progress in `[0.0, 1.0]`
    ///     from an arbitrary queue. Caller must hop to the main actor before
    ///     touching UI state.
    /// - Returns: URL of the ready-to-use model directory.
    @discardableResult
    static func ensureModel(
        _ modelId: String,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        migrateLegacyModelsIfNeeded()

        let modelDir = modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
        if isModelInstalled(modelId) {
            AppLogger.log("Model '\(modelId)' already installed, skipping download")
            return modelDir
        }

        guard let source = ModelSource.source(for: modelId) else {
            throw ModelDownloadError.noSource(modelId)
        }

        AppLogger.log("Fetching model '\(modelId)' from \(source.baseURL)")
        try FileManager.default.createDirectory(
            at: modelsDirectory, withIntermediateDirectories: true
        )

        let staging = modelsDirectory
            .appendingPathComponent("\(modelId).staging", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: true
        )

        // Explicit timeouts. The default `timeoutIntervalForResource` is seven
        // days; an idle connection would freeze the progress window for a week.
        // `waitsForConnectivity = false`: this is a foreground download the
        // user is actively watching — fail fast so retries kick in, do not
        // silently wait up to a minute for a flaky network to come back.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false

        // Phase 1: HEAD all files to learn the grand total, so the progress bar
        // is byte-accurate (the two decoder files alone are ~65% of a Medium
        // download — equal-slice progress would look wrong).
        let sizes = try await discoverSizes(source: source, config: config)
        let grandTotal = sizes.reduce(0, +)
        AppLogger.log("Model '\(modelId)' total download size: \(grandTotal) bytes")

        // Phase 2: download each file sequentially, reporting cumulative
        // progress against `grandTotal`.
        var completed: Int64 = 0
        for (file, expected) in zip(requiredFiles, sizes) {
            let fileURL = source.baseURL.appendingPathComponent(file)
            let destURL = staging.appendingPathComponent(file)
            let offset = completed

            try await downloadFile(
                from: fileURL,
                to: destURL,
                config: config,
                onProgress: { fileBytes in
                    guard grandTotal > 0 else { return }
                    let overall = Double(offset + fileBytes) / Double(grandTotal)
                    onProgress(min(1.0, overall))
                }
            )

            completed += expected
            if grandTotal > 0 {
                onProgress(min(1.0, Double(completed) / Double(grandTotal)))
            }
        }

        // Atomic swap.
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        try FileManager.default.moveItem(at: staging, to: modelDir)

        guard isModelInstalled(modelId) else {
            throw ModelDownloadError.invalidArchive(
                "Downloaded files are missing from \(modelDir.path)"
            )
        }

        onProgress(1.0)
        AppLogger.log("Model '\(modelId)' installed at \(modelDir.path)")
        return modelDir
    }

    // MARK: - Internals

    /// Pre-1.0 path name. Move anything from there into the new directory so
    /// long-time users don't re-download the ~450MB they already have on disk.
    static func migrateLegacyModelsIfNeeded() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let newDir = appSupport.appendingPathComponent("SubFlow/MoonshineModels")
        let oldDir = appSupport.appendingPathComponent("TranslatedCaption/MoonshineModels")

        guard !FileManager.default.fileExists(atPath: newDir.path),
              FileManager.default.fileExists(atPath: oldDir.path) else { return }

        do {
            try FileManager.default.createDirectory(
                at: newDir.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: oldDir, to: newDir)
            AppLogger.log("Migrated models from TranslatedCaption to SubFlow")
        } catch {
            AppLogger.log("Model migration failed: \(error.localizedDescription)")
        }
    }

    private static func discoverSizes(
        source: ModelSource, config: URLSessionConfiguration
    ) async throws -> [Int64] {
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var sizes: [Int64] = []
        for file in requiredFiles {
            var request = URLRequest(url: source.baseURL.appendingPathComponent(file))
            request.httpMethod = "HEAD"
            let (_, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw ModelDownloadError.httpError(file, -1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ModelDownloadError.httpError(file, http.statusCode)
            }
            guard response.expectedContentLength > 0 else {
                throw ModelDownloadError.missingContentLength(file)
            }
            sizes.append(response.expectedContentLength)
        }
        return sizes
    }

    /// Maximum number of attempts per file before giving up. Each attempt starts
    /// with a fresh `URLSession` so transient proxy/NAT state from a previous
    /// failure cannot stick around. Covers the common case of an intermittent
    /// MITM proxy or QUIC-fallback hiccup.
    private static let downloadMaxAttempts = 3

    private static func downloadFile(
        from url: URL,
        to destination: URL,
        config: URLSessionConfiguration,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        // Some proxies display progress monotonically going backwards on retry
        // because the second attempt's `totalBytesWritten` starts at 0 again.
        // Wrap `onProgress` with a high-water mark so the UI never regresses.
        let maxReported = HighWaterMark()
        let guardedProgress: @Sendable (Int64) -> Void = { bytes in
            onProgress(maxReported.record(bytes))
        }

        var lastError: Error?
        for attempt in 1...downloadMaxAttempts {
            do {
                let delegate = ProgressDelegate(onProgress: guardedProgress)
                let session = URLSession(
                    configuration: config, delegate: delegate, delegateQueue: nil
                )
                defer { session.invalidateAndCancel() }

                let (downloadedURL, response) = try await session.download(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw ModelDownloadError.httpError(
                        url.lastPathComponent, http.statusCode
                    )
                }

                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: downloadedURL, to: destination)
                if attempt > 1 {
                    AppLogger.log(
                        "Retry succeeded for \(url.lastPathComponent) on attempt \(attempt)"
                    )
                }
                return
            } catch {
                lastError = error
                let ns = error as NSError
                AppLogger.log(
                    "Download attempt \(attempt)/\(downloadMaxAttempts) failed for \(url.lastPathComponent): " +
                    "\(ns.domain) code=\(ns.code) \(ns.localizedDescription)"
                )
                if attempt == downloadMaxAttempts { break }
                // Exponential backoff: 1s, 2s.
                let seconds = 1 << (attempt - 1)
                try await Task.sleep(for: .seconds(seconds))
            }
        }
        throw lastError ?? ModelDownloadError.httpError(url.lastPathComponent, -1)
    }
}

/// Thread-safe high-water mark for progress reporting. Prevents the UI from
/// visually regressing when a retry restarts bytes at zero.
private final class HighWaterMark: @unchecked Sendable {
    private let lock = NSLock()
    private var max: Int64 = 0

    func record(_ bytes: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        if bytes > max { max = bytes }
        return max
    }
}

// MARK: - URLSession delegate forwarding per-file progress.

private final class ProgressDelegate: NSObject,
    URLSessionDownloadDelegate, @unchecked Sendable
{
    let onProgress: @Sendable (Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // No-op: the async `download(from:)` return value hands us the temp URL.
    }
}

// MARK: - Source table.

extension ModelSource {
    /// Returns the upstream URL prefix to fetch `modelId` from, or `nil` for
    /// unknown IDs.
    ///
    /// Moonshine publishes each model's `.ort` files at
    /// `https://download.moonshine.ai/model/<modelId>/quantized/<file>` — the
    /// same CDN their `pip install moonshine-voice && python -m
    /// moonshine_voice.download --language en` tooling hits under the hood.
    /// Pointing SubFlow at that CDN directly avoids mirroring model weights on
    /// our own GitHub and keeps us on whichever version upstream ships.
    static func source(for modelId: String) -> ModelSource? {
        let base = "https://download.moonshine.ai/model"
        switch modelId {
        case "small-streaming-en":
            return ModelSource(
                baseURL: URL(string: "\(base)/small-streaming-en/quantized")!
            )
        case "medium-streaming-en":
            return ModelSource(
                baseURL: URL(string: "\(base)/medium-streaming-en/quantized")!
            )
        default:
            return nil
        }
    }
}
