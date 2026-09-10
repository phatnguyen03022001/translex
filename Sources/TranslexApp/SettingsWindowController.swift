import AppKit
import TranslexCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private let speech: SpeechService
    private let selection: SelectionProvider
    private let onApply: (ShortcutDefinition, ShortcutDefinition) throws -> Void

    private let translateModifiers = NSPopUpButton()
    private let translateKey = NSPopUpButton()
    private let speakModifiers = NSPopUpButton()
    private let speakKey = NSPopUpButton()
    private let voice = NSPopUpButton()
    private let duration = NSSlider(value: 4, minValue: 2, maxValue: 15, target: nil, action: nil)
    private let durationLabel = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(labelWithString: "")

    private let modifierOptions: [(String, ShortcutModifiers)] = [
        ("⌃⌥", [.control, .option]),
        ("⌘⌥", [.command, .option]),
        ("⌃⌘", [.control, .command]),
        ("⌃⌥⇧", [.control, .option, .shift]),
        ("⌘⌥⇧", [.command, .option, .shift])
    ]

    private let keyOptions: [(String, UInt32)] = [
        ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5),
        ("Z", 6), ("X", 7), ("C", 8), ("V", 9), ("B", 11), ("Q", 12),
        ("W", 13), ("E", 14), ("R", 15), ("Y", 16), ("T", 17), ("O", 31),
        ("U", 32), ("I", 34), ("P", 35), ("L", 37), ("J", 38), ("K", 40),
        ("N", 45), ("M", 46)
    ]

    init(
        settings: SettingsStore,
        speech: SpeechService,
        selection: SelectionProvider,
        onApply: @escaping (ShortcutDefinition, ShortcutDefinition) throws -> Void
    ) {
        self.settings = settings
        self.speech = speech
        self.selection = selection
        self.onApply = onApply
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Translex Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let translateRow = shortcutRow(modifiers: translateModifiers, key: translateKey)
        let speakRow = shortcutRow(modifiers: speakModifiers, key: speakKey)
        duration.target = self
        duration.action = #selector(durationChanged)
        duration.isContinuous = false

        let requestButton = NSButton(title: "Request Accessibility…", target: self, action: #selector(requestAccessibility))
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applySettings))
        applyButton.keyEquivalent = "\r"

        let durationRow = NSStackView(views: [duration, durationLabel])
        durationRow.orientation = .horizontal
        durationRow.spacing = 10

        let accessRow = NSStackView(views: [accessibilityStatus, requestButton])
        accessRow.orientation = .horizontal
        accessRow.spacing = 10

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Translate shortcut"), translateRow],
            [NSTextField(labelWithString: "Speak shortcut"), speakRow],
            [NSTextField(labelWithString: "English voice"), voice],
            [NSTextField(labelWithString: "Popup duration"), durationRow],
            [NSTextField(labelWithString: "Accessibility"), accessRow]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [NSView(), applyButton])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
    }

    private func shortcutRow(modifiers: NSPopUpButton, key: NSPopUpButton) -> NSView {
        modifierOptions.forEach { modifiers.addItem(withTitle: $0.0) }
        keyOptions.forEach { key.addItem(withTitle: $0.0) }
        let stack = NSStackView(views: [modifiers, key])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func loadValues() {
        select(settings.translateShortcut, modifiers: translateModifiers, key: translateKey)
        select(settings.speakShortcut, modifiers: speakModifiers, key: speakKey)
        duration.doubleValue = settings.popupDuration
        durationChanged()
        voice.removeAllItems()
        let voices = speech.availableEnglishVoices
        voices.forEach { voice.addItem(withTitle: "\($0.name) — \($0.language)") }
        if let resolved = speech.resolvedVoice(preferredIdentifier: settings.englishVoiceIdentifier),
           let index = voices.firstIndex(where: { $0.identifier == resolved.identifier }) {
            voice.selectItem(at: index)
        }
        refreshAccessibility()
    }

    private func select(
        _ shortcut: ShortcutDefinition,
        modifiers: NSPopUpButton,
        key: NSPopUpButton
    ) {
        if let index = modifierOptions.firstIndex(where: { $0.1 == shortcut.modifiers }) {
            modifiers.selectItem(at: index)
        }
        if let index = keyOptions.firstIndex(where: { $0.1 == shortcut.keyCode }) {
            key.selectItem(at: index)
        }
    }

    private func definition(modifiers: NSPopUpButton, key: NSPopUpButton) -> ShortcutDefinition {
        let modifierIndex = max(0, modifiers.indexOfSelectedItem)
        let keyIndex = max(0, key.indexOfSelectedItem)
        return .init(
            keyCode: keyOptions[keyIndex].1,
            modifiers: modifierOptions[modifierIndex].1
        )
    }

    @objc private func durationChanged() {
        durationLabel.stringValue = String(format: "%.0f s", duration.doubleValue)
    }

    @objc private func requestAccessibility() {
        _ = selection.requestAccessibilityPermission()
        refreshAccessibility()
    }

    private func refreshAccessibility() {
        accessibilityStatus.stringValue = selection.isAccessibilityTrusted ? "Granted" : "Not granted"
        accessibilityStatus.textColor = selection.isAccessibilityTrusted ? .labelColor : .secondaryLabelColor
    }

    @objc private func applySettings() {
        let translate = definition(modifiers: translateModifiers, key: translateKey)
        let speak = definition(modifiers: speakModifiers, key: speakKey)
        do {
            try ShortcutValidator.validatePair(translate: translate, speak: speak)
            try onApply(translate, speak)
            try settings.setTranslateShortcut(translate)
            try settings.setSpeakShortcut(speak)
            settings.popupDuration = duration.doubleValue
            let voices = speech.availableEnglishVoices
            let selectedIndex = voice.indexOfSelectedItem
            settings.englishVoiceIdentifier = voices.indices.contains(selectedIndex)
                ? voices[selectedIndex].identifier
                : nil
            window?.close()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not apply settings"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func show() {
        loadValues()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
