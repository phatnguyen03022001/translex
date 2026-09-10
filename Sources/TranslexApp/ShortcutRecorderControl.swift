import AppKit
import TranslexCore

@MainActor
final class ShortcutRecorderControl: NSControl {
    var shortcut: ShortcutDefinition {
        didSet { needsDisplay = true }
    }
    var onChange: ((ShortcutDefinition) -> Void)?
    private var isRecording = false

    init(shortcut: ShortcutDefinition) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        focusRingType = .none
        setAccessibilityRole(.button)
        setAccessibilityLabel("Shortcut recorder")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 30) }

    override func mouseDown(with event: NSEvent) {
        _ = window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        let relevant = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53 && relevant.isEmpty {
            isRecording = false
            _ = window?.makeFirstResponder(nil)
            needsDisplay = true
            return
        }
        guard let value = Self.definition(keyCode: UInt32(event.keyCode), modifierFlags: relevant) else { return }
        shortcut = value
        isRecording = false
        onChange?(value)
        _ = window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.selectedControlColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Press shortcut…" : ShortcutFormatter.display(shortcut)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        text.draw(at: point, withAttributes: attributes)
    }

    static func definition(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) -> ShortcutDefinition? {
        guard ShortcutKeyCatalog.isSupported(keyCode) else { return nil }
        var modifiers: ShortcutModifiers = []
        if modifierFlags.contains(.command) { modifiers.insert(.command) }
        if modifierFlags.contains(.option) { modifiers.insert(.option) }
        if modifierFlags.contains(.control) { modifiers.insert(.control) }
        if modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        return .init(keyCode: keyCode, modifiers: modifiers)
    }
}
