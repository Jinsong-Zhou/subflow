import Foundation
import CryptoKit

/// Where a model archive is hosted and (optionally) its integrity hash.
struct ModelSource: Sendable {
    let url: URL
    /// Lowercase hex SHA-256 of the zip archive. `nil` = skip integrity check.
    let expectedSHA256: String?
}

enum ModelDownloadError: LocalizedError {
    case noSource(String)
    case httpError(Int)
    case extractionFailed(String)
    case integrityFailed(String)
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .noSource(let id):
            return "No download URL configured for model '\(id)'. " +
                   "Open ModelSource.swift and paste the URL after running scripts/upload-models.sh."
        case .httpError(let code):
            return "Model download failed (HTTP \(code)). Check your internet connection."
        case .extractionFailed(let msg):
            return "Archive extraction failed: \(msg)"
        case .integrityFailed(let msg):
            return "Downloaded model failed integrity check: \(msg)"
        case .invalidArchive(let msg):
            return "Archive did not contain a valid model: \(msg)"
        }
    }
}

/// Downloads Moonshine ORT model bundles on demand.
///
/// Model layout on disk (after extraction):
///   ~/Library/Application Support/SubFlow/MoonshineModels/<modelId>/
///     ├── adapter.ort
///     ├── cross_kv.ort
///     ├── decoder_kv.ort
///     ├── decoder_kv_with_attention.ort
///     ├── encoder.ort
///     ├── frontend.ort
///     ├── streaming_config.json
///     └── tokenizer.bin
///
/// Archives are hosted on GitHub Releases as `<modelId>.zip`.
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

    /// Ensures the model is available on disk. If missing, downloads and extracts it.
    /// - Parameters:
    ///   - modelId: e.g. `"small-streaming-en"`.
    ///   - onProgress: Called with download progress in `[0.0, 1.0]` from an
    ///     arbitrary queue. Callers wishing to update UI state must hop to the
    ///     main actor themselves.
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

        AppLogger.log("Downloading model '\(modelId)' from \(source.url)")
        try FileManager.default.createDirectory(
            at: modelsDirectory, withIntermediateDirectories: true
        )

        let tempZip = modelsDirectory.appendingPathComponent("\(modelId).download.zip")
        try? FileManager.default.removeItem(at: tempZip)

        let delegate = ProgressDelegate(onProgress: onProgress)
        // Explicit timeouts: the system default for `timeoutIntervalForResource`
        // is seven days — a stalled connection would leave the progress window
        // frozen for a week. Ten minutes is generous for ~450 MB on a sane link.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        let session = URLSession(
            configuration: config, delegate: delegate, delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let (downloadedURL, response) = try await session.download(from: source.url)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw ModelDownloadError.httpError(http.statusCode)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: tempZip)

        if let expected = source.expectedSHA256 {
            let actual = try await sha256Hex(of: tempZip)
            guard actual.lowercased() == expected.lowercased() else {
                try? FileManager.default.removeItem(at: tempZip)
                throw ModelDownloadError.integrityFailed(
                    "expected \(expected), got \(actual)"
                )
            }
        }

        let stagingDir = modelsDirectory
            .appendingPathComponent("\(modelId).staging", isDirectory: true)
        try? FileManager.default.removeItem(at: stagingDir)
        try FileManager.default.createDirectory(
            at: stagingDir, withIntermediateDirectories: true
        )
        try await extractZip(at: tempZip, to: stagingDir)

        let extracted = try locateModelRoot(in: stagingDir, modelId: modelId)

        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        try FileManager.default.moveItem(at: extracted, to: modelDir)

        try? FileManager.default.removeItem(at: stagingDir)
        try? FileManager.default.removeItem(at: tempZip)

        guard isModelInstalled(modelId) else {
            throw ModelDownloadError.invalidArchive(
                "Extraction succeeded but required files are missing in \(modelDir.path)"
            )
        }

        AppLogger.log("Model '\(modelId)' installed at \(modelDir.path)")
        return modelDir
    }

    // MARK: - Internals

    /// Pre-1.0 path name. Move anything from there into the new directory so that
    /// long-time users don't re-download the 700MB they already have on disk.
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

    private static func locateModelRoot(in stagingDir: URL, modelId: String) throws -> URL {
        let fm = FileManager.default
        let rootContents = (try? fm.contentsOfDirectory(atPath: stagingDir.path)) ?? []

        if requiredFiles.allSatisfy({ rootContents.contains($0) }) {
            return stagingDir
        }

        for name in rootContents {
            let candidate = stagingDir.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: candidate.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let nested = (try? fm.contentsOfDirectory(atPath: candidate.path)) ?? []
            if requiredFiles.allSatisfy({ nested.contains($0) }) {
                return candidate
            }
        }

        throw ModelDownloadError.invalidArchive(
            "Zip does not contain the expected files for '\(modelId)'. " +
            "Found at root: \(rootContents)"
        )
    }

    /// Runs `/usr/bin/unzip` on a detached task so `Process.waitUntilExit()`
    /// cannot block whichever executor `ensureModel` happens to be suspended on.
    /// Unzipping a 300 MB archive takes tens of seconds on a typical Mac — more
    /// than enough to freeze the UI if this ran on the main actor.
    private static func extractZip(at zip: URL, to dest: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-q", "-o", zip.path, "-d", dest.path]
            let err = Pipe()
            proc.standardError = err
            do {
                try proc.run()
            } catch {
                throw ModelDownloadError.extractionFailed(error.localizedDescription)
            }
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                let stderr = String(
                    data: err.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw ModelDownloadError.extractionFailed(
                    "unzip exit \(proc.terminationStatus): \(stderr)"
                )
            }
        }.value
    }

    /// Same rationale as `extractZip`: `Data(contentsOf:)` + `SHA256.hash` reads
    /// and hashes up to ~300 MB synchronously. Run on a detached task.
    private static func sha256Hex(of file: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            return SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }.value
    }
}

// MARK: - URLSession delegate forwarding progress.

private final class ProgressDelegate: NSObject,
    URLSessionDownloadDelegate, @unchecked Sendable
{
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // No-op: the async `download(from:)` return value hands us the temp URL.
    }
}

// MARK: - User-configurable source table.

extension ModelSource {
    /// Returns where to download `modelId` from, or `nil` if there is no known source.
    ///
    /// ## Pine — fill this in after the first upload.
    ///
    /// Run `scripts/upload-models.sh <release-tag>` to:
    ///   1. Zip both local model directories.
    ///   2. Upload them to a GitHub Release.
    ///   3. Print the browser download URL and SHA-256 of each zip.
    ///
    /// Paste those URLs and hashes into the `switch` below. The first time a new
    /// user launches SubFlow, this function tells the downloader where to fetch
    /// the ~157 MB (Small) or ~303 MB (Medium) archive from.
    ///
    /// ### Decisions encoded here
    ///
    /// - **Release-tag strategy.** The template uses `models-v1` — a dedicated tag
    ///   that is independent of app version, so every app release does not have to
    ///   re-upload hundreds of MB. Bump to `models-v2` only when Moonshine model
    ///   weights actually change.
    /// - **Integrity.** Passing a non-nil `expectedSHA256` makes the downloader
    ///   verify the zip before extracting. This catches corrupted downloads and
    ///   any tampering. Skip (`nil`) only if you really trust HTTPS end-to-end.
    static func source(for modelId: String) -> ModelSource? {
        let base = "https://github.com/Jinsong-Zhou/subflow/releases/download/models-v1"
        switch modelId {
        case "small-streaming-en":
            return ModelSource(
                url: URL(string: "\(base)/small-streaming-en.zip")!,
                // TODO: replace with the SHA-256 printed by scripts/upload-models.sh
                expectedSHA256: nil
            )
        case "medium-streaming-en":
            return ModelSource(
                url: URL(string: "\(base)/medium-streaming-en.zip")!,
                // TODO: replace with the SHA-256 printed by scripts/upload-models.sh
                expectedSHA256: nil
            )
        default:
            return nil
        }
    }
}
