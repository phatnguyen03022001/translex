import Foundation
import Testing
@testable import TranslexCore

@Test func nativeLanguageDefaultsToVietnameseAndPersistsEnglish() throws {
    let suite = "TranslexNativeLanguageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults)
    #expect(settings.nativeLanguage == .vietnamese)
    settings.nativeLanguage = .english
    #expect(SettingsStore(defaults: defaults).nativeLanguage == .english)
}

@Test func pureLanguageDirectionIgnoresNativePreference() {
    #expect(LanguageDirectionResolver.resolve("This feature works really well.", nativeLanguage: .vietnamese) == .init(source: .english, target: .vietnamese))
    #expect(LanguageDirectionResolver.resolve("Tính năng này hoạt động rất tốt.", nativeLanguage: .vietnamese) == .init(source: .vietnamese, target: .english))
    #expect(LanguageDirectionResolver.resolve("This feature works really well.", nativeLanguage: .english) == .init(source: .english, target: .vietnamese))
    #expect(LanguageDirectionResolver.resolve("Tính năng này hoạt động rất tốt.", nativeLanguage: .english) == .init(source: .vietnamese, target: .english))
}

@Test func mixedLanguagePrefersConfiguredNativeTarget() {
    let mixedA = "This API rất tiện và easy to use."
    let mixedB = "Tính năng này works really well."
    #expect(LanguageDirectionResolver.resolve(mixedA, nativeLanguage: .vietnamese) == .init(source: .english, target: .vietnamese))
    #expect(LanguageDirectionResolver.resolve(mixedB, nativeLanguage: .vietnamese) == .init(source: .english, target: .vietnamese))
    #expect(LanguageDirectionResolver.resolve(mixedA, nativeLanguage: .english) == .init(source: .vietnamese, target: .english))
    #expect(LanguageDirectionResolver.resolve(mixedB, nativeLanguage: .english) == .init(source: .vietnamese, target: .english))
}

@Test func ambiguousLanguagePrefersConfiguredNativeTarget() {
    #expect(LanguageDirectionResolver.resolve("API", nativeLanguage: .vietnamese) == .init(source: .english, target: .vietnamese))
    #expect(LanguageDirectionResolver.resolve("API", nativeLanguage: .english) == .init(source: .vietnamese, target: .english))
}
