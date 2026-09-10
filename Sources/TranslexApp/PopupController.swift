import AppKit

@MainActor
final class PopupController {
    private let panel: NSPanel
    private let sourceLabel = NSTextField(labelWithString: "")
    private let primaryLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var dismissTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        let effect = NSVisualEffectView()
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

        let stack = NSStackView(views: [sourceLabel, primaryLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12)
        ])
    }

    func show(
        source: String?,
        primary: String,
        detail: String? = nil,
        anchor: NSPoint = NSEvent.mouseLocation,
        duration: TimeInterval
    ) {
        sourceLabel.stringValue = source ?? ""
        sourceLabel.isHidden = source?.isEmpty ?? true
        primaryLabel.stringValue = primary
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail?.isEmpty ?? true

        let width: CGFloat = 360
        let fitting = panel.contentView?.fittingSize ?? NSSize(width: width, height: 100)
        let height = min(max(fitting.height, 84), 260)
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

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            let nanos = UInt64(max(0.5, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel.orderOut(nil)
    }
}
