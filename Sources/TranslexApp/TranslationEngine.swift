import Foundation
import Translation
import TranslexCore

struct TranslationResult: Sendable {
    let sourceText: String
    let translatedText: String
    let direction: TranslationDirection
}

enum TranslationEngineError: Error, LocalizedError {
    case undeterminedLanguage
    case unsupportedPair
    case downloadRequired
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .undeterminedLanguage:
            "Could not determine whether the selection is English or Vietnamese."
        case .unsupportedPair:
            "This English/Vietnamese translation pair is unavailable on this Mac."
        case .downloadRequired:
            "Translation language data is not installed. Install English and Vietnamese in System Settings > General > Language & Region > Translation Languages."
        case .translationFailed(let message):
            "Translation failed: \(message)"
        }
    }
}

struct AppleTranslationEngine {
    func translate(_ text: String) async throws -> TranslationResult {
        guard let direction = LanguageDirectionResolver.resolve(text) else {
            throw TranslationEngineError.undeterminedLanguage
        }
        let source = Locale.Language(identifier: direction.source.rawValue)
        let target = Locale.Language(identifier: direction.target.rawValue)
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)
        switch await availability.status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw TranslationEngineError.downloadRequired
        case .unsupported:
            throw TranslationEngineError.unsupportedPair
        @unknown default:
            throw TranslationEngineError.unsupportedPair
        }
        do {
            let session = TranslationSession(
                installedSource: source,
                target: target,
                preferredStrategy: .lowLatency
            )
            defer { session.cancel() }
            let response = try await session.translate(text)
            return .init(
                sourceText: text,
                translatedText: response.targetText,
                direction: direction
            )
        } catch let error as TranslationEngineError {
            throw error
        } catch {
            throw TranslationEngineError.translationFailed(error.localizedDescription)
        }
    }
}
