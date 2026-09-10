import Foundation
import Testing
@testable import TranslexCore

@Test func settingsPersistShortcutsAndPopupDuration() throws {
    let suite = "TranslexTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults)
    let translate = ShortcutDefinition(keyCode: 17, modifiers: [.control, .option])
    let speak = ShortcutDefinition(keyCode: 1, modifiers: [.control, .option])
    try store.setTranslateShortcut(translate)
    try store.setSpeakShortcut(speak)
    store.popupDuration = 6
    store.englishVoiceIdentifier = "com.apple.voice.test"
    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.translateShortcut == translate)
    #expect(reloaded.speakShortcut == speak)
    #expect(reloaded.popupDuration == 6)
    #expect(reloaded.englishVoiceIdentifier == "com.apple.voice.test")
}

@Test func rejectsShortcutWithoutPrimaryModifier() {
    #expect(throws: ShortcutValidationError.self) {
        try ShortcutValidator.validate(.init(keyCode: 17, modifiers: [.shift]))
    }
}
