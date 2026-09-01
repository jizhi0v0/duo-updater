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
}

/// A library reader that answers the same list for any executable.
private func reader(_ libraries: String...) -> AppRuntimeDetector.LibraryReader {
    { _ in Set(libraries) }
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
    tauriProof: @escaping AppRuntimeDetector.TauriProof = { _, _ in false }
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
                   tauriProof: { _, _ in true }) == .tauri)
}

@Test func cargoBundledAppsWithoutAWebViewAreNativeNotTauri() throws {
    // Warp and Zed carry the same tauri-bundler plist pair and draw their own
    // windows. Without this split they would both be mislabeled Tauri.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Terminal")
    #expect(detect(bundle, plist: cargoBundlePlist(), libraries: reader(appKit),
                   tauriProof: { _, _ in true }) == .native)
}

@Test func aWebKitLinkAloneIsNotTauri() throws {
    // Plenty of native apps embed a WKWebView (Raycast does). The packager
    // fingerprint has to be there too.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Native")
    #expect(detect(bundle, libraries: reader(appKit, swiftUI, webKit),
                   tauriProof: { _, _ in true }) == .native)
}

@Test func aCargoBundledWebViewAppWithoutTheTauriCrateIsNative() throws {
    // Longbridge, and the reason the WebKit rule alone was not enough (#206). It
    // draws with GPUI like Zed and embeds a renamed wry fork for web content, so
    // every cheap marker says Tauri and the binary says otherwise.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    let bundle = try builder.app("Broker")
    #expect(detect(bundle, plist: cargoBundlePlist(), libraries: reader(appKit, webKit),
                   tauriProof: { _, _ in false }) == .native)
}

@Test func theTauriProofIsAskedOnlyAboutCargoBundledWebViewApps() throws {
    // The proof reads a whole executable, so what keeps it affordable during a scan
    // of the entire library is that almost nothing reaches it. If a later edit
    // moved the rule above the cheap filters, every app on the machine would pay —
    // and nothing about the *verdicts* would change, so only this notices.
    let builder = try BundleBuilder(); defer { builder.cleanUp() }
    final class Counter: @unchecked Sendable { var asked = 0 }
    let counter = Counter()
    let proof: AppRuntimeDetector.TauriProof = { _, _ in counter.asked += 1; return true }

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
    // AppKit at all. No *shipping* app on the development machine did — 0 of 77 —
    // which is why the runtime stays one label and the frameworks stay a set.
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
