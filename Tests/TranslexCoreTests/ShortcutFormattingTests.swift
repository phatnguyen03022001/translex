import Testing
@testable import TranslexCore

@Test func formatsPersistedShortcut() {
    let shortcut = ShortcutDefinition(keyCode: 17, modifiers: [.control, .option])
    #expect(ShortcutFormatter.display(shortcut) == "⌃⌥T")
}

@Test func rejectsDuplicateActionShortcuts() {
    let shortcut = ShortcutDefinition(keyCode: 17, modifiers: [.control, .option])
    #expect(throws: ShortcutValidationError.self) {
        try ShortcutValidator.validatePair(translate: shortcut, speak: shortcut)
    }
}
