import AppKit
import Foundation
import Testing
@testable import TranslexApp
import TranslexCore

@Test @MainActor func settingsExposeAndPersistNativeLanguage() throws {
    let suite = "TranslexNativeSettingsUI.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults)
    let controller = SettingsWindowController(
        settings: settings,
        speech: SpeechService(),
        selection: SelectionProvider(),
        onApply: { _, _ in }
    )
    let popup = try #require(findNativeLanguagePopup(in: controller.window?.contentView))
    #expect(popup.itemTitles == ["Vietnamese", "English"])
    popup.selectItem(withTitle: "English")
    let apply = try #require(findButton(title: "Apply", in: controller.window?.contentView))
    apply.performClick(nil)
    #expect(settings.nativeLanguage == .english)
}

@MainActor private func findNativeLanguagePopup(in view: NSView?) -> NSPopUpButton? {
    guard let view else { return nil }
    if let popup = view as? NSPopUpButton, Set(popup.itemTitles) == Set(["Vietnamese", "English"]) {
        return popup
    }
    for child in view.subviews {
        if let found = findNativeLanguagePopup(in: child) { return found }
    }
    return nil
}

@MainActor private func findButton(title: String, in view: NSView?) -> NSButton? {
    guard let view else { return nil }
    if let button = view as? NSButton, button.title == title { return button }
    for child in view.subviews {
        if let found = findButton(title: title, in: child) { return found }
    }
    return nil
}
