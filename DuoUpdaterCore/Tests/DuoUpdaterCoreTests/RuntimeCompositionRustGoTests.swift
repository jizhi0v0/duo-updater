import Testing
import Foundation
@testable import DuoUpdaterCore

/// The GPUI, egui, Tauri and Wails readers of `RuntimeComposition`. The strings
/// are the shapes of real `__TEXT,__cstring` entries.

private let registry = "/Users/runner/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f"

private func cstring(_ lines: String...) -> [String: String] {
    ["__TEXT,__cstring": lines.joined(separator: "\u{0}") + "\u{0}"]
}

private func read(_ runtime: AppRuntime, _ sections: [String: String]) throws -> [RuntimeComponent] {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    return RuntimeComposition.read(runtime, compositionContext(bundle, sections: sections))
}

// MARK: GPUI

/// Herdr: a renamed wry, `lb-wry`, beside `gpui-pre`.
@Test func gpuiWithARenamedWryShipsTheWebView() throws {
    let found = try read(.gpui, cstring(
        "\(registry)/gpui-pre-0.3.6/src/app.rs",
        "\(registry)/lb-wry-0.53.3/src/wkwebview/mod.rs"))
    #expect(found.map(\.id) == ["gpui.webview"])
    #expect(found.map(\.name) == ["WKWebView"])
}

/// Waku: wry under its own name.
@Test func gpuiWithPlainWryShipsTheWebView() throws {
    let found = try read(.gpui, cstring("\(registry)/wry-0.56.0/src/wkwebview/navigation.rs"))
    #expect(found.map(\.id) == ["gpui.webview"])
}

/// Superconductor: vendored in the repository, no leading directory.
@Test func gpuiWithAVendoredWryShipsTheWebView() throws {
    let found = try read(.gpui, cstring("vendor/lb-wry-macos/src/wkwebview/navigation.rs"))
    #expect(found.map(\.id) == ["gpui.webview"])
}

/// Zed Preview: GPUI and Metal and nothing else to say.
@Test func gpuiAloneShipsNothing() throws {
    #expect(try read(.gpui, cstring(
        "/Users/zed/crates/gpui/src/app.rs", "/Users/zed/crates/gpui_macos/src/metal_renderer.rs")).isEmpty)
}

/// An app's own crate called `herdr-wry`, or the word `wry`, is not the WebView.
@Test func gpuiNameLookalikesAreNotTheWebView() throws {
    #expect(try read(.gpui, cstring(
        "/Users/dev/herdr-wry/src/lib.rs",
        "/Users/dev/wry/src/lib.rs",
        "wry::WebView",
        "wkwebview")).isEmpty)
}

/// The module path counts in `__cstring` only — the section the detector reads.
@Test func gpuiWebViewPathInAnotherSectionDoesNotCount() throws {
    #expect(try read(.gpui, ["__TEXT,__const": "\(registry)/wry-0.56.0/src/wkwebview/mod.rs\u{0}"]).isEmpty)
}

// MARK: egui

/// DesignCraft and the other "...Craft" apps.
@Test func eguiOnWgpuShipsWgpu() throws {
    let found = try read(.egui, cstring(
        "\(registry)/egui-0.36.2/src/context.rs",
        "\(registry)/egui-wgpu-0.36.2/src/renderer.rs",
        "\(registry)/eframe-0.36.2/src/native/wgpu_integration.rs",
        "\(registry)/wgpu-core-30.0.1/src/instance.rs"))
    #expect(found.map(\.id) == ["egui.wgpu"])
    #expect(found.map(\.name) == ["wgpu"])
}

/// Spotifast: a git checkout of egui, laid out `crates/<name>/src`.
@Test func eguiOnGlowShipsGlow() throws {
    let checkout = "/Users/runner/.cargo/git/checkouts/egui-36521202101fc217/ba6790f/crates"
    let found = try read(.egui, cstring(
        "\(checkout)/egui/src/context.rs",
        "\(checkout)/egui_glow/src/painter.rs",
        "\(registry)/glow-0.17.0/src/native.rs"))
    #expect(found.map(\.id) == ["egui.glow"])
    #expect(found.map(\.name) == ["glow"])
}

/// An app may link both layers; wgpu is listed first.
@Test func eguiWithBothLayersListsBoth() throws {
    let found = try read(.egui, cstring(
        "\(registry)/egui-wgpu-0.36.2/src/lib.rs",
        "\(registry)/egui_glow-0.36.2/src/lib.rs"))
    #expect(found.map(\.name) == ["wgpu", "glow"])
}

/// eframe's own integration file is a witness where the layer has no path.
@Test func eguiBackendIsAlsoReadFromEframeIntegrationFile() throws {
    #expect(try read(.egui, cstring("\(registry)/eframe-0.36.2/src/native/glow_integration.rs")).map(\.id) == ["egui.glow"])
    #expect(try read(.egui, cstring("\(registry)/eframe-0.36.2/src/native/wgpu_integration.rs")).map(\.id) == ["egui.wgpu"])
}

/// egui on its default layer, with neither backend's path: no claim.
@Test func eguiWithoutABackendPathShipsNothing() throws {
    #expect(try read(.egui, cstring("\(registry)/egui-0.36.2/src/context.rs")).isEmpty)
}

/// `eframe` as a word, `wgpu` or `glow` as a bare name, and a crate whose name
/// merely begins with them are not paths of the backend crates.
@Test func eguiLookalikesAreNotABackend() throws {
    #expect(try read(.egui, cstring(
        "eframe failed to encode data using ron",
        "wgpu adapter",
        "glow",
        "/Users/dev/my-egui-wgpu/src/main.rs",
        "/Users/dev/glow-egui_glow/src/main.rs",
        "/Users/dev/glow_integration.rs")).isEmpty)
}

@Test func eguiBackendPathInAnotherSectionDoesNotCount() throws {
    #expect(try read(.egui, ["__TEXT,__const": "\(registry)/egui-wgpu-0.36.2/src/lib.rs\u{0}"]).isEmpty)
}

// MARK: Tauri and Wails

/// Jan, Handy, Clash Verge and the others: wry, tao and the WebKit bindings
/// are what every Tauri app has.
@Test func tauriShipsNothingBesideItsWebView() throws {
    #expect(try read(.tauri, cstring(
        "\(registry)/tauri-2.9.0/src/lib.rs",
        "\(registry)/tauri-runtime-wry-2.9.0/src/lib.rs",
        "\(registry)/wry-0.55.1/src/wkwebview/mod.rs",
        "\(registry)/tao-0.34.0/src/lib.rs")).isEmpty)
}

@Test func wailsShipsNothingBesideItsWebView() throws {
    #expect(try read(.wails, [
        "__TEXT,__rodata": "mygo_frontend/ index.html",
        "__TEXT,__gopclntab": "github.com/wailsapp/wails/v3/pkg/application.(*App).Run\u{0}",
    ]).isEmpty)
}

/// magpie's shape: Bubble Tea v1 linked beside Wails v3.
@Test func wailsReportsBubbleTeaFromItsFunctionNames() throws {
    #expect(try read(.wails, [
        "__TEXT,__gopclntab": "github.com/wailsapp/wails/v3/pkg/application.(*App).Run\u{0}"
            + "github.com/charmbracelet/bubbletea.(*Program).Run\u{0}",
    ]).map(\.name) == ["Bubble Tea"])
    #expect(try read(.wails, ["__TEXT,__gopclntab": "charm.land/bubbletea/v2.(*Program).Run"]).map(\.id)
            == ["wails.bubbletea"])
    #expect(try read(.wails, ["__TEXT,__gopclntab": "github.com/charmbracelet/bubbletea/v2.NewProgram"]).map(\.id)
            == ["wails.bubbletea"])
}

/// Bubble Tea's siblings are not Bubble Tea, and its name outside the function
/// table (a module-list line in read-only data) is not linked code.
@Test func wailsBubbleTeaLookalikesDoNotCount() throws {
    #expect(try read(.wails, [
        "__TEXT,__gopclntab": "github.com/charmbracelet/bubbles/list.New\u{0}github.com/charmbracelet/lipgloss.NewStyle",
        "__TEXT,__rodata": "dep\tgithub.com/charmbracelet/bubbletea.\tv1.3.10",
    ]).isEmpty)
}

// MARK: Real bundle

/// The real reader against a bundle with no executable: nothing, and no crash.
@Test func rustAndGoReadersToleratePlainBundlesWithoutAnExecutable() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    for runtime in [AppRuntime.gpui, .egui, .tauri, .wails] {
        #expect(RuntimeComposition.read(runtime, bundleAt: bundle).isEmpty)
    }
}
