import Testing
import Foundation
@testable import SubFlow

@Test func translationServiceThrowsWithoutSession() async {
    let service = TranslationService()
    do {
        _ = try await service.translate("Hello")
        Issue.record("Expected TranslationServiceError.sessionNotReady")
    } catch {
        #expect(error is TranslationServiceError)
        #expect(error.localizedDescription == "Translation session is not initialized")
    }
}

@Test func translationServiceConfigurationSimplifiedChinese() {
    let service = TranslationService()
    let config = service.configuration(target: .simplifiedChinese)
    #expect(config.source?.languageCode?.identifier == "en")
    #expect(config.target?.languageCode?.identifier == "zh")
    #expect(config.target?.script?.identifier == "Hans")
}

@Test func translationServiceConfigurationTraditionalChineseTaiwan() {
    let service = TranslationService()
    let config = service.configuration(target: .traditionalChineseTaiwan)
    #expect(config.source?.languageCode?.identifier == "en")
    #expect(config.target?.languageCode?.identifier == "zh")
    #expect(config.target?.script?.identifier == "Hant")
    #expect(config.target?.region?.identifier == "TW")
}
