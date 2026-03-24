import Foundation

struct CaptionEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let englishText: String
    let chineseText: String
}
