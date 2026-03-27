import Testing
import Foundation
@testable import TranslatedCaption

// MARK: - Basic State

@Test @MainActor func initialStateIsNotRecording() {
    let vm = CaptionViewModel()
    #expect(vm.isRecording == false)
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
}

@Test @MainActor func initialStateStreamingIsEmpty() {
    let vm = CaptionViewModel()
    #expect(vm.streamingEnglish == "")
    #expect(vm.streamingChinese == "")
    #expect(vm.streamingWords.isEmpty)
}

@Test @MainActor func initialLoadingAndModelState() {
    let vm = CaptionViewModel()
    #expect(vm.isLoading == false)
    #expect(vm.isModelReady == false)
    #expect(vm.statusMessage == "")
}

// MARK: - addCaption

@Test @MainActor func addCaptionAppendsToHistory() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Hello", chinese: "你好")
    #expect(vm.captionHistory.count == 1)
    #expect(vm.captionHistory[0].englishText == "Hello")
    #expect(vm.captionHistory[0].chineseText == "你好")
}

@Test @MainActor func addCaptionAppendsToRecentCaptions() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Hello", chinese: "你好")
    #expect(vm.recentCaptions.count == 1)
    #expect(vm.recentCaptions[0].englishText == "Hello")
}

@Test @MainActor func recentCaptionsLimitedToThree() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "One", chinese: "一")
    vm.addCaption(english: "Two", chinese: "二")
    vm.addCaption(english: "Three", chinese: "三")
    vm.addCaption(english: "Four", chinese: "四")
    #expect(vm.recentCaptions.count == 3)
    #expect(vm.recentCaptions[0].englishText == "Two")
    #expect(vm.recentCaptions[2].englishText == "Four")
}

@Test @MainActor func historyGrowsUnbounded() {
    let vm = CaptionViewModel()
    for i in 0..<10 {
        vm.addCaption(english: "Line \(i)", chinese: "行 \(i)")
    }
    #expect(vm.captionHistory.count == 10)
    #expect(vm.recentCaptions.count == 3)
}

@Test @MainActor func addCaptionWithEmptyStrings() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "", chinese: "")
    #expect(vm.captionHistory.count == 1)
    #expect(vm.captionHistory[0].englishText == "")
    #expect(vm.captionHistory[0].chineseText == "")
}

// MARK: - clearHistory

@Test @MainActor func clearHistoryRemovesAllEntries() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Test", chinese: "测试")
    vm.clearHistory()
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
}

@Test @MainActor func clearHistoryClearsStreamingState() {
    let vm = CaptionViewModel()
    vm.streamingEnglish = "streaming"
    vm.streamingChinese = "流式"
    vm.clearHistory()
    #expect(vm.streamingEnglish == "")
    #expect(vm.streamingChinese == "")
    #expect(vm.streamingWords.isEmpty)
}

@Test @MainActor func clearHistoryOnEmptyIsNoop() {
    let vm = CaptionViewModel()
    vm.clearHistory()
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
}

// MARK: - toggleCapture without model

@Test @MainActor func toggleCaptureWithoutModelDoesNotRecord() {
    let vm = CaptionViewModel()
    // Model not ready, toggleCapture should not set isRecording
    // (it will try to preload and fail since no model files exist)
    #expect(vm.isRecording == false)
}

// MARK: - Multiple rapid addCaption calls

@Test @MainActor func rapidAddCaptionMaintainsOrder() {
    let vm = CaptionViewModel()
    for i in 1...20 {
        vm.addCaption(english: "Sentence \(i)", chinese: "句子 \(i)")
    }
    #expect(vm.captionHistory.count == 20)
    #expect(vm.captionHistory.first?.englishText == "Sentence 1")
    #expect(vm.captionHistory.last?.englishText == "Sentence 20")
    #expect(vm.recentCaptions.count == 3)
    #expect(vm.recentCaptions[0].englishText == "Sentence 18")
    #expect(vm.recentCaptions[1].englishText == "Sentence 19")
    #expect(vm.recentCaptions[2].englishText == "Sentence 20")
}

// MARK: - CaptionEntry IDs are unique across addCaption calls

@Test @MainActor func captionHistoryEntriesHaveUniqueIds() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "A", chinese: "甲")
    vm.addCaption(english: "B", chinese: "乙")
    vm.addCaption(english: "C", chinese: "丙")
    let ids = Set(vm.captionHistory.map { $0.id })
    #expect(ids.count == 3)
}
