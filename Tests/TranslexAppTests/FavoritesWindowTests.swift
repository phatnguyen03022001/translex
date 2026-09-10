import AppKit
import Foundation
import Testing
@testable import TranslexApp
import TranslexCore

@Test @MainActor func favoritesWindowLoadsSavedTranslations() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try DatabaseStore(path: dir.appendingPathComponent("favorites.sqlite3").path)
    _ = try store.saveFavorite(sourceText: "Hello", sourceLanguage: .english, translatedText: "Xin chào")
    _ = try store.saveFavorite(sourceText: "Thanks", sourceLanguage: .english, translatedText: "Cảm ơn")

    let controller = FavoritesWindowController(database: store)
    controller.show()
    let table = try #require(findTable(in: controller.window?.contentView))
    #expect(table.numberOfRows == 2)
    #expect(table.tableColumns.count == 2)
    controller.close()
}

@MainActor
private func findTable(in view: NSView?) -> NSTableView? {
    guard let view else { return nil }
    if let table = view as? NSTableView { return table }
    for child in view.subviews {
        if let table = findTable(in: child) { return table }
    }
    return nil
}

@Test @MainActor func favoritesWindowRemovesSelectedTranslation() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try DatabaseStore(path: dir.appendingPathComponent("favorites.sqlite3").path)
    _ = try store.saveFavorite(sourceText: "Hello", sourceLanguage: .english, translatedText: "Xin chào")

    let controller = FavoritesWindowController(database: store)
    controller.show()
    let table = try #require(findTable(in: controller.window?.contentView))
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    let button = try #require(findRemoveButton(in: controller.window?.contentView))
    #expect(button.isEnabled)
    button.performClick(nil)
    #expect(try store.listFavorites().isEmpty)
    controller.close()
}

@MainActor
private func findRemoveButton(in view: NSView?) -> NSButton? {
    guard let view else { return nil }
    if let button = view as? NSButton, button.title == "Remove" { return button }
    for child in view.subviews {
        if let button = findRemoveButton(in: child) { return button }
    }
    return nil
}
