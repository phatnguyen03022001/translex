import AppKit
import Testing
@testable import TranslexApp

@Test @MainActor func noSelectionToastUsesCompactNoninteractivePanel() async throws {
    let popup = PopupController()
    popup.showToast("No text selected", anchor: NSPoint(x: 200, y: 200))
    let panel = try #require(NSApp.windows.first { $0.identifier?.rawValue == "TranslexPopup" && $0.isVisible && $0.frame.width <= 220 })
    #expect(panel.frame.width <= 220)
    #expect(panel.frame.height <= 52)
    #expect(panel.ignoresMouseEvents)
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    try await Task.sleep(for: .seconds(1.4))
    #expect(!panel.isVisible)
    popup.dismiss()
}

@Test @MainActor func translationFavoriteActionBecomesSavedWithoutDismissingPopup() throws {
    let popup = PopupController()
    var saved = false
    popup.show(
        source: "Hello",
        primary: "Xin chào",
        anchor: NSPoint(x: 200, y: 200),
        duration: 5,
        favoriteAction: { saved = true }
    )
    let panel = try #require(NSApp.windows.first { window in
        guard window.identifier?.rawValue == "TranslexPopup", window.isVisible else { return false }
        return findButton(in: window.contentView)?.isHidden == false
    })
    let button = try #require(findButton(in: panel.contentView))
    #expect(!panel.ignoresMouseEvents)
    #expect(button.title == "+")
    button.performClick(nil)
    #expect(saved)
    #expect(button.title == "✓")
    #expect(panel.isVisible)
    popup.dismiss()
}

@MainActor
private func findButton(in view: NSView?) -> NSButton? {
    guard let view else { return nil }
    if let button = view as? NSButton { return button }
    for child in view.subviews {
        if let button = findButton(in: child) { return button }
    }
    return nil
}
