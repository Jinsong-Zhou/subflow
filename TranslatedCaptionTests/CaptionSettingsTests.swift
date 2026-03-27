import Testing
import Foundation
@testable import TranslatedCaption

// MARK: - ASRModel

@Test func asrModelAvailableIsNotEmpty() {
    #expect(!ASRModel.available.isEmpty)
}

@Test func asrModelDefaultModelExistsInAvailable() {
    let defaultModel = ASRModel.defaultModel
    let found = ASRModel.available.contains { $0.id == defaultModel.id }
    #expect(found)
}

@Test func asrModelHasUniqueIds() {
    let ids = ASRModel.available.map { $0.id }
    #expect(Set(ids).count == ids.count)
}

@Test func asrModelDefaultIsMedium() {
    #expect(ASRModel.defaultModel.id == "medium-streaming-en")
}

// MARK: - CaptionSettings

@Test @MainActor func captionSettingsDefaultValues() {
    // Clear stored values to test defaults
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "panelWidth")
    defaults.removeObject(forKey: "fontSize")
    defaults.removeObject(forKey: "selectedModelId")

    let settings = CaptionSettings()
    #expect(settings.panelWidth == 620)
    #expect(settings.fontSize == 15)
    #expect(settings.selectedModelId == ASRModel.defaultModel.id)
}

@Test @MainActor func captionSettingsSelectedModelProperty() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "selectedModelId")

    let settings = CaptionSettings()
    #expect(settings.selectedModel.id == ASRModel.defaultModel.id)
    #expect(settings.selectedModel.name == ASRModel.defaultModel.name)
}

@Test @MainActor func captionSettingsPersistsPanelWidth() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "panelWidth")

    let settings = CaptionSettings()
    settings.panelWidth = 800
    #expect(defaults.double(forKey: "panelWidth") == 800)
}

@Test @MainActor func captionSettingsPersistsFontSize() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "fontSize")

    let settings = CaptionSettings()
    settings.fontSize = 20
    #expect(defaults.double(forKey: "fontSize") == 20)
}

@Test @MainActor func captionSettingsPersistsModelId() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "selectedModelId")

    let settings = CaptionSettings()
    settings.selectedModelId = "small-streaming-en"
    #expect(defaults.string(forKey: "selectedModelId") == "small-streaming-en")
}

@Test @MainActor func captionSettingsInvalidModelIdFallsBackToDefault() {
    let defaults = UserDefaults.standard
    defaults.set("nonexistent-model", forKey: "selectedModelId")

    let settings = CaptionSettings()
    // Should fall back to default because "nonexistent-model" is not in available list
    #expect(settings.selectedModelId == ASRModel.defaultModel.id)
}

@Test @MainActor func captionSettingsSelectedModelFallbackForInvalidId() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "selectedModelId")

    let settings = CaptionSettings()
    // Manually set an invalid id after init
    settings.selectedModelId = "invalid-model"
    // selectedModel should fall back to default
    #expect(settings.selectedModel.id == ASRModel.defaultModel.id)
}

@Test @MainActor func captionSettingsLoadsPersistedPanelWidth() {
    let defaults = UserDefaults.standard
    defaults.set(750.0, forKey: "panelWidth")

    let settings = CaptionSettings()
    #expect(settings.panelWidth == 750)

    // Cleanup
    defaults.removeObject(forKey: "panelWidth")
}

@Test @MainActor func captionSettingsLoadsPersistedFontSize() {
    let defaults = UserDefaults.standard
    defaults.set(18.0, forKey: "fontSize")

    let settings = CaptionSettings()
    #expect(settings.fontSize == 18)

    // Cleanup
    defaults.removeObject(forKey: "fontSize")
}
