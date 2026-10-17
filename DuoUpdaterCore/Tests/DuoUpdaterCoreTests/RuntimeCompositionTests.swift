import Testing
import Foundation
@testable import DuoUpdaterCore

/// `RuntimeComposition`'s dispatch and memo, and the MyGo reader. The other
/// readers are tested in their own files.

/// An empty bundle directory, removed by the caller.
func compositionBundle(_ files: [String] = []) throws -> URL {
    let bundle = FileManager.default.temporaryDirectory
        .appendingPathComponent("composition-\(UUID().uuidString).app")
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    for file in files {
        let url = contents.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if file.hasSuffix("/") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try Data().write(to: url)
        }
    }
    return bundle
}

/// A context whose executable's sections are `sections`, keyed `"segment,name"`.
func compositionContext(_ bundle: URL, sections: [String: String],
                        libraries: Set<String>? = nil) -> RuntimeComposition.Context {
    RuntimeComposition.Context(
        bundle: bundle, executable: bundle.appendingPathComponent("Contents/MacOS/app"), libraries: libraries
    ) { segment, name in
        if let segment { return sections["\(segment),\(name)"].map { Data($0.utf8) } }
        return sections.first { $0.key.hasSuffix(",\(name)") }.map { Data($0.value.utf8) }
    }
}

@Test func myGoWebDemoShipsOnlyTheWebView() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    // The shape of the web template's demo: an embedded frontend, no `ui` package.
    let context = compositionContext(bundle, sections: [
        "__TEXT,__rodata": "\u{0}mygo_frontend/assets/index-B4SS-a-G.js\u{0}",
        "__TEXT,__gopclntab": "github.com/egoist/mygo.(*Window).Show\u{0}",
    ])
    #expect(RuntimeComposition.read(.mygo, context).map(\.id) == ["mygo.webview"])
}

@Test func myGoNativeAppShipsOnlyMyGoUI() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    let context = compositionContext(bundle, sections: [
        "__TEXT,__rodata": "index.html\u{0}",
        "__TEXT,__gopclntab": "github.com/egoist/mygo/ui.(*Context).TitleBar\u{0}",
    ])
    #expect(RuntimeComposition.read(.mygo, context).map(\.id) == ["mygo.ui"])
}

@Test func myGoAppWithBothListsWebViewFirst() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    let context = compositionContext(bundle, sections: [
        "__TEXT,__rodata": "mygo_frontend/index.html",
        "__TEXT,__gopclntab": "github.com/egoist/mygo/ui.Text",
    ])
    #expect(RuntimeComposition.read(.mygo, context).map(\.name) == ["WKWebView", "MyGo UI"])
}

/// The frontend's name in the pcln table, or `ui` in read-only data, is not the
/// evidence: each signal counts only in the section it was observed in.
@Test func myGoSignalsCountOnlyInTheirOwnSection() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    let context = compositionContext(bundle, sections: [
        "__TEXT,__rodata": "github.com/egoist/mygo/ui.Text",
        "__TEXT,__gopclntab": "mygo_frontend/index.html",
    ])
    #expect(RuntimeComposition.read(.mygo, context).isEmpty)
}

@Test func appleStacksHaveNoComposition() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    var asked = 0
    let context = RuntimeComposition.Context(bundle: bundle, executable: nil) { _, _ in
        asked += 1
        return nil
    }
    for runtime in [AppRuntime.native, .catalyst, .iOSApp, .reactNative] {
        #expect(RuntimeComposition.read(runtime, context).isEmpty)
    }
    #expect(asked == 0)
}

@Test func aSectionIsReadOnceHoweverOftenItIsAsked() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    var reads = 0
    let context = RuntimeComposition.Context(bundle: bundle, executable: nil) { _, _ in
        reads += 1
        return nil
    }
    _ = context.sectionContains("__TEXT", "__rodata", "a")
    _ = context.sectionContains("__TEXT", "__rodata", "b")
    #expect(reads == 1)
}

/// The real reader against a bundle with no executable: nothing, and no crash.
@Test func aBundleWithoutAnExecutableShipsNothing() throws {
    let bundle = try compositionBundle()
    defer { try? FileManager.default.removeItem(at: bundle) }
    #expect(RuntimeComposition.read(.mygo, bundleAt: bundle).isEmpty)
}

/// How long the detail read takes on every app installed here, and what it says.
/// Opt-in: it reads real bundles, so its output describes this machine.
///
///     DUO_RUNTIME_COMPOSITION_BENCH=1 swift test --filter runtimeCompositionBench
@Test func runtimeCompositionBench() throws {
    guard ProcessInfo.processInfo.environment["DUO_RUNTIME_COMPOSITION_BENCH"] == "1" else { return }
    let fm = FileManager.default
    let roots = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
    var bundles: [URL] = []
    for root in roots {
        for name in ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted() where name.hasSuffix(".app") {
            bundles.append(URL(fileURLWithPath: root).appendingPathComponent(name))
        }
    }
    func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

    for pass in 1...2 {
        var times: [(Double, String)] = []
        for bundle in bundles {
            let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
            let isWrapped = fm.fileExists(atPath: bundle.appendingPathComponent("Wrapper").path)
                || fm.fileExists(atPath: bundle.appendingPathComponent("WrappedBundle").path)
            guard let runtime = AppRuntimeDetector.detect(bundleAt: bundle, isiOSAppOnMac: isWrapped, infoPlist: plist)
            else { continue }
            let start = DispatchTime.now().uptimeNanoseconds
            let components = RuntimeComposition.read(runtime, bundleAt: bundle)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            times.append((ms, bundle.lastPathComponent))
            if pass == 1, !components.isEmpty || runtime != .native {
                log(String(format: "BENCH %8.2f ms  %-10@ %@  %@", ms, runtime.rawValue as NSString,
                           bundle.lastPathComponent as NSString,
                           components.map(\.name).joined(separator: ", ") as NSString))
            }
        }
        let sorted = times.map(\.0).sorted()
        guard !sorted.isEmpty else { continue }
        func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let worst = times.max { $0.0 < $1.0 }!
        log(String(format: "BENCH pass %d: n=%d p50=%.2f ms p95=%.2f ms max=%.2f ms (%@) total=%.0f ms",
                   pass, sorted.count, pct(0.5), pct(0.95), worst.0, worst.1 as NSString, sorted.reduce(0, +)))
    }
}
