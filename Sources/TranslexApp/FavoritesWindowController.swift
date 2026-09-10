import AppKit
import TranslexCore

@MainActor
final class FavoritesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let database: DatabaseStore
    private var favorites: [FavoriteRecord] = []
    private let table = NSTableView()
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    init(database: DatabaseStore) {
        self.database = database
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Favorites"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let source = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        source.title = "Source"
        source.width = 235
        let translation = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("translation"))
        translation.title = "Translation"
        translation.width = 235
        table.addTableColumn(source)
        table.addTableColumn(translation)
        table.headerView = NSTableHeaderView()
        table.rowHeight = 34
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false

        removeButton.target = self
        removeButton.action = #selector(removeSelected)
        removeButton.isEnabled = false
        let footer = NSStackView(views: [NSView(), removeButton])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
    }

    func show() {
        reloadFavorites()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func reloadFavorites() {
        do {
            favorites = try database.listFavorites()
            table.reloadData()
            removeButton.isEnabled = false
        } catch {
            favorites = []
            table.reloadData()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not load Favorites"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { favorites.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard favorites.indices.contains(row), let tableColumn else { return nil }
        let favorite = favorites[row]
        let text = tableColumn.identifier.rawValue == "source" ? favorite.sourceText : favorite.translatedText
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = favorites.indices.contains(table.selectedRow)
    }

    @objc private func removeSelected() {
        let row = table.selectedRow
        guard favorites.indices.contains(row) else { return }
        do {
            _ = try database.deleteFavorite(id: favorites[row].id)
            reloadFavorites()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not remove favorite"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
