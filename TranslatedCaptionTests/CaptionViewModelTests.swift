import Testing
import Foundation
@testable import TranslatedCaption

@Test @MainActor func initialStateIsNotRecording() {
    let vm = CaptionViewModel()
    #expect(vm.isRecording == false)
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
}

@Test @MainActor func addCaptionAppendsToHistory() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Hello", chinese: "你好")
    #expect(vm.captionHistory.count == 1)
    #expect(vm.captionHistory[0].englishText == "Hello")
    #expect(vm.captionHistory[0].chineseText == "你好")
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

@Test @MainActor func clearHistoryRemovesAllEntries() {
    let vm = CaptionViewModel()
    vm.addCaption(english: "Test", chinese: "测试")
    vm.clearHistory()
    #expect(vm.captionHistory.isEmpty)
    #expect(vm.recentCaptions.isEmpty)
}
