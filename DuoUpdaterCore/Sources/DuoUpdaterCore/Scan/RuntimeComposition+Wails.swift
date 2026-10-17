import Foundation

extension RuntimeComposition {

    /// Bubble Tea, the terminal UI framework, linked into a Wails app.
    static let wailsBubbleTea = RuntimeComponent(id: "wails.bubbletea", name: "Bubble Tea")

    /// Wails, from the function names in the one Go binary it ships.
    ///
    /// A Wails window is the system WebView in every app, so "WKWebView" would
    /// repeat the badge, as it does for Tauri.
    ///
    /// **Bubble Tea.** magpie (`wails/v3 v3.0.0-beta.24`) links
    /// `github.com/charmbracelet/bubbletea` v1.3.10 beside Wails: a terminal
    /// interface compiled into the same binary as the windowed one. Its function
    /// names in `__gopclntab` are the evidence, as `mygo/ui` is for MyGo — Go's
    /// linker drops packages nothing reaches, which the module list alone does
    /// not show. Bubble Tea v2 moved to `charm.land/bubbletea/v2` (the module
    /// line of its `go.mod`), and its pre-releases used
    /// `github.com/charmbracelet/bubbletea/v2`; all three spellings count.
    static func wails(_ context: Context) -> [RuntimeComponent] {
        let bubbleTea = [
            "github.com/charmbracelet/bubbletea.",
            "github.com/charmbracelet/bubbletea/v2.",
            "charm.land/bubbletea/v2.",
        ]
        if bubbleTea.contains(where: { context.sectionContains(nil, "__gopclntab", $0) }) {
            return [wailsBubbleTea]
        }
        return []
    }
}
