import Testing
@testable import TranslexCore

@Test func formatsCommandNumberShortcuts() {
    let translate = ShortcutDefinition(keyCode: 18, modifiers: [.command])
    let speak = ShortcutDefinition(keyCode: 19, modifiers: [.command])
    #expect(ShortcutFormatter.display(translate) == "⌘1")
    #expect(ShortcutFormatter.display(speak) == "⌘2")
}

@Test func rejectsDuplicateActionShortcuts() {
    let shortcut = ShortcutDefinition(keyCode: 18, modifiers: [.command])
    #expect(throws: ShortcutValidationError.self) {
        try ShortcutValidator.validatePair(translate: shortcut, speak: shortcut)
    }
}
