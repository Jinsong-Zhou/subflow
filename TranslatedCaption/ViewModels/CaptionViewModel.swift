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
