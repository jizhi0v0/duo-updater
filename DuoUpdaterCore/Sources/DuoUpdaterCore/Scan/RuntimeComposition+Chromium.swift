import Foundation

extension RuntimeComposition {

    /// A Chromium shell: nothing to report.
    ///
    /// What this runtime is made of is what the badge says. Google Chrome,
    /// Helium and Vivaldi each ship one `<product> Framework.framework` and draw
    /// their window chrome with Chromium's own toolkit, which leaves no second
    /// technology in the bundle. A CEF app's framework is the same engine as the
    /// badge's, so naming it (`Chromium Embedded Framework.framework` in
    /// Spotify) would repeat the badge in another spelling. CEF is only worth a
    /// line when something else draws the windows, and `qt(_:)` reports it there.
    ///
    /// What a CEF shell's own windows are is not in the bundle. Spotify's main
    /// binary links AppKit and ships CEF without linking it (CEF is loaded at
    /// run time), and its helpers (`Spotify Helper (Renderer).app` and the like)
    /// are the layout every CEF app has. An AppKit link says the shell can open
    /// a native window, not that it opens one, and every shell links AppKit.
    static func chromium(_ context: Context) -> [RuntimeComponent] {
        []
    }

    /// Electron: nothing to report.
    ///
    /// Whether a window is a `BrowserWindow` or a `WebContentsView` is decided
    /// by the app's JavaScript at run time, and neither is a bundle-level
    /// signal: both live in the one `Electron Framework.framework` every
    /// Electron app ships. Beside it VS Code, Claude and Notion carry only
    /// helper apps and the updater's `Squirrel`, `Mantle` and `ReactiveObjC`, and the JavaScript is a
    /// packed `app.asar` that is not searched here: a string found in it would
    /// be a guess at a call, not evidence of a window. Native add-ons (`.node`
    /// files) are not a UI technology either.
    static func electron(_ context: Context) -> [RuntimeComponent] {
        []
    }
}
