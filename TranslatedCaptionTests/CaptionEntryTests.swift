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
