import Testing
import Foundation
@testable import TranslatedCaption

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

@Test func translationServiceConfigurationIsEnglishToChinese() {
    let service = TranslationService()
    let config = service.configuration
    #expect(config.source?.languageCode?.identifier == "en")
    #expect(config.target?.languageCode?.identifier == "zh")
    #expect(config.target?.script?.identifier == "Hans")
}
