import AppKit
import DuoUpdaterCore

/// Whether Duo Updater shows a Dock icon, or lives in the menu bar only.
///
/// The bundle declares `LSUIElement`, so every launch starts in the menu bar with
/// no Dock icon — the default, and the only way to avoid a Dock icon flashing up
/// at login before our code runs. `Preferences.hideDockIcon` is the switch; when
/// the user turns it off, `apply` promotes us to `.regular` at startup and the
/// Dock tile (and its update badge) comes back.
@MainActor
enum DockIcon {
    /// Switch the Dock icon on or off.
    ///
    /// Open windows survive the switch either way — measured on macOS 27.0, a
    /// window is still `isVisible` after both transitions. What is lost going to
    /// `.accessory` is *focus*: the app deactivates, and asking to activate again
    /// right afterwards does not win it back (also measured). So the window the
    /// user just clicked the toggle in stays on screen, unfocused, until they
    /// click it — which is the ordinary way into a menu-bar app's window anyway.
    /// The re-activate below is kept for the `.regular` direction, where it does
    /// take, and costs nothing in the other.
    static func apply(hidden: Bool) {
        let wanted: NSApplication.ActivationPolicy = hidden ? .accessory : .regular
        let app = NSApplication.shared
        guard app.activationPolicy() != wanted else { return }

        let visible = app.windows.filter(\.isVisible)
        let key = app.keyWindow
        let ok = app.setActivationPolicy(wanted)
        Log.app.info("dock: activation policy → \(hidden ? "accessory" : "regular", privacy: .public) ok=\(ok, privacy: .public)")

        // Coming back to `.regular` gets a fresh, unbadged Dock tile.
        if !hidden { AppDockBadge.reassert() }

        guard !visible.isEmpty else { return }
        // Next runloop: the policy change is still settling on this one.
        DispatchQueue.main.async {
            app.activate(ignoringOtherApps: true)
            for window in visible { window.orderFrontRegardless() }
            key?.makeKeyAndOrderFront(nil)
        }
    }
}
