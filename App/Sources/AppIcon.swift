import AppKit

@MainActor
enum AppIcon {
    private static var appearanceObservation: NSKeyValueObservation?

    /// LSUIElement menu-bar apps can momentarily surface as a generic placeholder
    /// icon when promoted to `.regular` for a window/⌘-Tab presence. Re-apply the
    /// bundle icon explicitly so the running process advertises the real app icon
    /// even if LaunchServices doesn't eagerly hydrate it.
    static func start() {
        guard appearanceObservation == nil else {
            applyIfAvailable()
            return
        }

        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.initial, .new]) { _, _ in
            Task { @MainActor in
                applyIfAvailable()
                AppDockBadge.refreshIcon()
            }
        }
    }

    static func applyIfAvailable() {
        let app = NSApplication.shared
        if let icon = NSImage(named: "AppRuntimeIcon") {
            app.applicationIconImage = icon
            return
        }

        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        app.applicationIconImage = icon
    }
}
