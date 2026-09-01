import Foundation

/// One window as the window server describes it — the few fields that decide
/// whether something is actually in front of the user.
///
/// A value type rather than the `CFDictionary` `CGWindowListCopyWindowInfo` hands
/// back, so the rule below can be tested without a window server: the App target
/// has no tests (see `CLAUDE.md`), and this rule is the reason the window either
/// appears or does not.
public struct WindowInfo: Sendable, Equatable {
    /// `kCGWindowNumber` — matches `NSWindow.windowNumber`.
    public let number: Int
    /// `kCGWindowLayer`. Ordinary windows are 0; menus, popovers and status-item
    /// panels live above (102, 101, …) and are not competitors for "in front".
    public let layer: Int
    /// `kCGWindowIsOnscreen`. False for a window that has been closed, hidden or
    /// minimised — a SwiftUI `Window` scene keeps its `NSWindow` after ⌘W, so this
    /// is the difference between "exists" and "the user can see it".
    public let isOnScreen: Bool

    public init(number: Int, layer: Int, isOnScreen: Bool) {
        self.number = number
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

/// Whether a window is really the one in front, asked of the window server rather
/// than assumed from having asked for it.
///
/// This exists because ordering a window front is a *request*, and with the Dock
/// icon hidden — `.accessory`, Duo Updater's default — the first one is refused.
/// Logged from the shipped app, opening the workbench from the popover's row menu,
/// four consecutive times with no variation:
///
///     surface[1] workbench visible=true key=true front=false policy=accessory
///     surface[2] workbench visible=true key=true front=true  policy=accessory
///
/// `visible=true key=true front=false` is the state AppKit cannot describe. The
/// window is open; it is this app's key window; it is not the frontmost window on
/// screen. Asking `NSWindow` gets "yes" to both of the questions it can answer, so
/// the code that asserted once and returned believed it was done — and to the user
/// that is a menu item that does nothing, with a second click on any row bringing
/// the window up, which is what made the bug look app-specific for a while.
///
/// Known behaviour rather than a defect of ours: a menu-bar app has no Dock icon
/// and macOS will not let its window take the front on the asking. Not something
/// Apple's documentation states, as far as could be found — the corroboration is
/// third-party write-ups of the same symptom, and the primary evidence is the log
/// above.
public enum WindowOrder {

    /// Is `number` the frontmost ordinary on-screen window?
    ///
    /// `windows` is the window server's list in front-to-back order — which means
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly, …)`. **`.optionAll` is not
    /// ordered**, and mistaking it for a z-order is not a subtle error: measured on
    /// this machine with Claude frontmost, `.optionAll` listed Excel, Messages,
    /// Finder and Zed ahead of it while `.optionOnScreenOnly` put Claude first. An
    /// investigation that read `.optionAll` as depth spent an hour on a window it
    /// believed was buried eight deep and that was in fact in front.
    ///
    /// Only layer-0, on-screen windows are competitors: the popover that the click came
    /// from is layer 101 and the row menu is layer 102, and both are legitimately
    /// above everything while they are up. Counting those as "in front" would make
    /// the check answer *no* forever and leave the caller retrying against windows
    /// it is not fighting.
    ///
    /// False when the window is not in the list at all: not on screen is not in
    /// front, and that is the state to keep retrying from.
    public static func isFrontmost(_ number: Int, in windows: [WindowInfo]) -> Bool {
        windows.first { $0.layer == 0 && $0.isOnScreen }?.number == number
    }
}
