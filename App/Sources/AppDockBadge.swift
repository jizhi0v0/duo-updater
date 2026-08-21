import AppKit

@MainActor
enum AppDockBadge {
    private static var lastCount = 0
    private static var reasserting = false

    /// Sets the system Dock badge to the pending-update count.
    ///
    /// Note: the Dock badge only renders if the app holds the "Badges" notification
    /// permission — `NotificationController` must request `.badge` in its authorization
    /// options, or the system silently suppresses `badgeLabel` even when it's set.
    ///
    /// A no-op while the user has the Dock icon hidden (`DockIcon`): there is no
    /// tile to badge then, and the count is already on the menu-bar icon.
    static func sync(count: Int) {
        lastCount = count
        let show = count > 0 && NSApplication.shared.activationPolicy() == .regular
        let tile = NSApplication.shared.dockTile
        tile.showsApplicationBadge = show
        tile.badgeLabel = show ? String(min(count, 99)) : nil
    }

    /// Re-push the last known count — for whoever just gave us a Dock tile back
    /// (turning the Dock icon on) and doesn't itself know the number.
    static func reassert() {
        syncSoon(count: lastCount)
    }

    /// Re-pushes the badge, clearing it first so the Dock actually repaints.
    ///
    /// Setting `badgeLabel` to the value it already holds is a no-op the Dock skips —
    /// which matters after a Dock restart (or `killall Dock`), when the new Dock process
    /// has no badge but the app's stored `badgeLabel` is unchanged, so a plain re-set
    /// wouldn't bring it back. Clearing to `nil` in a separate runloop tick forces a real
    /// `nil → value` transition that repaints.
    static func syncSoon(count: Int) {
        startReasserting()
        Task { @MainActor in
            NSApplication.shared.dockTile.badgeLabel = nil
            await Task.yield()
            sync(count: count)
        }
    }

    /// The Dock relaunching wipes every app's badge. There's no public "Dock restarted"
    /// signal, so re-push whenever the app is activated — clicking our Dock icon or
    /// opening a window brings the badge straight back instead of waiting for the next
    /// background check.
    private static func startReasserting() {
        guard !reasserting else { return }
        reasserting = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in syncSoon(count: lastCount) }
        }
    }
}
