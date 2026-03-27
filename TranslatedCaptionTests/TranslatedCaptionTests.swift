import Testing
import Foundation
@testable import TranslatedCaption

// MARK: - Integration Tests

/// End-to-end flow: add captions, verify history and recent, clear, verify empty
@Test @MainActor func fullCaptionFlowEndToEnd() {
    let vm = CaptionViewModel()

    // Add captions simulating a transcription session
    vm.addCaption(english: "Good morning everyone", chinese: "大家早上好")
    vm.addCaption(english: "Today we will discuss AI", chinese: "今天我们讨论人工智能")
    vm.addCaption(english: "Let's begin", chinese: "让我们开始吧")

    // History should have all 3
    #expect(vm.captionHistory.count == 3)
    // Recent should have all 3 (limit is 3)
    #expect(vm.recentCaptions.count == 3)

    // Add a 4th, recent should drop oldest
    vm.addCaption(english: "First topic", chinese: "第一个话题")
    #expect(vm.captionHistory.count == 4)
    #expect(vm.recentCaptions.count == 3)
    #expect(vm.recentCaptions[0].englishText == "Today we will discuss AI")
    #expect(vm.recentCaptions[2].englishText == "First topic")

    // Clear resets everything
    vm.clearHistory()
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
    #expect(vm.streamingEnglish.isEmpty)
    #expect(vm.streamingChinese.isEmpty)
}

/// Simulate streaming state transitions
@Test @MainActor func streamingStateTransitions() {
    let vm = CaptionViewModel()

    // Simulate streaming text arriving
    vm.streamingEnglish = "Hello"
    vm.streamingChinese = ""
    #expect(vm.streamingEnglish == "Hello")
    #expect(vm.streamingChinese.isEmpty)

    // Simulate translation arriving
    vm.streamingChinese = "你好"
    #expect(vm.streamingChinese == "你好")

    // Simulate moving to history
    vm.addCaption(english: vm.streamingEnglish, chinese: vm.streamingChinese)
    vm.streamingEnglish = ""
    vm.streamingChinese = ""
    #expect(vm.streamingEnglish.isEmpty)
    #expect(vm.captionHistory.count == 1)
    #expect(vm.captionHistory[0].englishText == "Hello")
    #expect(vm.captionHistory[0].chineseText == "你好")
}

/// Settings and ViewModel work together
@Test @MainActor func settingsIntegration() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "panelWidth")
    defaults.removeObject(forKey: "fontSize")
    defaults.removeObject(forKey: "selectedModelId")

    let settings = CaptionSettings()
    let vm = CaptionViewModel()

    // Default model should match settings
    #expect(settings.selectedModel.id == ASRModel.defaultModel.id)

    // ViewModel and settings are independent but consistent
    #expect(vm.isModelReady == false)
    #expect(settings.panelWidth == 620)
    #expect(settings.fontSize == 15)
}

/// Word timestamp storage in streaming
@Test @MainActor func wordTimestampStorage() {
    let vm = CaptionViewModel()

    let words = [
        WordTimestamp(word: "Hello", start: 0.0, end: 0.5, confidence: 0.95),
        WordTimestamp(word: "world", start: 0.5, end: 1.0, confidence: 0.88),
    ]
    vm.streamingWords = words
    #expect(vm.streamingWords.count == 2)
    #expect(vm.streamingWords[0].word == "Hello")
    #expect(vm.streamingWords[0].confidence == 0.95)
    #expect(vm.streamingWords[1].word == "world")

    // Clear should reset words
    vm.clearHistory()
    #expect(vm.streamingWords.isEmpty)
}

/// TranslationService refuses to translate without session
@Test func translationServiceRejectsWithoutSession() async {
    let service = TranslationService()
    do {
        _ = try await service.translate("test")
        Issue.record("Should have thrown")
    } catch let error as TranslationServiceError {
        #expect(error == .sessionNotReady)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}
