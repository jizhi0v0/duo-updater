import Foundation

extension RuntimeComposition {

    /// Wails: nothing to report.
    ///
    /// A Wails window is the system WebView in every app, so "WKWebView" would
    /// repeat the badge, as it does for Tauri. The one Wails app known here,
    /// magpie (`wails/v3 v3.0.0-beta.24`), links a terminal UI library (Bubble
    /// Tea) beside it, but a Go module in the build list says what is compiled
    /// in and not how an interface is drawn, and one app is not enough to
    /// build a list of which modules draw. Revisit with a second Wails app that
    /// shows a distinct renderer.
    static func wails(_ context: Context) -> [RuntimeComponent] {
        []
    }
}
