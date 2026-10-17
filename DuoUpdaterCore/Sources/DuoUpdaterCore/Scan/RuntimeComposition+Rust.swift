import Foundation

extension RuntimeComposition {

    /// A web page in the system WebView, through the `wry` crate.
    static let rustWebView = RuntimeComponent(id: "gpui.webview", name: "WKWebView")
    /// egui drawn through the `wgpu` graphics layer.
    static let eguiWgpu = RuntimeComponent(id: "egui.wgpu", name: "wgpu")
    /// egui drawn through OpenGL, by way of the `glow` crate.
    static let eguiGlow = RuntimeComponent(id: "egui.glow", name: "glow")

    /// GPUI, from `__TEXT,__cstring` — the section the detector reads its crate
    /// paths from.
    ///
    /// **WebView.** GPUI itself draws with Metal on macOS and has no choice to
    /// report, so Metal is no component. What some GPUI apps carry beside it is
    /// a web view, through `wry`, whose macOS half lives in `src/wkwebview/`.
    /// The crate is renamed or vendored often enough that its directory name is
    /// no evidence: Herdr and Longbridge build `lb-wry-0.53.3`, Superconductor
    /// vendors `lb-wry-macos`, Waku builds plain `wry-0.56.0`. The evidence is
    /// the module directory, `/src/wkwebview/`, which every one of them leaves
    /// in panic locations; Zed Preview, Reviu, Kitten Preview, OpenLogi and
    /// disktree leave none. An app's own crate named `…-wry` does not match
    /// because its sources are not under `src/wkwebview/`.
    ///
    /// The path is wry being linked; whether a window ever shows a page is not
    /// known, which is the "ships, not shows" caveat.
    static func gpui(_ context: Context) -> [RuntimeComponent] {
        guard let strings = context.section("__TEXT", "__cstring") else { return [] }
        return contains(strings, wkwebviewModule) ? [rustWebView] : []
    }

    /// egui, from `__TEXT,__cstring`.
    ///
    /// Which graphics layer egui draws through is a build-time choice, and each
    /// choice leaves its own crate in the panic locations: `egui-wgpu` (with
    /// `wgpu-core` and `wgpu-hal` beside it) in DesignCraft, FilmCraft and the
    /// other "…Craft" apps, `egui_glow` and `glow` in Spotifast. `eframe`'s own
    /// `native/wgpu_integration.rs` and `native/glow_integration.rs` are the
    /// second witness, and the only one for an app that links egui_wgpu or
    /// egui_glow statically without a path of its own. The bare word `eframe` is
    /// no evidence — it is in unrelated binaries — so every test here is a
    /// crate source path, with the leading-slash rule of the detector.
    static func egui(_ context: Context) -> [RuntimeComponent] {
        guard let strings = context.section("__TEXT", "__cstring") else { return [] }
        var found: [RuntimeComponent] = []
        if AppRuntimeDetector.containsCratePath(strings, "egui-wgpu")
            || contains(strings, "/src/native/wgpu_integration.rs") {
            found.append(eguiWgpu)
        }
        if AppRuntimeDetector.containsCratePath(strings, "egui_glow")
            || contains(strings, "/src/native/glow_integration.rs") {
            found.append(eguiGlow)
        }
        return found
    }

    /// Tauri: nothing to report, and that is a finding.
    ///
    /// Tauri's window is the system WebView in every app, so "WKWebView" would
    /// repeat the badge. What else could be positively shipped is not there:
    /// the stable API is one WebView per window (a second one is behind the
    /// `unstable` feature), and the C strings of Jan, Handy, Conductor, Clash
    /// Verge, CC Switch, Moshi, Cline, AstrLink and the rest carry `tauri`,
    /// `tao`, `wry` and `objc2-web-kit` paths and no other UI crate — no egui,
    /// GPUI, wgpu or glow. Tauri plugins (`tauri-plugin-dialog`, `-updater`, …)
    /// are features of the shell, not a way of drawing.
    static func tauri(_ context: Context) -> [RuntimeComponent] {
        []
    }

    /// The directory of `wry`'s macOS WebView, wherever the crate sits and
    /// whatever it is called.
    private static let wkwebviewModule = "/src/wkwebview/"
}
