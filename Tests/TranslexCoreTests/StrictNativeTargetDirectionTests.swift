import Testing
@testable import TranslexCore

@Test func nativeVietnameseTargetsVietnameseForVietnameseDominantMixedText() {
    let cases = [
        "Tính năng này hoạt động very well.",
        "Tính năng này hoạt động very",
        "This feature hoạt động rất tốt."
    ]
    for text in cases {
        #expect(LanguageDirectionResolver.resolve(text, nativeLanguage: .vietnamese) == .init(source: .english, target: .vietnamese))
    }
}

@Test func nativeEnglishTargetsEnglishForAllConfirmedMixedText() {
    let cases = [
        "Tính năng này hoạt động very well.",
        "Tính năng này works really well.",
        "This feature hoạt động rất tốt.",
        "This API rất tiện và easy to use."
    ]
    for text in cases {
        #expect(LanguageDirectionResolver.resolve(text, nativeLanguage: .english) == .init(source: .vietnamese, target: .english))
    }
}

@Test func strictNativeTargetPolicyStillAllowsClearlyPureNativeText() {
    #expect(LanguageDirectionResolver.resolve("Tính năng này hoạt động rất tốt.", nativeLanguage: .vietnamese) == .init(source: .vietnamese, target: .english))
    #expect(LanguageDirectionResolver.resolve("This feature works really well.", nativeLanguage: .english) == .init(source: .english, target: .vietnamese))
}
