import AppKit
import Carbon
import TranslexCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var controller: AppController?
    private var shortcutManager: GlobalShortcutManager?
    private var settingsWindow: SettingsWindowController?
    private var favoritesWindow: FavoritesWindowController?
    private var shortcutIssue: String?
    private var activeTranslateShortcut: ShortcutDefinition?
    private var activeSpeakShortcut: ShortcutDefinition?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let controller = try AppController()
            let shortcuts = try GlobalShortcutManager()
            self.controller = controller
            self.shortcutManager = shortcuts
            try registerShortcuts(
                translate: controller.settings.translateShortcut,
                speak: controller.settings.speakShortcut
            )
        } catch {
            shortcutIssue = error.localizedDescription
        }
        buildStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutManager?.shutdown()
    }

    private func registerShortcuts(
        translate: ShortcutDefinition,
        speak: ShortcutDefinition
    ) throws {
        guard let shortcuts = shortcutManager, let controller else {
            throw ShortcutRegistrationError.eventHandlerInstallationFailed(OSStatus(eventNotHandledErr))
        }
        try shortcuts.register(
            translate: translate,
            speak: speak,
            onTranslate: { [weak controller] in controller?.translateSelection() },
            onSpeak: { [weak controller] in controller?.speakSelection() }
        )
        activeTranslateShortcut = translate
        activeSpeakShortcut = speak
        shortcutIssue = nil
        refreshMenu()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Translex")
            button.image?.isTemplate = true
            button.toolTip = "Translex"
        }
        statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let translateTitle = activeTranslateShortcut.map { "\(ShortcutFormatter.display($0)) — Translate Selection" }
            ?? "Translate Selection"
        let speakTitle = activeSpeakShortcut.map { "\(ShortcutFormatter.display($0)) — Speak Selection" }
            ?? "Speak Selection"
        menu.addItem(withTitle: translateTitle, action: #selector(translateSelection), keyEquivalent: "")
        menu.addItem(withTitle: speakTitle, action: #selector(speakSelection), keyEquivalent: "")
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: shortcutIssue == nil ? "character.bubble" : "exclamationmark.triangle",
                accessibilityDescription: "Translex"
            )
            button.image?.isTemplate = true
            button.toolTip = shortcutIssue.map { "Translex — \($0)" } ?? "Translex"
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Favorites…", action: #selector(openFavorites), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Translex", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }
        item.menu = menu
    }

    @objc private func translateSelection() {
        controller?.translateSelection()
    }

    @objc private func speakSelection() {
        controller?.speakSelection()
    }

    @objc private func openFavorites() {
        guard let controller else { return }
        if favoritesWindow == nil {
            favoritesWindow = FavoritesWindowController(database: controller.database)
        }
        favoritesWindow?.show()
    }

    @objc private func openSettings() {
        guard let controller else { return }
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: controller.settings,
                speech: controller.speech,
                selection: controller.selection,
                onApply: { [weak self] translate, speak in
                    try self?.applyShortcutChange(translate: translate, speak: speak)
                }
            )
        }
        settingsWindow?.show()
    }

    private func applyShortcutChange(
        translate: ShortcutDefinition,
        speak: ShortcutDefinition
    ) throws {
        guard let controller else {
            throw ShortcutRegistrationError.eventHandlerInstallationFailed(OSStatus(eventNotHandledErr))
        }
        let requested = ShortcutPair(translate: translate, speak: speak)
        let coordinator = ShortcutApplyCoordinator(
            current: { [weak self] in
                ShortcutPair(
                    translate: self?.activeTranslateShortcut ?? controller.settings.translateShortcut,
                    speak: self?.activeSpeakShortcut ?? controller.settings.speakShortcut
                )
            },
            register: { [weak self] pair in
                guard let self else {
                    throw ShortcutRegistrationError.eventHandlerInstallationFailed(OSStatus(eventNotHandledErr))
                }
                try self.registerShortcuts(translate: pair.translate, speak: pair.speak)
            },
            persist: { pair in
                try controller.settings.setTranslateShortcut(pair.translate)
                try controller.settings.setSpeakShortcut(pair.speak)
            },
            onRollbackFailure: { [weak self] error in
                self?.shortcutIssue = "Previous shortcuts could not be restored: \(error.localizedDescription)"
                self?.refreshMenu()
            }
        )
        try coordinator.apply(requested)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
