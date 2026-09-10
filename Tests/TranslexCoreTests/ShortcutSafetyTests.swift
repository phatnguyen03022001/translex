import Testing
@testable import TranslexCore

@Test func obviousSystemShortcutsAreReservedButCommandNumbersAreAllowed() {
    #expect(ShortcutReservedPolicy.isReserved(.init(keyCode: 49, modifiers: [.command])))
    #expect(ShortcutReservedPolicy.isReserved(.init(keyCode: 48, modifiers: [.command])))
    #expect(ShortcutReservedPolicy.isReserved(.init(keyCode: 53, modifiers: [.command, .option])))
    #expect(!ShortcutReservedPolicy.isReserved(.init(keyCode: 18, modifiers: [.command])))
    #expect(!ShortcutReservedPolicy.isReserved(.init(keyCode: 19, modifiers: [.command])))
    #expect(throws: ShortcutValidationError.self) {
        try ShortcutValidator.validate(.init(keyCode: 49, modifiers: [.command]))
    }
    #expect(throws: Never.self) {
        try ShortcutValidator.validate(.init(keyCode: 18, modifiers: [.command]))
    }
}

@Test func supportedRecorderKeysIncludeLettersNumbersFunctionAndNavigationKeys() {
    #expect(ShortcutKeyCatalog.isSupported(0))
    #expect(ShortcutKeyCatalog.isSupported(18))
    #expect(ShortcutKeyCatalog.isSupported(122))
    #expect(ShortcutKeyCatalog.isSupported(123))
    #expect(!ShortcutKeyCatalog.isSupported(127))
}

@Test func formatterDisplaysFunctionAndNavigationKeys() {
    #expect(ShortcutFormatter.display(.init(keyCode: 122, modifiers: [.control, .option])) == "⌃⌥F1")
    #expect(ShortcutFormatter.display(.init(keyCode: 123, modifiers: [.command, .shift])) == "⇧⌘←")
}
