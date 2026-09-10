import Testing
@testable import TranslexCore

@Test func resolvesEnglishToVietnamese() {
    let direction = LanguageDirectionResolver.resolve("We need to improve the system.")
    #expect(direction == TranslationDirection(source: .english, target: .vietnamese))
}

@Test func resolvesVietnameseToEnglish() {
    let direction = LanguageDirectionResolver.resolve("Chúng ta cần cải thiện hệ thống.")
    #expect(direction == TranslationDirection(source: .vietnamese, target: .english))
}

@Test func normalizesLexicalIdentityWithoutDroppingVietnameseDiacritics() {
    #expect(LexicalNormalizer.normalize("  Cải   Thiện!  ") == "cải thiện")
    #expect(LexicalNormalizer.normalize("  IMPROVE  ") == "improve")
}

@Test func lexicalCandidateRejectsSentences() {
    #expect(LexicalClassifier.isCandidate("improve performance"))
    #expect(!LexicalClassifier.isCandidate("We need to improve the system because it is currently too slow."))
}
