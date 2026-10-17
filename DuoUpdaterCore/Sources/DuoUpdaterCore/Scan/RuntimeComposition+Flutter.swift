import Foundation

extension RuntimeComposition {

    /// A web page in the system WebView, from a Flutter plugin that links WebKit.
    static let flutterWebView = RuntimeComponent(id: "flutter.webview", name: "WKWebView")

    /// Flutter, from the plugin frameworks beside the engine.
    ///
    /// **Rendering is no evidence.** The engine in AweSun, LocalSend, Mithka and
    /// RustDesk each carries both the Impeller and the Skia strings, so neither
    /// says which one draws.
    ///
    /// **WebView.** The Flutter embedder is not a WebView host, so a plugin that
    /// is one says so in its load commands: AweSun's
    /// `webview_flutter_wkwebview.framework` and
    /// `desktop_webview_window.framework` link
    /// `/System/Library/Frameworks/WebKit.framework`, and no other framework in
    /// AweSun does. LocalSend, Mithka and RustDesk link WebKit from none of their
    /// frameworks. Each `Contents/Frameworks/*.framework` other than the engine is
    /// asked, header only (`MachOImports`), and the first that links WebKit
    /// settles it. A WebView plugin linked statically into `App.framework` leaves
    /// no framework of its own and is missed.
    static func flutter(_ context: Context) -> [RuntimeComponent] {
        flutter(context, linkedLibraries: MachOImports.linkedLibraries(at:))
    }

    /// `flutter(_:)` with the Mach-O read injected, so a test needs no binary.
    static func flutter(
        _ context: Context, linkedLibraries: (URL) -> Set<String>?
    ) -> [RuntimeComponent] {
        let engine = "FlutterMacOS.framework"
        for name in context.listing("Frameworks").sorted()
        where name.hasSuffix(".framework") && name != engine {
            let stem = String(name.dropLast(".framework".count))
            // The framework's top-level link to its binary; a framework with
            // none (resources only) has nothing to read.
            let relative = "Frameworks/\(name)/\(stem)"
            guard context.exists(relative),
                  let linked = linkedLibraries(context.contents.appendingPathComponent(relative))
            else { continue }
            if linked.contains(where: { $0.hasPrefix("/System/Library/Frameworks/WebKit.framework/") }) {
                return [flutterWebView]
            }
        }
        return []
    }
}
