import AppKit
@preconcurrency import ApplicationServices

struct SelectedText {
    let text: String
    let anchor: NSPoint
}

enum SelectionError: Error, LocalizedError {
    case accessibilityRequired
    case noSelection
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: "Accessibility permission is required to read the current selection."
        case .noSelection: "No selectable text is currently selected."
        case .copyFailed: "The current app did not expose or copy its selected text."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accessibilityRequired:
            "Translex needs Accessibility only to read selected text and trigger its bounded clipboard fallback."
        case .noSelection, .copyFailed:
            nil
        }
    }
}

final class SelectionProvider {
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func selectedText() throws -> SelectedText {
        guard AXIsProcessTrusted() else { throw SelectionError.accessibilityRequired }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw SelectionError.noSelection }
        if let text = accessibilitySelection(pid: app.processIdentifier) {
            return .init(text: text, anchor: NSEvent.mouseLocation)
        }
        if let text = clipboardSelection(pid: app.processIdentifier) {
            return .init(text: text, anchor: NSEvent.mouseLocation)
        }
        throw SelectionError.copyFailed
    }

    private func accessibilitySelection(pid: pid_t) -> String? {
        let application = AXUIElementCreateApplication(pid)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focusedValue else { return nil }
        let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &selectedValue
        ) == .success else { return nil }
        guard let text = selectedValue as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    private struct SnapshotItem {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    private func clipboardSelection(pid: pid_t) -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let before = pasteboard.changeCount
        pasteboard.clearContents()
        let cleared = pasteboard.changeCount
        postCopy(to: pid)

        var copied: String?
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.03)
            if pasteboard.changeCount != cleared {
                copied = pasteboard.string(forType: .string)
                break
            }
        }

        let afterCopy = pasteboard.changeCount
        if afterCopy == cleared || afterCopy == before {
            restore(snapshot, to: pasteboard)
            return nil
        }
        restore(snapshot, to: pasteboard)
        guard let copied else { return nil }
        let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : copied
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [SnapshotItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            SnapshotItem(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private func restore(_ snapshot: [SnapshotItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { snapshotItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshotItem.values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private func postCopy(to pid: pid_t) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
    }
}
