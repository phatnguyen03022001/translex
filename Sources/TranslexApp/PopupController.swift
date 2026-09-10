import AppKit

@MainActor
final class PopupController {
    private let panel: NSPanel
    private let effect = NSVisualEffectView()
    private let sourceLabel = NSTextField(labelWithString: "")
    private let primaryLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let favoriteButton = NSButton(title: "+", target: nil, action: nil)
    private var favoriteAction: (() throws -> Void)?
    private var dismissTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("TranslexPopup")
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.font = .systemFont(ofSize: 11)
        sourceLabel.lineBreakMode = .byTruncatingTail
        primaryLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        primaryLabel.maximumNumberOfLines = 5
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.maximumNumberOfLines = 2

        favoriteButton.target = self
        favoriteButton.action = #selector(performFavoriteAction)
        favoriteButton.isBordered = false
        favoriteButton.font = .systemFont(ofSize: 16, weight: .semibold)
        favoriteButton.toolTip = "Save to Favorites"
        favoriteButton.isHidden = true

        let textStack = NSStackView(views: [sourceLabel, primaryLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 7
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [textStack, favoriteButton])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12)
        ])
    }

    func show(
        source: String?,
        primary: String,
        detail: String? = nil,
        anchor: NSPoint = NSEvent.mouseLocation,
        duration: TimeInterval,
        favoriteAction: (() throws -> Void)? = nil
    ) {
        configureContent(source: source, primary: primary, detail: detail)
        self.favoriteAction = favoriteAction
        favoriteButton.title = "+"
        favoriteButton.toolTip = "Save to Favorites"
        favoriteButton.isHidden = favoriteAction == nil
        panel.ignoresMouseEvents = favoriteAction == nil
        primaryLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        primaryLabel.maximumNumberOfLines = 5

        let width: CGFloat = 360
        let fitting = effect.fittingSize
        let height = min(max(fitting.height, 84), 260)
        present(width: width, height: height, anchor: anchor, duration: duration)
    }

    func showToast(
        _ text: String,
        anchor: NSPoint = NSEvent.mouseLocation,
        duration: TimeInterval = 1.25
    ) {
        favoriteAction = nil
        favoriteButton.isHidden = true
        panel.ignoresMouseEvents = true
        sourceLabel.isHidden = true
        detailLabel.isHidden = true
        primaryLabel.stringValue = text
        primaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        primaryLabel.maximumNumberOfLines = 1
        let measured = text.size(withAttributes: [.font: primaryLabel.font as Any])
        let width = min(max(measured.width + 32, 130), 220)
        present(width: width, height: 38, anchor: anchor, duration: min(max(duration, 1.0), 1.5))
    }

    private func configureContent(source: String?, primary: String, detail: String?) {
        sourceLabel.stringValue = source ?? ""
        sourceLabel.isHidden = source?.isEmpty ?? true
        primaryLabel.stringValue = primary
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail?.isEmpty ?? true
    }

    private func present(width: CGFloat, height: CGFloat, anchor: NSPoint, duration: TimeInterval) {
        var frame = NSRect(x: anchor.x + 14, y: anchor.y - height - 12, width: width, height: height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - width - 8 }
            if frame.minX < visible.minX { frame.origin.x = visible.minX + 8 }
            if frame.minY < visible.minY { frame.origin.y = anchor.y + 16 }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - height - 8 }
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        scheduleDismiss(after: duration)
    }

    private func scheduleDismiss(after duration: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            let nanos = UInt64(max(0.5, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    @objc private func performFavoriteAction() {
        guard let favoriteAction, favoriteButton.title != "✓" else { return }
        do {
            try favoriteAction()
            favoriteButton.title = "✓"
            favoriteButton.toolTip = "Saved to Favorites"
        } catch {
            favoriteButton.title = "!"
            favoriteButton.toolTip = error.localizedDescription
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        favoriteAction = nil
        panel.orderOut(nil)
    }
}
