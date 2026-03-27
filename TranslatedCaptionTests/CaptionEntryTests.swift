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

@Test func captionEntryStoresTimestamp() {
    let date = Date(timeIntervalSince1970: 1000)
    let entry = CaptionEntry(timestamp: date, englishText: "Test", chineseText: "测试")
    #expect(entry.timestamp == date)
}

@Test func captionEntryEmptyTexts() {
    let entry = CaptionEntry(timestamp: .now, englishText: "", chineseText: "")
    #expect(entry.englishText == "")
    #expect(entry.chineseText == "")
    #expect(entry.id != UUID()) // still has a valid unique id
}

@Test func captionEntryLongTexts() {
    let longEnglish = String(repeating: "word ", count: 500)
    let longChinese = String(repeating: "字", count: 500)
    let entry = CaptionEntry(timestamp: .now, englishText: longEnglish, chineseText: longChinese)
    #expect(entry.englishText == longEnglish)
    #expect(entry.chineseText == longChinese)
}
