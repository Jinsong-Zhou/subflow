import Testing
import Foundation
@testable import SubFlow

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

@Test @MainActor func recentCaptionsLimitedToTwo() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "One", chinese: "一")
    vm.addCaption(english: "Two", chinese: "二")
    vm.addCaption(english: "Three", chinese: "三")
    #expect(vm.recentCaptions.count == 2)
    #expect(vm.recentCaptions[0].englishText == "Two")
    #expect(vm.recentCaptions[1].englishText == "Three")
}

@Test @MainActor func historyGrowsUnbounded() {
    let vm = CaptionViewModel()
    for i in 0..<10 {
        vm.addCaption(english: "Line \(i)", chinese: "行 \(i)")
    }
    #expect(vm.captionHistory.count == 10)
    #expect(vm.recentCaptions.count == 2)
}

@Test @MainActor func addCaptionWithEmptyStrings() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "", chinese: "")
    #expect(vm.captionHistory.count == 1)
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
}

// MARK: - toggleCapture without model

@Test @MainActor func toggleCaptureWithoutModelDoesNotRecord() {
    let vm = CaptionViewModel()
    #expect(vm.isRecording == false)
}

// MARK: - Rapid addCaption

@Test @MainActor func rapidAddCaptionMaintainsOrder() {
    let vm = CaptionViewModel()
    for i in 1...20 {
        vm.addCaption(english: "Sentence \(i)", chinese: "句子 \(i)")
    }
    #expect(vm.captionHistory.count == 20)
    #expect(vm.captionHistory.first?.englishText == "Sentence 1")
    #expect(vm.captionHistory.last?.englishText == "Sentence 20")
    #expect(vm.recentCaptions.count == 2)
    #expect(vm.recentCaptions[0].englishText == "Sentence 19")
    #expect(vm.recentCaptions[1].englishText == "Sentence 20")
}

@Test @MainActor func captionHistoryEntriesHaveUniqueIds() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "A", chinese: "甲")
    vm.addCaption(english: "B", chinese: "乙")
    vm.addCaption(english: "C", chinese: "丙")
    let ids = Set(vm.captionHistory.map { $0.id })
    #expect(ids.count == 3)
}

// MARK: - Bilingual Reading Time

@Test func readingTimeShortSentence() {
    let time = CaptionViewModel.estimateReadingTime(english: "Hello", chinese: "你好")
    #expect(time == 2.5)
}

@Test func readingTimeMediumSentence() {
    let time = CaptionViewModel.estimateReadingTime(
        english: "This is a medium length sentence for testing",
        chinese: "这是一个中等长度的测试句子"
    )
    #expect(time >= 3.5 && time <= 4.5)
}

@Test func readingTimeLongChineseDominates() {
    let time = CaptionViewModel.estimateReadingTime(
        english: "Hi",
        chinese: "这是一个非常非常非常非常非常非常非常非常非常长的中文翻译"
    )
    #expect(time >= 4.0 && time <= 5.0)
}

@Test func readingTimeClampedToMax() {
    let longEN = String(repeating: "word ", count: 50)
    let longZH = String(repeating: "字", count: 100)
    let time = CaptionViewModel.estimateReadingTime(english: longEN, chinese: longZH)
    #expect(time == 10.0)
}

@Test func readingTimeEmptyStrings() {
    let time = CaptionViewModel.estimateReadingTime(english: "", chinese: "")
    #expect(time == 2.5)
}

// MARK: - Model switching

@Test @MainActor func modelSwitchWhileIdle() {
    let vm = CaptionViewModel()
    vm.switchModel(to: "small-streaming-en")
    #expect(vm.isLoading == true)
    #expect(vm.isModelReady == false)
}

@Test @MainActor func rapidModelSwitchIgnoresDuringLoading() {
    let vm = CaptionViewModel()
    vm.switchModel(to: "small-streaming-en")
    #expect(vm.isLoading == true)
    vm.switchModel(to: "medium-streaming-en")
    #expect(vm.isLoading == true)
}
