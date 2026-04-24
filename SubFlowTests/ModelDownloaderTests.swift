import Testing
import Foundation
@testable import SubFlow

@Suite("ModelDownloader")
struct ModelDownloaderTests {

    // MARK: - isModelInstalled

    @Test("reports installed when all required files exist and are non-empty")
    func installedWhenAllFilesPresent() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let modelDir = tempRoot.appendingPathComponent("small-streaming-en")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for name in ModelDownloader.requiredFiles {
            try "dummy".data(using: .utf8)!
                .write(to: modelDir.appendingPathComponent(name))
        }

        #expect(ModelDownloader.isModelInstalled("small-streaming-en", inside: tempRoot))
    }

    @Test("reports not installed when directory is missing")
    func notInstalledWhenDirMissing() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        #expect(!ModelDownloader.isModelInstalled("small-streaming-en", inside: tempRoot))
    }

    @Test("reports not installed when a required file is missing")
    func notInstalledWhenAFileMissing() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let modelDir = tempRoot.appendingPathComponent("small-streaming-en")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        // Create all but the last required file.
        for name in ModelDownloader.requiredFiles.dropLast() {
            try "dummy".data(using: .utf8)!
                .write(to: modelDir.appendingPathComponent(name))
        }

        #expect(!ModelDownloader.isModelInstalled("small-streaming-en", inside: tempRoot))
    }

    @Test("reports not installed when a required file is zero bytes")
    func notInstalledWhenFileEmpty() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let modelDir = tempRoot.appendingPathComponent("small-streaming-en")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        for name in ModelDownloader.requiredFiles {
            let file = modelDir.appendingPathComponent(name)
            if name == "encoder.ort" {
                // Simulate aborted download: file exists but is empty.
                FileManager.default.createFile(atPath: file.path, contents: nil)
            } else {
                try "dummy".data(using: .utf8)!.write(to: file)
            }
        }

        #expect(!ModelDownloader.isModelInstalled("small-streaming-en", inside: tempRoot))
    }

    // MARK: - ModelSource

    @Test("knows the two official model IDs")
    func sourceKnownIds() {
        #expect(ModelSource.source(for: "small-streaming-en") != nil)
        #expect(ModelSource.source(for: "medium-streaming-en") != nil)
    }

    @Test("returns nil for unknown model IDs")
    func sourceUnknownId() {
        #expect(ModelSource.source(for: "nonexistent-model") == nil)
        #expect(ModelSource.source(for: "") == nil)
    }

    @Test("source URLs use https")
    func sourceURLsAreHTTPS() {
        let small = ModelSource.source(for: "small-streaming-en")!
        let medium = ModelSource.source(for: "medium-streaming-en")!
        #expect(small.url.scheme == "https")
        #expect(medium.url.scheme == "https")
    }

    // MARK: - ensureModel fast path

    @Test("ensureModel throws noSource for unknown IDs")
    func ensureModelUnknownId() async {
        await #expect(throws: ModelDownloadError.self) {
            _ = try await ModelDownloader.ensureModel("not-a-real-model")
        }
    }

    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("subflow-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
