import Foundation
import Testing
@testable import TranslexApp
import TranslexCore

private enum ProbeError: Error { case unavailable }

@Test @MainActor func failedRegistrationRestoresPreviousPairAndDoesNotPersist() throws {
    let previous = ShortcutPair(
        translate: .init(keyCode: 18, modifiers: [.command]),
        speak: .init(keyCode: 19, modifiers: [.command])
    )
    let attempted = ShortcutPair(
        translate: .init(keyCode: 17, modifiers: [.control, .option]),
        speak: .init(keyCode: 1, modifiers: [.control, .option])
    )
    let suite = "TranslexShortcutRollbackTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults)
    try settings.setTranslateShortcut(previous.translate)
    try settings.setSpeakShortcut(previous.speak)
    var registrations: [ShortcutPair] = []
    let coordinator = ShortcutApplyCoordinator(
        current: { previous },
        register: { pair in
            registrations.append(pair)
            if pair == attempted { throw ProbeError.unavailable }
        },
        persist: { pair in
            try settings.setTranslateShortcut(pair.translate)
            try settings.setSpeakShortcut(pair.speak)
        }
    )

    #expect(throws: ProbeError.self) { try coordinator.apply(attempted) }
    let reloaded = SettingsStore(defaults: defaults)
    #expect(registrations == [attempted, previous])
    #expect(reloaded.translateShortcut == previous.translate)
    #expect(reloaded.speakShortcut == previous.speak)
}

@Test @MainActor func successfulCustomShortcutRegistrationPersists() throws {
    let previous = ShortcutPair(
        translate: .init(keyCode: 18, modifiers: [.command]),
        speak: .init(keyCode: 19, modifiers: [.command])
    )
    let custom = ShortcutPair(
        translate: .init(keyCode: 17, modifiers: [.control, .option]),
        speak: .init(keyCode: 1, modifiers: [.control, .option])
    )
    let suite = "TranslexShortcutApplyTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults)
    var registered: ShortcutPair?
    let coordinator = ShortcutApplyCoordinator(
        current: { previous },
        register: { registered = $0 },
        persist: { pair in
            try settings.setTranslateShortcut(pair.translate)
            try settings.setSpeakShortcut(pair.speak)
        }
    )

    try coordinator.apply(custom)
    let reloaded = SettingsStore(defaults: defaults)
    #expect(registered == custom)
    #expect(reloaded.translateShortcut == custom.translate)
    #expect(reloaded.speakShortcut == custom.speak)
}
