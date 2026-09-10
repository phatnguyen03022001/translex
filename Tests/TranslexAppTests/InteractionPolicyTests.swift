import AppKit
import Testing
@testable import TranslexApp
import TranslexCore

@Test func selectionFeedbackUsesToastOnlyForMissingSelection() {
    #expect(SelectionFeedbackPolicy.kind(for: .noSelection) == .noSelectionToast)
    #expect(SelectionFeedbackPolicy.kind(for: .copyFailed) == .noSelectionToast)
    #expect(SelectionFeedbackPolicy.kind(for: .accessibilityRequired) == .accessibilityPermission)
}

@Test @MainActor func recorderMapsSupportedKeyAndModifiers() {
    let shortcut = ShortcutRecorderControl.definition(
        keyCode: 122,
        modifierFlags: [.control, .option]
    )
    #expect(shortcut == .init(keyCode: 122, modifiers: [.control, .option]))
    #expect(ShortcutRecorderControl.definition(keyCode: 127, modifierFlags: [.command]) == nil)
}

@Test func registrationErrorNamesActionAndAttemptedShortcut() {
    let attempted = ShortcutDefinition(keyCode: 17, modifiers: [.control, .option])
    let error = ShortcutRegistrationError.registrationFailed(.translate, attempted, -9876)
    #expect(error.localizedDescription.contains("Translate"))
    #expect(error.localizedDescription.contains("⌃⌥T"))
    #expect(error.localizedDescription.contains("unavailable"))
}

@Test @MainActor func recorderCapturesKeyDownIntoShortcutDefinition() throws {
    let recorder = ShortcutRecorderControl(shortcut: .init(keyCode: 18, modifiers: [.command]))
    let event = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.control, .option],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "t",
        charactersIgnoringModifiers: "t",
        isARepeat: false,
        keyCode: 17
    ))
    recorder.keyDown(with: event)
    #expect(recorder.shortcut == .init(keyCode: 17, modifiers: [.control, .option]))
}
