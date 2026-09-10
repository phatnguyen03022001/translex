import AppKit
import TranslexCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private let speech: SpeechService
    private let selection: SelectionProvider
    private let onApply: (ShortcutDefinition, ShortcutDefinition) throws -> Void

    private let translateRecorder: ShortcutRecorderControl
    private let speakRecorder: ShortcutRecorderControl
    private let voice = NSPopUpButton()
    private let duration = NSSlider(value: 4, minValue: 2, maxValue: 15, target: nil, action: nil)
    private let durationLabel = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(labelWithString: "")

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
        self.translateRecorder = ShortcutRecorderControl(shortcut: settings.translateShortcut)
        self.speakRecorder = ShortcutRecorderControl(shortcut: settings.speakShortcut)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
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
            [NSTextField(labelWithString: "Translate shortcut"), translateRecorder],
            [NSTextField(labelWithString: "Speak shortcut"), speakRecorder],
            [NSTextField(labelWithString: "English voice"), voice],
            [NSTextField(labelWithString: "Popup duration"), durationRow],
            [NSTextField(labelWithString: "Accessibility"), accessRow]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let note = NSTextField(wrappingLabelWithString: "Global shortcuts may override the same shortcut in other apps while Translex is running.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [NSView(), applyButton])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(note)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            note.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
    }

    private func loadValues() {
        translateRecorder.shortcut = settings.translateShortcut
        speakRecorder.shortcut = settings.speakShortcut
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
        let translate = translateRecorder.shortcut
        let speak = speakRecorder.shortcut
        do {
            try ShortcutValidator.validatePair(translate: translate, speak: speak)
            try onApply(translate, speak)
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
