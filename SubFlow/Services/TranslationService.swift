import Translation

final class TranslationService: @unchecked Sendable {
    private var session: TranslationSession?

    func configuration(target: TranslationTarget) -> TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: .init(identifier: "en"),
            target: .init(identifier: target.rawValue)
        )
    }

    func setSession(_ session: TranslationSession) {
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        guard let session else {
            throw TranslationServiceError.sessionNotReady
        }
        let response = try await session.translate(text)
        return response.targetText
    }
}

enum TranslationServiceError: Error, LocalizedError {
    case sessionNotReady

    var errorDescription: String? {
        switch self {
        case .sessionNotReady:
            return "Translation session is not initialized"
        }
    }
}
