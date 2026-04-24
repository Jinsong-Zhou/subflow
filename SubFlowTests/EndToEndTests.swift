import Testing
import Foundation
import AppKit
@testable import SubFlow

// MARK: - Caption Pipeline End-to-End Tests

/// YouTube-style flow: stream EN → complete → show EN+ZH → next sentence
@Test @MainActor func youtubeStyleCaptionFlow() {
    let vm = CaptionViewModel()

    // Phase 1: Streaming English (speaker talking)
    vm.streamingEnglish = "Hello everyone"
    vm.streamingChinese = ""
    #expect(vm.streamingEnglish == "Hello everyone")
    #expect(vm.streamingChinese.isEmpty)

    // Phase 2: Sentence completes → show EN+ZH pair
    vm.streamingEnglish = "Hello everyone"
    vm.streamingChinese = "大家好"
    #expect(vm.streamingChinese == "大家好")

    // Phase 3: Move to history, start next sentence
    vm.addCaption(english: "Hello everyone", chinese: "大家好")
    vm.streamingEnglish = "Welcome to SubFlow"
    vm.streamingChinese = ""
    #expect(vm.captionHistory.count == 1)
    #expect(vm.streamingEnglish == "Welcome to SubFlow")
    #expect(vm.streamingChinese.isEmpty)

    // Phase 4: Second sentence completes
    vm.streamingChinese = "欢迎使用 SubFlow"
    vm.addCaption(english: vm.streamingEnglish, chinese: vm.streamingChinese)
    vm.streamingEnglish = ""
    vm.streamingChinese = ""
    #expect(vm.captionHistory.count == 2)
    #expect(vm.recentCaptions.count == 2)
    #expect(vm.recentCaptions[1].englishText == "Welcome to SubFlow")
}

/// Long session with recentCaptions sliding window
@Test @MainActor func longSessionRecentCaptionSlidingWindow() {
    let vm = CaptionViewModel()

    let sentences = [
        ("Good morning", "早上好"),
        ("Let's start the meeting", "我们开始会议吧"),
        ("First agenda item", "第一个议程"),
        ("Any questions so far", "目前有什么问题吗"),
        ("See you next time", "下次见"),
    ]

    for (i, (en, zh)) in sentences.enumerated() {
        vm.addCaption(english: en, chinese: zh)
        #expect(vm.captionHistory.count == i + 1)
        #expect(vm.recentCaptions.count == min(i + 1, 2))
    }

    #expect(vm.captionHistory.count == 5)
    #expect(vm.recentCaptions.count == 2)
    #expect(vm.recentCaptions[1].englishText == "See you next time")
}

/// Streaming interrupted by fast speaker
@Test @MainActor func streamingInterruptedByNewText() {
    let vm = CaptionViewModel()

    vm.streamingEnglish = "Hello"
    vm.streamingEnglish = "Hello world"
    #expect(vm.streamingEnglish == "Hello world")

    vm.streamingChinese = "你好世界"
    vm.addCaption(english: vm.streamingEnglish, chinese: vm.streamingChinese)
    vm.streamingEnglish = ""
    vm.streamingChinese = ""

    #expect(vm.captionHistory.count == 1)
    #expect(vm.captionHistory[0].englishText == "Hello world")
}

// MARK: - Settings

@Test @MainActor func settingsRoundTripPersistence() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "panelWidth")
    defaults.removeObject(forKey: "fontSize")
    defaults.removeObject(forKey: "selectedModelId")

    let settings1 = CaptionSettings()
    settings1.panelWidth = 800
    settings1.fontSize = 20
    settings1.selectedModelId = "small-streaming-en"

    let settings2 = CaptionSettings()
    #expect(settings2.panelWidth == 800)
    #expect(settings2.fontSize == 20)

    defaults.removeObject(forKey: "panelWidth")
    defaults.removeObject(forKey: "fontSize")
    defaults.removeObject(forKey: "selectedModelId")
}

@Test @MainActor func settingsInvalidModelIdFallbackEndToEnd() {
    let defaults = UserDefaults.standard
    defaults.set("nonexistent-model-id", forKey: "selectedModelId")
    let settings = CaptionSettings()
    #expect(settings.selectedModelId == ASRModel.defaultModel.id)
    defaults.removeObject(forKey: "selectedModelId")
}

// MARK: - FloatingPanel

@Test @MainActor func floatingPanelResizeSimulation() {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 200))
    #expect(panel.frame.width == 620)
    panel.setFrame(
        NSRect(x: panel.frame.origin.x, y: panel.frame.origin.y, width: 800, height: panel.frame.height),
        display: false
    )
    #expect(panel.frame.width == 800)
}

@Test @MainActor func floatingPanelCenterPositioning() {
    guard let screen = NSScreen.main else { return }
    let width: CGFloat = 620
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 200))
    let screenFrame = screen.visibleFrame
    let x = screenFrame.midX - width / 2
    panel.setFrameOrigin(NSPoint(x: x, y: screenFrame.minY + 60))
    #expect(abs(panel.frame.midX - screenFrame.midX) < 1.0)
}

// MARK: - TranslationService

@Test func translationServiceLanguagePairEndToEnd() {
    let service = TranslationService()
    let config = service.configuration(target: .simplifiedChinese)
    #expect(config.source?.languageCode?.identifier == "en")
    #expect(config.target?.languageCode?.identifier == "zh")
    #expect(config.target?.script?.identifier == "Hans")
}

@Test func translationServiceMultipleRejectsWithoutSession() async {
    let service = TranslationService()
    for _ in 0..<5 {
        do {
            _ = try await service.translate("test")
            Issue.record("Should have thrown")
        } catch let error as TranslationServiceError {
            #expect(error == .sessionNotReady)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Edge Cases

@Test @MainActor func unicodeAndSpecialCharactersInCaptions() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Hello 👋 world 🌍", chinese: "你好 👋 世界 🌍")
    vm.addCaption(english: "café résumé naïve", chinese: "咖啡馆 简历 天真")
    #expect(vm.captionHistory.count == 2)
}

@Test @MainActor func veryLongCaptionText() {
    let vm = CaptionViewModel()
    let longEnglish = String(repeating: "This is a very long sentence. ", count: 100)
    let longChinese = String(repeating: "这是一个很长的句子。", count: 100)
    vm.addCaption(english: longEnglish, chinese: longChinese)
    #expect(vm.captionHistory.count == 1)
}

@Test @MainActor func alternatingAddAndClear() {
    let vm = CaptionViewModel()
    for cycle in 0..<10 {
        vm.addCaption(english: "Cycle \(cycle)", chinese: "周期 \(cycle)")
        #expect(vm.captionHistory.count == 1)
        vm.clearHistory()
        #expect(vm.captionHistory.isEmpty)
    }
}

@Test @MainActor func captionTimestampsAreMonotonic() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "First", chinese: "第一")
    Thread.sleep(forTimeInterval: 0.01)
    vm.addCaption(english: "Second", chinese: "第二")
    for i in 1..<vm.captionHistory.count {
        #expect(vm.captionHistory[i].timestamp >= vm.captionHistory[i - 1].timestamp)
    }
}

@Test @MainActor func captionIdsUniqueAcrossClearCycles() {
    let vm = CaptionViewModel()
    var allIds: Set<UUID> = []
    for i in 0..<5 { vm.addCaption(english: "C1-\(i)", chinese: "周期1-\(i)") }
    allIds.formUnion(vm.captionHistory.map(\.id))
    vm.clearHistory()
    for i in 0..<5 { vm.addCaption(english: "C2-\(i)", chinese: "周期2-\(i)") }
    allIds.formUnion(vm.captionHistory.map(\.id))
    #expect(allIds.count == 10)
}

@Test func asrModelConsistencyEndToEnd() {
    let models = ASRModel.available
    for model in models {
        #expect(!model.id.isEmpty)
        #expect(!model.name.isEmpty)
    }
    let defaultModel = ASRModel.defaultModel
    #expect(models.contains(where: { $0.id == defaultModel.id }))
    #expect(Set(models.map(\.id)).count == models.count)
}

@Test func appLoggerAppendDuringSession() {
    let marker = "E2E-\(UUID().uuidString)"
    AppLogger.log(marker)
    let content = (try? String(contentsOfFile: AppLogger.path, encoding: .utf8)) ?? ""
    #expect(content.contains(marker))
}

@Test @MainActor func hotkeyManagerLifecycle() {
    let manager = HotkeyManager { }
    manager.register()
    manager.unregister()
    manager.register()
    manager.unregister()
}
