import Foundation

extension RuntimeComposition {

    /// A web page in the system WebView, from a frontend `mygo build` embedded.
    static let myGoWebView = RuntimeComponent(id: "mygo.webview", name: "WKWebView")
    /// The interface MyGo draws itself on the GPU, written with its package `ui`.
    static let myGoUI = RuntimeComponent(id: "mygo.ui", name: "MyGo UI")

    /// MyGo, from two sections of the one Go binary it ships (mygo v0.2.14 to
    /// v0.4.2, Go 1.27).
    ///
    /// **WebView.** Every MyGo binary carries the means to open a WebView — it
    /// `dlopen`s WebKit at run time whatever the app does — so that is no
    /// evidence. A frontend is: `mygo build` embeds `frontendDist` under the
    /// directory `mygo_frontend` of the main package (`cmd/mygo/embed.go`), and
    /// Go keeps embedded file names in `__TEXT,__rodata`. Observed: 5 hits in a
    /// web-template demo, 0 in Leafmark, Pulse and Moshi Go. A page loaded from a
    /// URL, or a frontend embedded by hand, leaves no such name and is missed.
    ///
    /// **MyGo UI.** The root package does not import `mygo/ui` (v0.2.14, v0.4.1,
    /// v0.4.2), and Go's linker drops packages nothing reaches, so its function
    /// names in `__gopclntab` mean something in the build draws with it: 0 in the
    /// web demo, about 1,100 to 2,100 in the other three. That something can be a
    /// plugin rather than the app's own windows — `plugins/updater/native` draws
    /// the update window with `ui`, and Pulse ships it — which is the "ships, not
    /// shows" caveat at its plainest.
    static func myGo(_ context: Context) -> [RuntimeComponent] {
        var found: [RuntimeComponent] = []
        if context.sectionContains("__TEXT", "__rodata", "mygo_frontend/") {
            found.append(myGoWebView)
        }
        if context.sectionContains(nil, "__gopclntab", "github.com/egoist/mygo/ui.") {
            found.append(myGoUI)
        }
        return found
    }
}
