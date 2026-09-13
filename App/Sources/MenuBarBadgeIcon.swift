import AppKit
import SwiftUI

/// The menu-bar icon's pending-update count.
///
/// SF Symbols only ship numbered circles up to `50.circle.fill` (`51.circle.fill`
/// doesn't exist), so a count above 50 used to be clamped to 50 while the Dock badge,
/// capped at 99, showed the real number. Up to 50 we keep the system symbol; above it
/// we draw the same shape ourselves — the system's own `circle.fill`, which has the
/// numbered symbols' exact size and alignment rect, with the digits knocked out.
enum MenuBarBadgeIcon {
    static func image(count: Int) -> Image {
        if count <= 50 {
            return Image(systemName: "\(count).circle.fill")
        }
        return Image(nsImage: drawn(count: min(count, 99)))
    }

    private static func drawn(count: Int) -> NSImage {
        // The status bar draws symbols at the menu-bar font size (13pt, measured
        // against the old `50.circle.fill` on screen).
        let pointSize = NSFont.menuBarFont(ofSize: 0).pointSize
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let circle = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return NSImage() }

        let text = "\(count)" as NSString
        // Condensed digits, like the numbered symbols'.
        let font = NSFont.systemFont(ofSize: pointSize * 0.6, weight: .medium, width: .condensed)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let image = NSImage(size: circle.size, flipped: false) { rect in
            circle.draw(in: rect)
            guard let context = NSGraphicsContext.current else { return false }
            context.compositingOperation = .destinationOut
            let textSize = text.size(withAttributes: attributes)
            // `draw(at:)` places the line's bottom (baseline + descender); centre the
            // cap height on the circle.
            text.draw(
                at: NSPoint(x: rect.midX - textSize.width / 2,
                            y: rect.midY - font.capHeight / 2 + font.descender),
                withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "\(count)"
        return image
    }
}
