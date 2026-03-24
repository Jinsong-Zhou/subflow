# TranslatedCaption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS app that captures system audio, transcribes English speech in real-time via WhisperKit, translates to Chinese via Apple Translation, and displays bilingual subtitles in a floating overlay.

**Architecture:** Single-process pipeline using Swift Concurrency. Audio buffers flow through `AsyncStream` from ScreenCaptureKit capture to WhisperKit transcription to Apple Translation, with an `@Observable` ViewModel driving both a floating subtitle panel and a main transcript window.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSPanel), ScreenCaptureKit, AVFoundation, WhisperKit (SPM), Apple Translation framework, xcodegen (project generation)

---

## File Map

| File | Responsibility |
|------|----------------|
| `project.yml` | xcodegen project definition (targets, SPM deps, entitlements) |
| `TranslatedCaption/TranslatedCaptionApp.swift` | App entry point, window management, environment wiring |
| `TranslatedCaption/Models/CaptionEntry.swift` | Subtitle data model |
| `TranslatedCaption/Services/AudioCaptureService.swift` | ScreenCaptureKit system audio capture + resample |
| `TranslatedCaption/Services/TranscriptionService.swift` | WhisperKit speech-to-text |
| `TranslatedCaption/Services/TranslationService.swift` | Apple Translation English→Chinese |
| `TranslatedCaption/ViewModels/CaptionViewModel.swift` | Pipeline coordinator, state management |
| `TranslatedCaption/Views/MainWindowView.swift` | Main window with toolbar + transcript list |
| `TranslatedCaption/Views/FloatingCaptionView.swift` | Floating subtitle content |
| `TranslatedCaption/Windows/FloatingPanel.swift` | NSPanel subclass (always-on-top, non-activating) |
| `TranslatedCaption/Utilities/HotkeyManager.swift` | Global Cmd+Shift+T registration |
| `TranslatedCaption/Resources/Info.plist` | Privacy descriptions |
| `TranslatedCaption/Resources/TranslatedCaption.entitlements` | Sandbox disabled |
| `TranslatedCaptionTests/CaptionEntryTests.swift` | Model tests |
| `TranslatedCaptionTests/CaptionViewModelTests.swift` | ViewModel logic tests |

---

### Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `TranslatedCaption/Resources/Info.plist`
- Create: `TranslatedCaption/Resources/TranslatedCaption.entitlements`
- Create: `TranslatedCaption/TranslatedCaptionApp.swift` (placeholder)

- [ ] **Step 1: Install xcodegen if needed**

```bash
brew install xcodegen
```

- [ ] **Step 2: Create project.yml**

```yaml
name: TranslatedCaption
options:
  bundleIdPrefix: com.pinechou
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "16.0"
  minimumXcodeGenVersion: "2.40.0"

packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit
    from: "0.9.0"

targets:
  TranslatedCaption:
    type: application
    platform: macOS
    sources:
      - TranslatedCaption
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pinechou.TranslatedCaption
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "6.0"
        CODE_SIGN_ENTITLEMENTS: TranslatedCaption/Resources/TranslatedCaption.entitlements
        INFOPLIST_FILE: TranslatedCaption/Resources/Info.plist
    dependencies:
      - package: WhisperKit
    entitlements:
      path: TranslatedCaption/Resources/TranslatedCaption.entitlements

  TranslatedCaptionTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - TranslatedCaptionTests
    dependencies:
      - target: TranslatedCaption
    settings:
      base:
        SWIFT_VERSION: "6.0"
```

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSScreenCaptureUsageDescription</key>
    <string>TranslatedCaption needs screen recording permission to capture system audio for real-time transcription.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create entitlements (sandbox disabled)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 5: Create placeholder app entry point**

```swift
// TranslatedCaption/TranslatedCaptionApp.swift
import SwiftUI

@main
struct TranslatedCaptionApp: App {
    var body: some Scene {
        WindowGroup {
            Text("TranslatedCaption")
                .frame(width: 600, height: 400)
        }
    }
}
```

- [ ] **Step 6: Create test directory placeholder**

```swift
// TranslatedCaptionTests/TranslatedCaptionTests.swift
import Testing

@Test func appLaunches() {
    // Placeholder — will be replaced with real tests
    #expect(true)
}
```

- [ ] **Step 7: Generate Xcode project and verify build**

```bash
xcodegen generate
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

Expected: Build succeeds, app launches showing "TranslatedCaption" text.

- [ ] **Step 8: Commit**

```bash
git add project.yml TranslatedCaption/ TranslatedCaptionTests/ .gitignore
git commit -m "chore: scaffold Xcode project with xcodegen and WhisperKit dependency"
```

Note: Add `TranslatedCaption.xcodeproj` to `.gitignore` — it is generated from `project.yml`.

---

### Task 2: Data Model

**Files:**
- Create: `TranslatedCaption/Models/CaptionEntry.swift`
- Create: `TranslatedCaptionTests/CaptionEntryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// TranslatedCaptionTests/CaptionEntryTests.swift
import Testing
import Foundation
@testable import TranslatedCaption

@Test func captionEntryHasUniqueId() {
    let a = CaptionEntry(timestamp: .now, englishText: "Hello", chineseText: "你好")
    let b = CaptionEntry(timestamp: .now, englishText: "Hello", chineseText: "你好")
    #expect(a.id != b.id)
}

@Test func captionEntryStoresTexts() {
    let entry = CaptionEntry(timestamp: .now, englishText: "Hello world", chineseText: "你好世界")
    #expect(entry.englishText == "Hello world")
    #expect(entry.chineseText == "你好世界")
}
```

- [ ] **Step 2: Run tests — verify FAIL**

```bash
xcodebuild test -project TranslatedCaption.xcodeproj -scheme TranslatedCaptionTests -destination 'platform=macOS'
```

Expected: FAIL — `CaptionEntry` not found.

- [ ] **Step 3: Implement CaptionEntry**

```swift
// TranslatedCaption/Models/CaptionEntry.swift
import Foundation

struct CaptionEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let englishText: String
    let chineseText: String
}
```

- [ ] **Step 4: Run tests — verify PASS**

```bash
xcodebuild test -project TranslatedCaption.xcodeproj -scheme TranslatedCaptionTests -destination 'platform=macOS'
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add TranslatedCaption/Models/ TranslatedCaptionTests/CaptionEntryTests.swift
git commit -m "feat: add CaptionEntry data model with tests"
```

---

### Task 3: Floating Panel Infrastructure

**Files:**
- Create: `TranslatedCaption/Windows/FloatingPanel.swift`

- [ ] **Step 1: Implement FloatingPanel**

```swift
// TranslatedCaption/Windows/FloatingPanel.swift
import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }
}
```

Key design decisions:
- `.nonactivatingPanel` — does not steal focus from other apps
- `.fullSizeContentView` — content extends to window edges (no title bar chrome)
- `isMovableByWindowBackground` — user can drag to reposition
- `collectionBehavior` — visible in all Spaces and alongside fullscreen apps
- `hidesOnDeactivate = false` — stays visible when app is not frontmost

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add TranslatedCaption/Windows/
git commit -m "feat: add FloatingPanel NSPanel subclass for subtitle overlay"
```

---

### Task 4: Floating Caption View

**Files:**
- Create: `TranslatedCaption/Views/FloatingCaptionView.swift`

- [ ] **Step 1: Implement FloatingCaptionView**

```swift
// TranslatedCaption/Views/FloatingCaptionView.swift
import SwiftUI

struct FloatingCaptionView: View {
    @Environment(CaptionViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.recentCaptions) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.englishText)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(entry.chineseText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.47, green: 0.78, blue: 1.0).opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.85))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add TranslatedCaption/Views/FloatingCaptionView.swift
git commit -m "feat: add FloatingCaptionView with minimal dark subtitle style"
```

---

### Task 5: Main Window View

**Files:**
- Create: `TranslatedCaption/Views/MainWindowView.swift`

- [ ] **Step 1: Implement MainWindowView**

```swift
// TranslatedCaption/Views/MainWindowView.swift
import SwiftUI

struct MainWindowView: View {
    @Environment(CaptionViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        VStack(spacing: 0) {
            toolbar
            Divider()
            transcriptList
        }
        .frame(minWidth: 500, minHeight: 300)
        .preferredColorScheme(.dark)
    }

    private var toolbar: some View {
        HStack {
            Button(action: { viewModel.toggleCapture() }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRecording ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRecording ? "Recording" : "Start")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.isRecording
                              ? Color.green.opacity(0.15)
                              : Color.gray.opacity(0.15))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Cmd+Shift+T")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.captionHistory) { entry in
                        CaptionRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.captionHistory.count) {
                if let last = viewModel.captionHistory.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct CaptionRow: View {
    let entry: CaptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(entry.englishText)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))
            Text(entry.chineseText)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.47, green: 0.78, blue: 1.0).opacity(0.8))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}
```

- [ ] **Step 2: Create stub CaptionViewModel for compilation**

The view depends on `CaptionViewModel`. Create a minimal stub so the view compiles. The full implementation comes in Task 8.

```swift
// TranslatedCaption/ViewModels/CaptionViewModel.swift
import Foundation
import SwiftUI

@Observable
final class CaptionViewModel {
    var isRecording = false
    var currentEnglish = ""
    var currentChinese = ""
    var captionHistory: [CaptionEntry] = []
    var recentCaptions: [CaptionEntry] = []

    func startCapture() { isRecording = true }
    func stopCapture() { isRecording = false }

    func toggleCapture() {
        if isRecording { stopCapture() } else { startCapture() }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

- [ ] **Step 4: Commit**

```bash
git add TranslatedCaption/Views/MainWindowView.swift TranslatedCaption/ViewModels/CaptionViewModel.swift
git commit -m "feat: add MainWindowView with toolbar and transcript list"
```

---

### Task 6: Audio Capture Service

**Files:**
- Create: `TranslatedCaption/Services/AudioCaptureService.swift`

- [ ] **Step 1: Implement AudioCaptureService**

```swift
// TranslatedCaption/Services/AudioCaptureService.swift
import AVFoundation
import ScreenCaptureKit

final class AudioCaptureService: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var continuation: AsyncStream<[Float]>.Continuation?

    var audioStream: AsyncStream<[Float]> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
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
        config.sampleRate = 16000
        config.channelCount = 1

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
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
```

Key decisions:
- `excludesCurrentProcessAudio = true` — avoids feedback loop
- `sampleRate = 16000`, `channelCount = 1` — WhisperKit's required format
- **Deliberate simplification from spec:** SCStreamConfiguration handles resampling natively, so AVAudioEngine is not needed as a separate step. If audio quality issues arise with certain audio devices, add an AVAudioEngine resample pass as a fallback.
- Audio data extracted from `CMSampleBuffer` as `[Float]` array
- Guard against missing display with descriptive error instead of force-unwrap

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add TranslatedCaption/Services/AudioCaptureService.swift
git commit -m "feat: add AudioCaptureService with ScreenCaptureKit system audio capture"
```

---

### Task 7: Transcription Service

**Files:**
- Create: `TranslatedCaption/Services/TranscriptionService.swift`

- [ ] **Step 1: Implement TranscriptionService**

```swift
// TranslatedCaption/Services/TranscriptionService.swift
import WhisperKit

final class TranscriptionService: Sendable {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    static func load() async throws -> TranscriptionService {
        let kit = try await WhisperKit(model: "large-v3-turbo")
        return TranscriptionService(whisperKit: kit)
    }

    func transcribe(audioBuffer: [Float]) async throws -> String {
        let result = try await whisperKit.transcribe(audioArray: audioBuffer)
        let text = result
            .compactMap(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}
```

Key decisions:
- `large-v3-turbo` model — good accuracy/speed balance for Apple Silicon
- Model downloaded on first launch (WhisperKit handles this automatically)
- `transcribe(audioArray:)` accepts raw Float array — matches AudioCaptureService output
- Results joined into single string per chunk

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

Note: WhisperKit API may differ slightly from plan. Check WhisperKit docs if build fails and adjust method signatures accordingly. The core flow (init with model name, transcribe audio array, extract text) is stable.

- [ ] **Step 3: Commit**

```bash
git add TranslatedCaption/Services/TranscriptionService.swift
git commit -m "feat: add TranscriptionService with WhisperKit speech-to-text"
```

---

### Task 8: Translation Service

**Files:**
- Create: `TranslatedCaption/Services/TranslationService.swift`

- [ ] **Step 1: Implement TranslationService**

The Apple Translation framework requires a `TranslationSession` obtained through SwiftUI's `.translationTask` modifier. We use a service class that receives the session from the view layer.

```swift
// TranslatedCaption/Services/TranslationService.swift
import Translation

final class TranslationService {
    private var session: TranslationSession?

    var configuration: TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: .init(identifier: "en"),
            target: .init(identifier: "zh-Hans")
        )
    }

    func setSession(_ session: TranslationSession) {
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        guard let session else {
            throw TranslationError.sessionNotReady
        }
        let response = try await session.translate(text)
        return response.targetText
    }
}

enum TranslationError: Error, LocalizedError {
    case sessionNotReady

    var errorDescription: String? {
        switch self {
        case .sessionNotReady:
            return "Translation session is not initialized"
        }
    }
}
```

The `.translationTask` modifier will be added in the app entry point (Task 11) to obtain the session and pass it to the service:

```swift
// In TranslatedCaptionApp or MainWindowView:
.translationTask(viewModel.translationConfig) { session in
    viewModel.setTranslationSession(session)
}
```

Key decisions:
- Session obtained via `.translationTask` SwiftUI modifier (required by Apple Translation framework)
- Service holds the session reference, view layer provides it at startup
- Source: English, Target: Simplified Chinese
- Translation model downloaded by system on first use

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add TranslatedCaption/Services/TranslationService.swift
git commit -m "feat: add TranslationService with Apple Translation framework"
```

---

### Task 9: CaptionViewModel — Full Implementation

**Files:**
- Modify: `TranslatedCaption/ViewModels/CaptionViewModel.swift` (replace stub)
- Create: `TranslatedCaptionTests/CaptionViewModelTests.swift`

- [ ] **Step 1: Write failing tests for ViewModel logic**

```swift
// TranslatedCaptionTests/CaptionViewModelTests.swift
import Testing
import Foundation
@testable import TranslatedCaption

@Test func initialStateIsNotRecording() {
    let vm = CaptionViewModel()
    #expect(vm.isRecording == false)
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
}

@Test func addCaptionAppendsToHistory() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Hello", chinese: "你好")
    #expect(vm.captionHistory.count == 1)
    #expect(vm.captionHistory[0].englishText == "Hello")
    #expect(vm.captionHistory[0].chineseText == "你好")
}

@Test func recentCaptionsLimitedToThree() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "One", chinese: "一")
    vm.addCaption(english: "Two", chinese: "二")
    vm.addCaption(english: "Three", chinese: "三")
    vm.addCaption(english: "Four", chinese: "四")
    #expect(vm.recentCaptions.count == 3)
    #expect(vm.recentCaptions[0].englishText == "Two")
    #expect(vm.recentCaptions[2].englishText == "Four")
}

@Test func clearHistoryRemovesAllEntries() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Test", chinese: "测试")
    vm.clearHistory()
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
}
```

- [ ] **Step 2: Run tests — verify FAIL**

```bash
xcodebuild test -project TranslatedCaption.xcodeproj -scheme TranslatedCaptionTests -destination 'platform=macOS'
```

Expected: FAIL — `addCaption` and `clearHistory` not found.

- [ ] **Step 3: Replace stub with full implementation**

```swift
// TranslatedCaption/ViewModels/CaptionViewModel.swift
import Foundation
import SwiftUI

@Observable
final class CaptionViewModel {
    var isRecording = false
    var currentEnglish = ""
    var currentChinese = ""
    var captionHistory: [CaptionEntry] = []
    var recentCaptions: [CaptionEntry] = []

    private let maxRecentCaptions = 3

    let translationService = TranslationService()

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
        Task { await audioCaptureService?.stop() }
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

                    await MainActor.run { self.currentEnglish = english }

                    let chinese = try await translation.translate(english)
                    await MainActor.run {
                        self.currentChinese = chinese
                        self.addCaption(english: english, chinese: chinese)
                    }
                } catch {
                    print("Pipeline error: \(error)")
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests — verify PASS**

```bash
xcodebuild test -project TranslatedCaption.xcodeproj -scheme TranslatedCaptionTests -destination 'platform=macOS'
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add TranslatedCaption/ViewModels/CaptionViewModel.swift TranslatedCaptionTests/CaptionViewModelTests.swift
git commit -m "feat: implement CaptionViewModel with pipeline coordination and tests"
```

---

### Task 10: Hotkey Manager

**Files:**
- Create: `TranslatedCaption/Utilities/HotkeyManager.swift`

- [ ] **Step 1: Implement HotkeyManager**

```swift
// TranslatedCaption/Utilities/HotkeyManager.swift
import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var monitor: Any?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd + Shift + T
            let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
            let hasFlags = event.modifierFlags.contains(requiredFlags)
            let isKeyT = event.keyCode == UInt16(kVK_ANSI_T)

            if hasFlags && isKeyT {
                self?.action()
            }
        }
    }

    func unregister() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        unregister()
    }
}
```

Key decisions:
- `addGlobalMonitorForEvents` — works when app is not frontmost
- Requires Accessibility permission (system will prompt user)
- `kVK_ANSI_T` (keyCode 17) — physical T key regardless of keyboard layout
- Weak self in closure to prevent retain cycle

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add TranslatedCaption/Utilities/HotkeyManager.swift
git commit -m "feat: add HotkeyManager for global Cmd+Shift+T shortcut"
```

---

### Task 11: App Entry Point — Wire Everything Together

**Files:**
- Modify: `TranslatedCaption/TranslatedCaptionApp.swift` (replace placeholder)

- [ ] **Step 1: Implement full app entry point with window management**

```swift
// TranslatedCaption/TranslatedCaptionApp.swift
import SwiftUI
import Translation

@main
struct TranslatedCaptionApp: App {
    @State private var viewModel = CaptionViewModel()
    @State private var floatingPanel: FloatingPanel?
    @State private var hotkeyManager: HotkeyManager?
    @State private var translationConfig: TranslationSession.Configuration?

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(viewModel)
                .translationTask(translationConfig) { session in
                    viewModel.setTranslationSession(session)
                }
                .onAppear {
                    translationConfig = viewModel.translationService.configuration
                    setupFloatingPanel()
                    setupHotkey()
                }
                .onDisappear { teardown() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 600, height: 500)
    }

    private func setupFloatingPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160)
        )

        // Use a single NSHostingView with environment — SwiftUI's
        // @Observable tracking handles reactive updates automatically
        let hostingView = NSHostingView(
            rootView: FloatingCaptionView()
                .environment(viewModel)
        )
        panel.contentView = hostingView

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 260
            let y = screenFrame.minY + 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        floatingPanel = panel
    }

    private func setupHotkey() {
        let manager = HotkeyManager { [viewModel] in
            Task { @MainActor in
                viewModel.toggleCapture()
            }
        }
        manager.register()
        hotkeyManager = manager
    }

    private func teardown() {
        hotkeyManager?.unregister()
        floatingPanel?.close()
        viewModel.stopCapture()
    }
}
```

Key decisions:
- `.translationTask` modifier provides `TranslationSession` to the ViewModel (required by Apple Translation framework)
- Floating panel uses a single `NSHostingView` with `.environment(viewModel)` — SwiftUI's `@Observable` tracking handles reactive updates automatically, no manual `withObservationTracking` needed
- Hotkey wired to `viewModel.toggleCapture()`
- Cleanup on `onDisappear`

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**

```bash
git add TranslatedCaption/TranslatedCaptionApp.swift
git commit -m "feat: wire app entry point with floating panel, hotkey, and pipeline"
```

---

### Task 12: Integration Smoke Test

- [ ] **Step 1: Run all unit tests**

```bash
xcodebuild test -project TranslatedCaption.xcodeproj -scheme TranslatedCaptionTests -destination 'platform=macOS'
```

Expected: All tests PASS.

- [ ] **Step 2: Launch the app manually**

```bash
xcodebuild -project TranslatedCaption.xcodeproj -scheme TranslatedCaption -destination 'platform=macOS' build
open build/Build/Products/Debug/TranslatedCaption.app
```

Or open `TranslatedCaption.xcodeproj` in Xcode and press Cmd+R.

Manual verification checklist:
- Main window appears with dark theme
- Floating subtitle panel appears at bottom of screen
- Record button toggles between "Start" and "Recording" states
- Cmd+Shift+T toggles recording from any app
- When recording during a Zoom call: English text appears, followed by Chinese translation
- Floating panel shows last 2-3 entries
- Main window shows full scrolling history with timestamps
- Floating panel is draggable and stays on top

- [ ] **Step 3: Fix any integration issues found**

Common issues to watch for:
- Screen Recording permission not granted → system prompt should appear
- WhisperKit model download on first launch → may take a minute
- Translation model download on first use → system handles this
- Accessibility permission for global hotkey → system prompt should appear

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: integration fixes from smoke test"
```

Only if changes were needed. Skip if everything passed.
