import Testing
import Foundation
@testable import DuoUpdaterCore

/// Assemble a throwaway `.app` whose *layout* carries the markers under test.
/// The executable is a stub file — every rule that needs a real Mach-O goes
/// through the injected library reader instead, so these tests never depend on
/// what happens to be installed on the machine running them.
private struct BundleBuilder {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// - Parameters:
    ///   - frameworks: names to create under `Contents/Frameworks`.
    ///   - directories: extra directories relative to `Contents` (`jbr`, `Java`, …).
    ///   - files: extra files relative to `Contents` (`Resources/app.asar`).
    ///   - executableContents: bytes to write into the stub executable, for the one
    ///     rule that reads a binary's contents rather than its header.
    func app(
        _ name: String,
        executable: String? = "Stub",
        executableContents: String = "",
        frameworks: [String] = [],
        directories: [String] = [],
        files: [String] = []
    ) throws -> URL {
        let fm = FileManager.default
        let bundle = root.appendingPathComponent("\(name).app")
        let contents = bundle.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
        for framework in frameworks {
            try fm.createDirectory(
                at: contents.appendingPathComponent("Frameworks/\(framework)"),
                withIntermediateDirectories: true)
        }
        for directory in directories {
            try fm.createDirectory(at: contents.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        for file in files {
            let url = contents.appendingPathComponent(file)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        if let executable {
            let macos = contents.appendingPathComponent("MacOS")
            try fm.createDirectory(at: macos, withIntermediateDirectories: true)
            try Data(executableContents.utf8).write(to: macos.appendingPathComponent(executable))
            // A real Info.plist as well as the dictionary the caller passes in:
            // `RuntimeVersion` finds the executable by reading the bundle's own
            // plist off disk, so a bundle without one has no binary to read.
            try PropertyListSerialization
                .data(fromPropertyList: ["CFBundleExecutable": executable],
                      format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        return bundle
    }

    /// Move a built bundle into another's `Contents/MacOS`, where a wrapper keeps
    /// its interface and where helper processes live too.
    @discardableResult
    func nest(_ inner: URL, in outer: URL) throws -> URL {
        let destination = outer
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(inner.lastPathComponent)
        try FileManager.default.moveItem(at: inner, to: destination)
        return destination
    }
}

/// A library reader that answers the same list for any executable.
private func reader(_ libraries: String...) -> AppRuntimeDetector.LibraryReader {
    { _ in Set(libraries) }
}

/// A library reader whose answer depends on which executable it is handed, for
/// the cases where a bundle and the bundle nested inside it link different things.
private func reader(
    byPath answers: [String: Set<String>], default fallback: Set<String> = []
) -> AppRuntimeDetector.LibraryReader {
    { url in answers.first { url.path.contains($0.key) }?.value ?? fallback }
}

private let appKit = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
private let swiftUI = "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI"
private let webKit = "/System/Library/Frameworks/WebKit.framework/Versions/A/WebKit"
private let catalystUIKit = "/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit"

private func detect(
    _ bundle: URL,
    isiOSAppOnMac: Bool = false,
    plist: [String: Any] = ["CFBundleExecutable": "Stub"],
    libraries: @escaping AppRuntimeDetector.LibraryReader = { _ in [] },
    tauriProof: @escaping AppRuntimeDetector.TauriProof = { _ in false }
) -> AppRuntime? {
    AppRuntimeDetector.detect(
        bundleAt: bundle, isiOSAppOnMac: isiOSAppOnMac, infoPlist: plist,
        linkedLibraries: libraries, carriesTauriCrate: tauriProof)
}

/// The tauri-bundler plist pair — what admits a bundle to the proof, and on its
/// own says only "cargo-bundle".
private func cargoBundlePlist() -> [String: Any] {
    ["CFBundleExecutable": "Stub", "LSRequiresCarbon": true, "CSResourcesFileMapped": true]
}

// MARK: - Layout rules

@Test func detectsElectronFromItsFramework() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Editor", frameworks: ["Electron Framework.framework"])
    #expect(detect(bundle) == .electron)
}

@Test func detectsElectronFromItsPayloadWhenTheFrameworkIsRenamed() throws {
    // QQ ships Electron as `QQNT.framework`, so the framework-name rule alone reads
    // it as a native app — which is what it did until this case was found. Each of
    // these three is on its own enough: the packed archive, electron-builder's
    // update descriptor, and the unpacked payload VS Code and QQ both ship.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    for (name, marker) in [
        ("Packed", "Resources/app.asar"),
        ("Builder", "Resources/app-update.yml"),
        ("Unpacked", "Resources/app/package.json"),
    ] {
        let bundle = try builder.app(name, frameworks: ["QQNT.framework"], files: [marker])
        #expect(detect(bundle) == .electron, "\(marker) should be enough on its own")
    }
}

@Test func aCEFHelperLayoutIsNotReadAsElectron() throws {
    // Spotify's shape: `<name> Helper (Renderer).app` sitting in Contents/Frameworks
    // exactly where Electron puts its own helpers, with no JavaScript payload
    // anywhere. Keying on the helpers would file every CEF app under Electron.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Player", frameworks: [
        "Chromium Embedded Framework.framework", "Player Helper (Renderer).app",
    ])
    #expect(detect(bundle) == .chromium)
}

@Test func detectsFlutter() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Send", frameworks: ["FlutterMacOS.framework"])
    #expect(detect(bundle) == .flutter)
}

@Test func detectsQtAsFrameworksOrDylibs() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let deployed = try builder.app("Frameworked", frameworks: ["QtCore.framework", "QtGui.framework"])
    #expect(detect(deployed) == .qt)
    let dylibs = try builder.app("Dylibbed", frameworks: ["libQt6Core.dylib"])
    #expect(detect(dylibs) == .qt)
}

@Test func qtWinsOverAnEmbeddedChromium() throws {
    // CapCut's shape: Qt draws the windows, CEF is embedded inside it. Reading it
    // as "chromium" would name the passenger rather than the driver.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("CapCutish", frameworks: [
        "QtCore.framework", "Chromium Embedded Framework.framework",
    ])
    #expect(detect(bundle) == .qt)
}

@Test func detectsJavaFromABundledRuntime() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    for directory in ["jbr", "Java", "runtime"] {
        let bundle = try builder.app("IDE-\(directory)", directories: [directory])
        #expect(detect(bundle) == .java, "\(directory) should read as a bundled JVM")
    }
    let legacy = try builder.app("Legacy", executable: "JavaApplicationStub")
    #expect(detect(legacy, plist: ["CFBundleExecutable": "JavaApplicationStub"]) == .java)
}

@Test func detectsANonElectronChromiumShell() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let chrome = try builder.app("Browser", frameworks: ["Google Chrome Framework.framework"])
    #expect(detect(chrome) == .chromium)
    let cef = try builder.app("Embedder", frameworks: ["Chromium Embedded Framework.framework"])
    #expect(detect(cef) == .chromium)
}

@Test func wrappedIOSAppsAreReadFromTheWrapperNotTheLayout() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    // No `Contents/` at all — every layout rule below would look in the wrong place.
    let bundle = builder.root.appendingPathComponent("Wrapped.app")
    try FileManager.default.createDirectory(
        at: bundle.appendingPathComponent("Wrapper"), withIntermediateDirectories: true)
    #expect(detect(bundle, isiOSAppOnMac: true, plist: [:]) == .iOSApp)
}

// MARK: - Load-command rules

@Test func detectsTauriFromCargoBundleMarkersPlusWebKitPlusTheCrate() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Shell")
    #expect(detect(bundle, plist: cargoBundlePlist(), libraries: reader(appKit, webKit),
                   tauriProof: { _ in true }) == .tauri)
}

@Test func cargoBundledAppsWithoutAWebViewAreNativeNotTauri() throws {
    // Warp and Zed carry the same tauri-bundler plist pair and draw their own
    // windows. Without this split they would both be mislabeled Tauri.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Terminal")
    #expect(detect(bundle, plist: cargoBundlePlist(), libraries: reader(appKit),
                   tauriProof: { _ in true }) == .native)
}

@Test func aWebKitLinkAloneIsNotTauri() throws {
    // Plenty of native apps embed a WKWebView (Raycast does). The packager
    // fingerprint has to be there too.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Native")
    #expect(detect(bundle, libraries: reader(appKit, swiftUI, webKit),
                   tauriProof: { _ in true }) == .native)
}

@Test func aCargoBundledWebViewAppWithoutTheTauriCrateIsNative() throws {
    // Longbridge, and the reason the WebKit rule alone was not enough (#206). It
    // draws with GPUI like Zed and embeds a renamed wry fork for web content, so
    // every cheap marker says Tauri and the binary says otherwise.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Broker")
    #expect(detect(bundle, plist: cargoBundlePlist(), libraries: reader(appKit, webKit),
                   tauriProof: { _ in false }) == .native)
}

@Test func theTauriProofIsAskedOnlyAboutCargoBundledWebViewApps() throws {
    // The proof reads a whole executable, so what keeps it affordable during a scan
    // of the entire library is that almost nothing reaches it. If a later edit
    // moved the rule above the cheap filters, every app on the machine would pay —
    // and nothing about the *verdicts* would change, so only this notices.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    final class Counter: @unchecked Sendable { var asked = 0 }
    let counter = Counter()
    let proof: AppRuntimeDetector.TauriProof = { _ in counter.asked += 1; return true }

    // An Electron app, a Qt app, a plain native one, and a cargo-bundled app that
    // links no WebView: four shapes, none of them a candidate.
    _ = detect(try builder.app("Editor", frameworks: ["Electron Framework.framework"]),
               libraries: reader(appKit), tauriProof: proof)
    _ = detect(try builder.app("Viewer", frameworks: ["QtCore.framework"]),
               libraries: reader(appKit), tauriProof: proof)
    _ = detect(try builder.app("Plain"), libraries: reader(appKit, swiftUI), tauriProof: proof)
    _ = detect(try builder.app("Terminal"), plist: cargoBundlePlist(),
               libraries: reader(appKit), tauriProof: proof)
    #expect(counter.asked == 0)

    _ = detect(try builder.app("Shell"), plist: cargoBundlePlist(),
               libraries: reader(appKit, webKit), tauriProof: proof)
    #expect(counter.asked == 1)
}

// MARK: - The proof, through the real reader

@Test func theRealProofReadsTheCratePathOutOfTheBinary() throws {
    // End to end through `RuntimeVersion.carriesTauriCrate`, the closure production
    // actually passes — the injected proofs above would keep passing if it broke.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app(
        "Shell",
        executableContents: "junk/Users/x/.cargo/registry/src/index/tauri-2.11.1/src/lib.rsmore")
    #expect(AppRuntimeDetector.detect(
        bundleAt: bundle, isiOSAppOnMac: false, infoPlist: cargoBundlePlist(),
        linkedLibraries: reader(appKit, webKit)) == .tauri)
}

@Test(.enabled(if: geteuid() != 0, "chmod 000 does not stop root, and these turn on a read failing"))
func theProofIsPaidForOncePerBinaryNotOncePerScan() throws {
    // What makes the walk affordable on a scheduled, library-wide scan is that the
    // second scan does not repeat it. Nothing about the *verdicts* would change if
    // the memoization were lost — every scan would simply start reading hundreds of
    // megabytes again — so this is the only thing that would notice.
    //
    // Making the binary unreadable between the two calls is how the test tells a
    // remembered answer from a fresh one: `stat` still succeeds, so the key is
    // unchanged, while a re-read would fail and the app would come back native.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app(
        "Shell", executableContents: "registry/src/index/tauri-2.11.1/src/lib.rs")
    let verdict = { AppRuntimeDetector.detect(
        bundleAt: bundle, isiOSAppOnMac: false, infoPlist: cargoBundlePlist(),
        linkedLibraries: reader(appKit, webKit)) }
    #expect(verdict() == .tauri)

    let executable = bundle.appendingPathComponent("Contents/MacOS/Stub")
    try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                          ofItemAtPath: executable.path)
    #expect(verdict() == .tauri, "the walk is not repeated for a binary that has not changed")
}

@Test func theRealProofRejectsAWryOnlyBinary() throws {
    // The same shape with Longbridge's contents: wry is there, the framework crate
    // is not. `tauri-runtime-wry-2.11.4` is included deliberately — it contains the
    // needle as a substring and must not be read as the crate.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app(
        "Broker",
        executableContents: "registry/src/index/lb-wry-0.53.3/src/lib.rs "
            + "and tauri-runtime-wry-2.11.4/src/lib.rs")
    #expect(AppRuntimeDetector.detect(
        bundleAt: bundle, isiOSAppOnMac: false, infoPlist: cargoBundlePlist(),
        linkedLibraries: reader(appKit, webKit)) == .native)
}

@Test func detectsCatalyst() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Ported")
    #expect(detect(bundle, libraries: reader(catalystUIKit, appKit)) == .catalyst)
}

@Test func detectsNativeFromEitherUIFramework() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Menu")
    #expect(detect(bundle, libraries: reader(appKit)) == .native)
    #expect(detect(bundle, libraries: reader(swiftUI)) == .native)
}

// MARK: - What the binary links

@Test func namesTheFrameworksItFinds() {
    #expect(AppRuntimeDetector.frameworks(in: [appKit, swiftUI]).names == ["AppKit", "SwiftUI"])
    #expect(AppRuntimeDetector.frameworks(in: [catalystUIKit]).names == ["UIKit"])
    // The Swift runtime is linked by most of these apps and is not a framework;
    // the set holds frameworks, so it is not in here.
    #expect(AppRuntimeDetector.frameworks(in: ["/usr/lib/swift/libswiftCore.dylib"]).names == [])
    #expect(AppRuntimeDetector.frameworks(in: ["/usr/lib/libSystem.B.dylib"]).names == [])
}

@Test func theNameOrderIsFixed() {
    // A set has no order; a row that reshuffled its own description between
    // launches would look like it had changed its mind about the app.
    let all = AppRuntimeDetector.frameworks(in: [swiftUI, appKit, catalystUIKit])
    #expect(all.names == ["AppKit", "SwiftUI", "UIKit"])
}

@Test func swiftUIWithoutAppKitIsStillNative() throws {
    // Not hypothetical: a demo app built for this question links SwiftUI and no
    // AppKit at all, which is why the runtime stays one label and the frameworks
    // stay a set. (It used to add that no shipping app on the author's machine
    // did — true when written, uncheckable by anyone else, and the demo app is
    // the evidence that matters either way.)
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Pure")
    let reading = AppRuntimeDetector.read(
        bundleAt: bundle, isiOSAppOnMac: false,
        infoPlist: ["CFBundleExecutable": "Stub"],
        linkedLibraries: reader(swiftUI, "/usr/lib/swift/libswiftCore.dylib"))
    #expect(reading.runtime == .native)
    #expect(reading.frameworks.names == ["SwiftUI"])
}

@Test func aCatalystReadingCarriesUIKit() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Ported")
    let reading = AppRuntimeDetector.read(
        bundleAt: bundle, isiOSAppOnMac: false,
        infoPlist: ["CFBundleExecutable": "Stub"],
        linkedLibraries: reader(catalystUIKit, appKit))
    #expect(reading.runtime == .catalyst)
    #expect(reading.frameworks.contains(.uiKit))
}

@Test func aBundleSettledByItsLayoutStillReportsWhatItLinks() throws {
    // Electron is decided without looking at the binary, but its shell links AppKit
    // like anything else — and the read happens once, so the answer is there.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Editor", frameworks: ["Electron Framework.framework"])
    let reading = AppRuntimeDetector.read(
        bundleAt: bundle, isiOSAppOnMac: false,
        infoPlist: ["CFBundleExecutable": "Stub"], linkedLibraries: reader(appKit))
    #expect(reading.runtime == .electron)
    #expect(reading.frameworks == .appKit)
}

@Test func aWrappedIOSAppReportsNoFrameworksRatherThanGuessing() throws {
    // Its executable is inside the wrapper, not where every other bundle keeps
    // one, so nothing was read and nothing is claimed.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = builder.root.appendingPathComponent("Wrapped.app")
    try FileManager.default.createDirectory(
        at: bundle.appendingPathComponent("Wrapper"), withIntermediateDirectories: true)
    let reading = AppRuntimeDetector.read(bundleAt: bundle, isiOSAppOnMac: true, infoPlist: [:])
    #expect(reading.runtime == .iOSApp)
    #expect(reading.frameworks.isEmpty)
}

// MARK: - A wrapper whose interface is a nested bundle

@Test func aWrapperThatShipsNothingIsReadFromTheOneBundleNestedInIt() throws {
    // Docker's shape (#208): the outer bundle declares a daemon that links AppKit,
    // ships no `Contents/Frameworks` at all, and keeps the GUI one level down. Every
    // rule is correct about the launcher and none of them is looking at the app.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let wrapper = try builder.app("Docker", executable: "com.docker.backend")
    // Docker's outer bundle has no `Contents/Frameworks` at all, which is not the
    // same thing as an empty one — the rule has to accept both, and only this test
    // constructs the shape that actually ships.
    try FileManager.default.removeItem(at: wrapper.appendingPathComponent("Contents/Frameworks"))
    let gui = try builder.app("Docker Desktop", frameworks: ["Electron Framework.framework"])
    try builder.nest(gui, in: wrapper)
    #expect(detect(wrapper, plist: ["CFBundleExecutable": "com.docker.backend"],
                   libraries: reader(appKit)) == .electron)
}

@Test func aWrapperThatShipsFrameworksOfItsOwnIsNotReadFromANestedBundle() throws {
    // WeChat's shape, and the live near-miss: `/Applications/WeChat.app` nests
    // exactly one `.app`, and that one ships `WeChatAppEx Framework.framework`,
    // which satisfies the Chromium rule. Conditions 2 and 3 both pass. Its own 28
    // frameworks are the only thing keeping the row from being labelled off a
    // web-view subprocess.
    //
    // The host ships `Sparkle.framework` deliberately: it has to fall through every
    // rule above the nested one, or `read` returns before reaching the condition
    // under test and the test proves nothing. With `frameworkNames.isEmpty` deleted
    // from the rule, this is what fails.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let host = try builder.app("WeChatish", frameworks: ["Sparkle.framework"])
    let subprocess = try builder.app("AppEx", frameworks: ["AppEx Framework.framework"])
    try builder.nest(subprocess, in: host)
    #expect(detect(host, libraries: reader(appKit)) == .native)
    #expect(AppRuntimeDetector.interfaceBundle(at: host) == host)
}

@Test func severalNestedBundlesReadAsHelpersRatherThanAsAnInterface() throws {
    // Parallels ships three, QQ four, WeChat two. One nested bundle is not proof of
    // an interface, but a crowd of them is proof of the opposite.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let wrapper = try builder.app("Wrapper")
    for name in ["Helper One", "Helper Two"] {
        try builder.nest(try builder.app(name, frameworks: ["Electron Framework.framework"]),
                         in: wrapper)
    }
    #expect(detect(wrapper, libraries: reader(appKit)) == .native)
}

@Test func aNestedBundleThatProvesNothingLeavesTheLabelWhereItWas() throws {
    // OrbStack's `scli.app` is a command-line helper: it would pass the other two
    // conditions and has nothing to say about itself. `.native` and `.catalyst` are
    // read off load commands, which a helper carries exactly like an interface, so
    // neither is adopted — only a runtime the nested bundle had to *ship*.
    //
    // The two bundles have to link *different* things or this cannot fail: with one
    // reader answering the same list for both, adopting the nested reading and
    // declining it produce the same verdict, and the guard could be deleted for
    // free. Here the outer is Catalyst and the nested is plain native, so an
    // adopted reading changes the answer and the assertion sees it.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let wrapper = try builder.app("Tool")
    try builder.nest(try builder.app("scli"), in: wrapper)
    #expect(detect(wrapper, libraries: reader(byPath: [
        "scli.app": [appKit],
        "Tool.app": [catalystUIKit, appKit],
    ])) == .catalyst)

    // And the other way round, so neither verdict is adopted in either direction.
    let ported = try builder.app("Ported")
    try builder.nest(try builder.app("agent"), in: ported)
    #expect(detect(ported, libraries: reader(byPath: [
        "agent.app": [catalystUIKit, appKit],
        "Ported.app": [appKit],
    ])) == .native)

    let silent = try builder.app("Mystery")
    try builder.nest(try builder.app("mystery-cli"), in: silent)
    #expect(detect(silent, libraries: reader("/usr/lib/libSystem.B.dylib")) == nil)
}

@Test func theNestedReadingIsAdoptedWholeIncludingWhatItLinks() throws {
    // Both halves of the reading have to come from the same bundle, because
    // `InstalledApp.linkedFrameworks` is documented as the link list of whichever
    // executable `runtime` describes. Docker's are two different binaries: its
    // launcher is a Go daemon linking AppKit, its Electron stub links only the
    // framework. `RuntimeTag.linkedLine` draws this only for `.native` and
    // `.catalyst`, so nothing renders it for Docker either way — the contract is
    // what is being kept here, ahead of the first consumer that relies on it.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let wrapper = try builder.app("Docker", executable: "com.docker.backend")
    try builder.nest(try builder.app("Docker Desktop", frameworks: ["Electron Framework.framework"]),
                     in: wrapper)
    let reading = AppRuntimeDetector.read(
        bundleAt: wrapper, isiOSAppOnMac: false,
        infoPlist: ["CFBundleExecutable": "com.docker.backend"],
        linkedLibraries: reader(byPath: [
            "com.docker.backend": [appKit, swiftUI],
            "Docker Desktop.app": [],
        ]))
    #expect(reading.runtime == .electron)
    #expect(reading.frameworks.names == [])
}

@Test func theDescentStopsAfterOneLevel() throws {
    // A wrapper inside a wrapper is not a shape anything ships, and the guard that
    // keeps it out is the same one that makes a bundle nesting a link to itself
    // terminate. Nothing about the verdicts of real apps would change if it were
    // lost, so only this notices.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let inner = try builder.app("Inner")
    try builder.nest(try builder.app("Deep", frameworks: ["Electron Framework.framework"]),
                     in: inner)
    let outer = try builder.app("Outer")
    try builder.nest(inner, in: outer)
    #expect(detect(outer, libraries: reader(appKit)) == .native)
}

@Test func theRuntimeVersionIsReadFromTheSameBundleAsTheRuntimeName() throws {
    // Otherwise the row says Electron and the popover has no version to show, out of
    // a bundle that plainly carries one — `RuntimeVersion` would be reading a
    // `Contents/Frameworks` that does not exist. Docker's real answer is 42.5.0.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let wrapper = try builder.app("Docker", executable: "com.docker.backend")
    let gui = try builder.app("Docker Desktop", frameworks: ["Electron Framework.framework"])
    let framework = gui.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
    try FileManager.default.createDirectory(
        at: framework.appendingPathComponent("Resources"), withIntermediateDirectories: true)
    try PropertyListSerialization
        .data(fromPropertyList: ["CFBundleIdentifier": "com.github.Electron.framework",
                                 "CFBundleVersion": "42.5.0"],
              format: .xml, options: 0)
        .write(to: framework.appendingPathComponent("Resources/Info.plist"))
    try builder.nest(gui, in: wrapper)

    #expect(AppRuntimeDetector.interfaceBundle(at: wrapper).lastPathComponent
            == "Docker Desktop.app")
    #expect(RuntimeVersion.read(.electron, bundleAt: wrapper, scanningBinaries: true) == "42.5.0")
}

@Test func anOrdinaryBundleIsItsOwnInterface() throws {
    // The redirection has to be invisible to the 209 bundles in 210 that are not
    // wrappers — including the ones that do nest a helper.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let plain = try builder.app("Plain", frameworks: ["Electron Framework.framework"])
    #expect(AppRuntimeDetector.interfaceBundle(at: plain) == plain)
    let host = try builder.app("Suite", frameworks: ["QtCore.framework"])
    try builder.nest(try builder.app("Helper", frameworks: ["Electron Framework.framework"]),
                     in: host)
    #expect(AppRuntimeDetector.interfaceBundle(at: host) == host)
}

@Test func aPlainFileNamedLikeABundleDoesNotCountAsOne() throws {
    // `Contents/MacOS` is mostly executables. A file called `uninstall.app` beside
    // the real interface would take the tally to two and turn the rule off, and
    // nothing anywhere would say why — the app would simply keep the wrong label.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let wrapper = try builder.app("Docker", executable: "com.docker.backend")
    try builder.nest(try builder.app("Docker Desktop", frameworks: ["Electron Framework.framework"]),
                     in: wrapper)
    try Data().write(to: wrapper.appendingPathComponent("Contents/MacOS/uninstall.app"))
    #expect(detect(wrapper, plist: ["CFBundleExecutable": "com.docker.backend"],
                   libraries: reader(appKit)) == .electron)
}

@Test func aTauriVersionIsNeverReadFromANestedBundle() throws {
    // Tauri is compiled into the executable rather than shipped beside it, so a
    // crate path found one level down is a fact about that binary and nothing else.
    // Following the redirect would let a nested bundle lend its identity to its
    // wrapper — the error the rest of this rule exists to prevent.
    //
    // It is also the edge that would close a cycle: `carriesTauriCrate` is
    // `RuntimeVersion.read`, the detector calls it, and `interfaceBundle` calls the
    // detector. That consequence is deliberately not tested by timing a bundle
    // whose `Contents/MacOS` links to itself — the re-entrant call goes through the
    // production proof, so a counter cannot see it, and the only signal left is a
    // clock. The exemption below is the thing that has to hold; the loop follows
    // from it. Measured while it did not hold: 0.38s of CPU against 0.02s, ~26
    // walks of a 60 MB binary, terminating only when the path outgrew PATH_MAX.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let wrapper = try builder.app("Wrapper")
    let inner = try builder.app(
        "Inner", executableContents: "registry/src/index/tauri-2.11.5/src/lib.rs",
        frameworks: ["Electron Framework.framework"])
    try builder.nest(inner, in: wrapper)
    #expect(AppRuntimeDetector.interfaceBundle(at: wrapper).lastPathComponent == "Inner.app")
    #expect(RuntimeVersion.read(.tauri, bundleAt: wrapper, scanningBinaries: true) == nil)
}

@Test(.enabled(if: geteuid() != 0, "chmod 000 does not stop root, and this turns on a read failing"))
func aFrameworksDirectoryThatCannotBeListedIsNotReadAsAnAbsentOne() throws {
    // Everywhere else in this file `Contents/Frameworks` is read as
    // `(try? …) ?? []`, and a directory that cannot be listed simply fails to match
    // a framework name — harmless. For this rule the same collapse would flip the
    // answer the other way and hand the label to a subprocess, so the absence has
    // to be established rather than assumed.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let host = try builder.app("Guarded")
    try builder.nest(try builder.app("Inner", frameworks: ["Electron Framework.framework"]),
                     in: host)
    let frameworks = host.appendingPathComponent("Contents/Frameworks")
    try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                          ofItemAtPath: frameworks.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: frameworks.path)
    }
    #expect(detect(host, libraries: reader(appKit)) == .native)
}

// MARK: - A launcher stub in front of the payload

/// Write another Mach-O stub into a built bundle's `Contents/MacOS`, where the
/// payload beside a launcher lives — and where helpers live too.
private func binary(_ name: String, in bundle: URL) throws -> URL {
    let url = bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
    try Data().write(to: url)
    return url
}

@Test func aLauncherStubIsAnsweredByTheBinaryNamedAfterTheBundle() throws {
    // Audacity's shape: `CFBundleExecutable` is `Wrapper`, a launcher that links
    // libSystem and nothing else and then executes `Contents/MacOS/Audacity`,
    // which is the one linking AppKit. Ships 144 loose dylibs and not one
    // `.framework`, so every layout rule above passes over it too.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Audacity", executable: "Wrapper")
    _ = try binary("Audacity", in: bundle)
    let reading = AppRuntimeDetector.read(
        bundleAt: bundle, isiOSAppOnMac: false,
        infoPlist: ["CFBundleExecutable": "Wrapper"],
        linkedLibraries: reader(byPath: ["MacOS/Wrapper": ["/usr/lib/libSystem.B.dylib"],
                                        "MacOS/Audacity": [appKit]]),
        carriesTauriCrate: { _ in false })
    #expect(reading.runtime == .native)
    // The frameworks travel with the verdict: they describe the binary that
    // answered, not the stub that did not.
    #expect(reading.frameworks.names == ["AppKit"])
}

@Test func theRetryReachesCatalystToo() throws {
    // The payload links both, as a Catalyst binary really does, so this pins the
    // order the retry applies the rules in as well as the fact that it reaches
    // them — `.native` would be the answer if the two were swapped. The frameworks
    // are checked through `read` rather than `detect`, since a retry that returned
    // the *stub's* empty set alongside the payload's verdict would pass a check on
    // the runtime alone.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Padded", executable: "Wrapper")
    _ = try binary("Padded", in: bundle)
    let reading = AppRuntimeDetector.read(
        bundleAt: bundle, isiOSAppOnMac: false,
        infoPlist: ["CFBundleExecutable": "Wrapper"],
        linkedLibraries: reader(byPath: ["MacOS/Wrapper": ["/usr/lib/libSystem.B.dylib"],
                                        "MacOS/Padded": [catalystUIKit, appKit]]),
        carriesTauriCrate: { _ in false })
    #expect(reading.runtime == .catalyst)
    #expect(reading.frameworks.names == ["AppKit", "UIKit"])
}

@Test func aHelperBesideTheStubIsNotAdopted() throws {
    // Only the binary named after the bundle. `Contents/MacOS` is otherwise where
    // subprocesses and command-line tools live — LibreOffice keeps ten of them
    // beside `soffice` — and any of them would hand a helper's load commands to
    // the app that spawns it.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Suite", executable: "soffice")
    _ = try binary("gengal", in: bundle)
    #expect(detect(bundle, plist: ["CFBundleExecutable": "soffice"],
                   libraries: reader(byPath: ["MacOS/soffice": ["/usr/lib/libSystem.B.dylib"],
                                              "MacOS/gengal": [appKit]])) == nil)
}

@Test func aDirectoryNamedAfterTheBundleIsNotABinary() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Studio", executable: "Wrapper")
    try FileManager.default.createDirectory(
        at: bundle.appendingPathComponent("Contents/MacOS/Studio"), withIntermediateDirectories: true)
    #expect(detect(bundle, plist: ["CFBundleExecutable": "Wrapper"],
                   libraries: reader(byPath: ["MacOS/Wrapper": ["/usr/lib/libSystem.B.dylib"]],
                                     default: [appKit])) == nil)
}

@Test func theTauriProofIsNeverAskedAboutTheRetry() throws {
    // The retry runs the link rules and stops there: the proof is a whole-binary
    // byte search, and a bundle that reached this point has already paid for one
    // read that told it nothing. A Tauri app behind a launcher stub therefore
    // reads as native, which is the direction this file fails in everywhere else.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Shelled", executable: "Wrapper")
    _ = try binary("Shelled", in: bundle)
    var proofAsked = 0
    let runtime = detect(
        bundle,
        plist: ["CFBundleExecutable": "Wrapper", "LSRequiresCarbon": true, "CSResourcesFileMapped": true],
        libraries: reader(byPath: ["MacOS/Wrapper": ["/usr/lib/libSystem.B.dylib"],
                                   "MacOS/Shelled": [appKit, webKit]]),
        tauriProof: { _ in proofAsked += 1; return true })
    #expect(runtime == .native)
    #expect(proofAsked == 0)
}

@Test func atMostOneExtraBinaryIsEverRead() throws {
    // The cost of the retry, pinned. A bundle that reaches a verdict pays nothing,
    // the stub shape pays exactly one more read, and a bundle whose declared
    // executable *is* the one named after it is never read twice — that last one
    // is the whole population of unlabelled apps, so a missing path guard would
    // double the reads for every app the retry cannot help.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    var reads = 0
    func counting(_ answers: [String: Set<String>]) -> AppRuntimeDetector.LibraryReader {
        { url in reads += 1; return answers.first { url.path.contains($0.key) }?.value ?? [] }
    }

    let plain = try builder.app("Native", executable: "Native")
    #expect(detect(plain, plist: ["CFBundleExecutable": "Native"],
                   libraries: counting(["MacOS/Native": [appKit]])) == .native)
    #expect(reads == 1)

    reads = 0
    let stubbed = try builder.app("Wrapped", executable: "Wrapper")
    _ = try binary("Wrapped", in: stubbed)
    #expect(detect(stubbed, plist: ["CFBundleExecutable": "Wrapper"],
                   libraries: counting(["MacOS/Wrapped": [appKit]])) == .native)
    #expect(reads == 2)

    // Case, not spelling: on a case-insensitive volume — the default for both
    // `/Applications` and the directory these fixtures are built in — `cased` and
    // `Cased` are one file, and comparing the two paths as strings says they are
    // two. The population this matters for is cargo-bundled apps, which routinely
    // ship a lowercase `CFBundleExecutable` beside a capitalized bundle.
    reads = 0
    let cased = try builder.app("Cased", executable: "cased")
    #expect(detect(cased, plist: ["CFBundleExecutable": "cased"],
                   libraries: counting([:])) == nil)
    #expect(reads == 1)

    // A second name for the same file, which `fileExists` follows and a path
    // comparison does not see. Real bundles carry these — LibreOffice ships three
    // in `Contents/MacOS`.
    reads = 0
    let linked = try builder.app("Linked", executable: "Stub")
    try FileManager.default.createSymbolicLink(
        at: linked.appendingPathComponent("Contents/MacOS/Linked"),
        withDestinationURL: linked.appendingPathComponent("Contents/MacOS/Stub"))
    #expect(detect(linked, libraries: counting([:])) == nil)
    #expect(reads == 1)

    reads = 0
    let mystery = try builder.app("Mystery", executable: "Mystery")
    #expect(detect(mystery, plist: ["CFBundleExecutable": "Mystery"],
                   libraries: counting([:])) == nil)
    #expect(reads == 1)
}

// MARK: - Failing closed

@Test func unrecognizedBundlesReportNothingRatherThanNative() throws {
    // A launcher shell script, a Python app, a C++ app linking neither AppKit nor a
    // bundled toolkit. "No badge" is the honest answer; defaulting to `.native`
    // would put a confident wrong label on every one of them.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Mystery")
    #expect(detect(bundle, libraries: reader("/usr/lib/libSystem.B.dylib")) == nil)
}

@Test func anUnreadableExecutableIsNotGuessedAt() throws {
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Broken")
    #expect(detect(bundle, libraries: { _ in nil }) == nil)
    let headless = try builder.app("Headless", executable: nil)
    #expect(detect(headless, libraries: reader(appKit)) == nil)
}

// MARK: - Mach-O reader

@Test func readsLoadCommandsFromARealBinary() throws {
    // /bin/ls is present on every macOS and links libSystem — a fixed fact that
    // exercises the whole header walk rather than a synthesized approximation.
    let libraries = MachOImports.linkedLibraries(at: URL(fileURLWithPath: "/bin/ls"))
    let names = try #require(libraries)
    #expect(names.contains { $0.contains("libSystem") })
}

@Test func findsTheArm64SliceOfAUniversalBinary() throws {
    // /bin/ls ships universal, so its arm64e slice is a real thin image to build a
    // synthetic fat file around. The first slice here is labeled x86_64 and is
    // deliberately garbage: if the reader took the first slice instead of walking
    // the table for arm64, it would come back nil rather than with ls's imports.
    let fatFile = try Data(contentsOf: URL(fileURLWithPath: "/bin/ls"))
    func be32(_ offset: Int) -> Int {
        Int(fatFile[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
    #expect(be32(0) == 0xcafe_babe, "/bin/ls is expected to be a universal binary")
    var thin: Data?
    for index in 0..<be32(4) {
        let entry = 8 + index * 20
        if be32(entry) == 0x0100_000c {   // CPU_TYPE_ARM64, subtype arm64e included
            thin = fatFile[be32(entry + 8)..<(be32(entry + 8) + be32(entry + 12))]
        }
    }
    let slice = try #require(thin, "no arm64 slice in /bin/ls")

    let alignment = 0x4000
    let decoy = Data(count: alignment)
    let firstOffset = alignment
    let secondOffset = alignment * (1 + (decoy.count + alignment - 1) / alignment) + alignment

    var fat = Data()
    func appendBE(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { fat.append(contentsOf: $0) } }
    appendBE(0xcafe_babe)                      // FAT_MAGIC
    appendBE(2)                                // nfat_arch
    for (cpu, offset, size) in [
        (UInt32(0x0100_0007), firstOffset, decoy.count),     // x86_64 — garbage
        (UInt32(0x0100_000c), secondOffset, slice.count),    // arm64 — the real one
    ] {
        appendBE(cpu)
        appendBE(0)                            // cpusubtype
        appendBE(UInt32(offset))
        appendBE(UInt32(size))
        appendBE(14)                           // align, 2^14
    }
    fat.append(Data(count: firstOffset - fat.count))
    fat.append(decoy)
    fat.append(Data(count: secondOffset - fat.count))
    fat.append(slice)

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fat-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fatURL = directory.appendingPathComponent("universal")
    let thinURL = directory.appendingPathComponent("thin")
    try fat.write(to: fatURL)
    try slice.write(to: thinURL)

    let fromThin = try #require(MachOImports.linkedLibraries(at: thinURL))
    #expect(fromThin.contains { $0.contains("libSystem") })
    #expect(MachOImports.linkedLibraries(at: fatURL) == fromThin)
}

@Test func refusesFilesThatAreNotMachO() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("junk-\(UUID().uuidString)")
    try Data("#!/bin/sh\nexec something\n".utf8).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(MachOImports.linkedLibraries(at: tmp) == nil)
    #expect(MachOImports.linkedLibraries(at: URL(fileURLWithPath: "/nope/missing")) == nil)
}

@Test func eachLoadedDylibCarriesTheVersionTheLinkerRecorded() throws {
    // The packed `current_version` is where a bundled toolkit's version survives
    // when it ships as a bare dylib with no Info.plist — Qt's case. /bin/ls links
    // libSystem, whose recorded version is a real three-part number.
    let dylibs = try #require(MachOImports.loadedDylibs(at: URL(fileURLWithPath: "/bin/ls")))
    let libSystem = try #require(dylibs.first { $0.key.contains("libSystem") })
    let parts = libSystem.value.split(separator: ".")
    #expect(parts.count == 3, "expected a packed X.Y.Z, got \(libSystem.value)")
    #expect(parts.allSatisfy { Int($0) != nil })
    #expect(libSystem.value != "0.0.0")
}

@Test func frameworkMatchingIgnoresTheInstallNameSpelling() {
    let libraries: Set<String> = [
        "@rpath/Sparkle.framework/Versions/B/Sparkle",
        "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
    ]
    #expect(MachOImports.links(libraries, framework: "Sparkle"))
    #expect(MachOImports.links(libraries, framework: "AppKit"))
    // Substring, not suffix: "Kit" must not match "AppKit".
    #expect(!MachOImports.links(libraries, framework: "Kit"))
}
