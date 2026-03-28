import Foundation

struct ASRModel: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String
    let speed: String
    let accuracy: String

    static let available: [ASRModel] = [
        ASRModel(
            id: "small-streaming-en",
            name: "Moonshine Small",
            size: "~157MB",
            speed: "~73ms",
            accuracy: "Good"
        ),
        ASRModel(
            id: "medium-streaming-en",
            name: "Moonshine Medium",
            size: "~303MB",
            speed: "~107ms",
            accuracy: "Great"
        ),
    ]

    static let defaultModel = available[1]
}

@MainActor
@Observable
final class CaptionSettings {
    var panelWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(panelWidth), forKey: "panelWidth") }
    }

    var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: "fontSize") }
    }

    var selectedModelId: String {
        didSet { UserDefaults.standard.set(selectedModelId, forKey: "selectedModelId") }
    }

    var selectedModel: ASRModel {
        ASRModel.available.first { $0.id == selectedModelId } ?? ASRModel.defaultModel
    }

    init() {
        let defaults = UserDefaults.standard
        let savedWidth = defaults.double(forKey: "panelWidth")
        panelWidth = savedWidth > 0 ? CGFloat(savedWidth) : 620

        let savedFontSize = defaults.double(forKey: "fontSize")
        fontSize = savedFontSize > 0 ? CGFloat(savedFontSize) : 15

        let savedModelId = defaults.string(forKey: "selectedModelId")
        // Migrate from WhisperKit model IDs to Moonshine default
        if let saved = savedModelId, ASRModel.available.contains(where: { $0.id == saved }) {
            selectedModelId = saved
        } else {
            selectedModelId = ASRModel.defaultModel.id
        }
    }
}
