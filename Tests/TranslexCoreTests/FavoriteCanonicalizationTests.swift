import Testing
@testable import TranslexCore

@Test func canonicalizationComposesUnicodeAndNormalizesWhitespace() {
    let decomposed = "  Ca\u{0301}i   Thie\u{0323}\u{0302}n!!!  "
    let value = FavoriteCanonicalizer.canonicalSource(decomposed, language: .vietnamese)
    #expect(value == "cái thiện")
    #expect(value == value.precomposedStringWithCanonicalMapping)
}

@Test func englishSingleWordUsesNativeLemmaWhenReliable() {
    #expect(FavoriteCanonicalizer.canonicalSource("Running", language: .english) == "run")
    #expect(FavoriteCanonicalizer.canonicalSource("studies", language: .english) == "study")
    #expect(FavoriteCanonicalizer.canonicalSource("went", language: .english) == "go")
}

@Test func englishLemmaFallsBackToNormalizedWord() {
    #expect(FavoriteCanonicalizer.canonicalSource("API", language: .english) == "api")
}

@Test func vietnameseLexicalCanonicalizationPreservesDiacritics() {
    #expect(FavoriteCanonicalizer.canonicalSource("  CẢI   THIỆN! ", language: .vietnamese) == "cải thiện")
}

@Test func phraseCanonicalizationPreservesSurfaceWordsWithoutTokenLemmatization() {
    #expect(FavoriteCanonicalizer.canonicalSource("  Running   studies!  ", language: .english) == "Running studies")
    #expect(FavoriteCanonicalizer.canonicalSource("  This   feature works. ", language: .english) == "This feature works")
}

@Test func normalizedFavoriteIdentityUsesCanonicalSource() {
    #expect(FavoriteCanonicalizer.normalizedIdentity("Running", language: .english) == "run")
    #expect(FavoriteCanonicalizer.normalizedIdentity("  CẢI THIỆN! ", language: .vietnamese) == "cải thiện")
}
