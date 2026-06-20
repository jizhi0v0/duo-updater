import AppKit

private final class DockBadgeTileView: NSView {
    private let iconView = NSImageView()
    private let badgeBubble = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        badgeBubble.wantsLayer = true
        badgeBubble.layer?.backgroundColor = NSColor(
            calibratedRed: 0.18, green: 0.21, blue: 0.28, alpha: 0.98
        ).cgColor
        badgeBubble.layer?.cornerCurve = .continuous
        badgeBubble.layer?.borderWidth = 1
        badgeBubble.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        badgeBubble.layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        badgeBubble.layer?.shadowOpacity = 1
        badgeBubble.layer?.shadowRadius = 4
        badgeBubble.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(badgeBubble)

        badgeLabel.alignment = .center
        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        badgeBubble.addSubview(badgeLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        iconView.frame = bounds

        let side = min(bounds.width, bounds.height)
        let badgeHeight = max(28, side * 0.27)
        let minWidth = badgeHeight
        let textWidth = badgeLabel.intrinsicContentSize.width + 14
        let badgeWidth = max(minWidth, textWidth)
        let x = bounds.maxX - badgeWidth - max(2, side * 0.015)
        let y = bounds.maxY - badgeHeight - max(1, side * 0.01)
        badgeBubble.frame = NSRect(x: x, y: y, width: badgeWidth, height: badgeHeight)
        badgeBubble.layer?.cornerRadius = badgeHeight / 2
        badgeLabel.frame = badgeBubble.bounds.insetBy(dx: 4, dy: 2)
    }

    func update(icon: NSImage?, count: Int) {
        iconView.image = icon
        if count > 0 {
            badgeLabel.stringValue = String(min(count, 99))
            badgeBubble.isHidden = false
        } else {
            badgeLabel.stringValue = ""
            badgeBubble.isHidden = true
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

@MainActor
enum AppDockBadge {
    private static let tileSide: CGFloat = 128
    private static var lastCount = 0
    private static let tileView = DockBadgeTileView(
        frame: NSRect(x: 0, y: 0, width: tileSide, height: tileSide)
    )

    static func sync(count: Int) {
        lastCount = count
        let app = NSApplication.shared
        AppIcon.applyIfAvailable()
        app.dockTile.badgeLabel = nil
        tileView.update(icon: app.applicationIconImage, count: count)
        app.dockTile.contentView = tileView
        app.dockTile.display()
    }

    static func refreshIcon() {
        sync(count: lastCount)
    }

    static func syncSoon(count: Int) {
        Task { @MainActor in
            await Task.yield()
            sync(count: count)
        }
    }
}
