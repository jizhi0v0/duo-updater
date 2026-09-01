import Testing
import Foundation
@testable import DuoUpdaterCore

private struct VersionBundle {
    let root: URL
    let bundle: URL

    init(_ name: String) throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("version-\(UUID().uuidString)")
        bundle = root.appendingPathComponent("\(name).app")
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// A framework with its own Info.plist, the way a real one is laid out.
    func framework(_ name: String, plist: [String: Any]) throws {
        let resources = bundle
            .appendingPathComponent("Contents/Frameworks/\(name)/Versions/A/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: resources.appendingPathComponent("Info.plist"))
    }

    func file(_ path: String, _ contents: String) throws {
        let url = bundle.appendingPathComponent("Contents/\(path)")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes the executable *and* the Info.plist that names it, the way a bundle
    /// the reader has to find its way around actually looks.
    func executable(_ name: String, containing text: String) throws {
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: macos.appendingPathComponent(name))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": name], format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    }

    func version(_ runtime: AppRuntime, scanning: Bool = true) -> String? {
        // A fresh key per bundle — each test builds its own temp directory, so the
        // path already makes the cache entry unique.
        RuntimeVersion.read(runtime, bundleAt: bundle, appVersion: "1.0", scanningBinaries: scanning)
    }
}

@Test func electronIsFoundByBundleIdEvenWhenTheFrameworkIsRenamed() throws {
    // QQ's shape: the framework is called QQNT and still declares Electron's id.
    let b = try VersionBundle("QQ"); defer { b.cleanUp() }
    try b.framework("QQNT.framework", plist: [
        "CFBundleIdentifier": "com.github.Electron.framework",
        "CFBundleVersion": "40.0.0",
    ])
    #expect(b.version(.electron) == "40.0.0")
}

@Test func aResignedElectronFrameworkIsReadFromItsBinaryNotItsPlist() throws {
    // Kiro's shape: electron-builder re-signed the framework under the app's own
    // prefix, and rewrote the version to the app's while it was there. Trusting the
    // plist here reports 1.0.411 — Kiro's version — for an app running Electron 39.
    let b = try VersionBundle("Kiro"); defer { b.cleanUp() }
    try b.framework("Electron Framework.framework", plist: [
        "CFBundleIdentifier": "dev.kiro.desktop.com.github.Electron.framework",
        "CFBundleVersion": "1.0.411",
    ])
    let binary = b.bundle.appendingPathComponent(
        "Contents/Frameworks/Electron Framework.framework/Versions/A/Electron Framework")
    try Data("ua Chrome/136.0.0.0 Electron/39.6.0 Safari/537.36".utf8).write(to: binary)
    #expect(b.version(.electron) == "39.6.0")
}

@Test func aResignedFrameworkIsNotScannedDuringALibraryWidePass() throws {
    // Its own bundle, because a remembered answer is deliberately handed back even
    // to a caller that forbade scanning — free is free, and that is what would let
    // a later scan pick up a version the detail view already paid for.
    let b = try VersionBundle("Kiro"); defer { b.cleanUp() }
    try b.framework("Electron Framework.framework", plist: [
        "CFBundleIdentifier": "dev.kiro.desktop.com.github.Electron.framework",
        "CFBundleVersion": "1.0.411",
    ])
    let binary = b.bundle.appendingPathComponent(
        "Contents/Frameworks/Electron Framework.framework/Versions/A/Electron Framework")
    try Data("ua Electron/39.6.0".utf8).write(to: binary)
    #expect(b.version(.electron, scanning: false) == nil)
}

@Test func aFrameworkThatIsNotElectronIsNotMistakenForIt() throws {
    let b = try VersionBundle("Other"); defer { b.cleanUp() }
    try b.framework("Sparkle.framework", plist: [
        "CFBundleIdentifier": "org.sparkle-project.Sparkle",
        "CFBundleVersion": "2.6.4",
    ])
    #expect(b.version(.electron) == nil)
}

@Test func qtComesFromQtCoresMarketingVersion() throws {
    let b = try VersionBundle("Editor"); defer { b.cleanUp() }
    try b.framework("QtCore.framework", plist: [
        "CFBundleIdentifier": "org.qt-project.QtCore",
        "CFBundleShortVersionString": "6.2",
        "CFBundleVersion": "6.2.4",
    ])
    #expect(b.version(.qt) == "6.2")
}

@Test func javaComesFromTheBundledRuntimesReleaseFile() throws {
    let jetBrains = try VersionBundle("IDE"); defer { jetBrains.cleanUp() }
    try jetBrains.file("jbr/Contents/Home/release",
                       "JAVA_VERSION=\"21.0.8\"\nOS_ARCH=\"aarch64\"\n")
    #expect(jetBrains.version(.java) == "21.0.8")

    // `jpackage` puts the same file under `runtime` instead.
    let packaged = try VersionBundle("Packaged"); defer { packaged.cleanUp() }
    try packaged.file("runtime/Contents/Home/release", "JAVA_VERSION=\"17.0.11\"\n")
    #expect(packaged.version(.java) == "17.0.11")
}

@Test func tauriComesFromTheCratePathBakedIntoTheBinary() throws {
    let b = try VersionBundle("Shell"); defer { b.cleanUp() }
    try b.executable("Shell", containing:
        "junk/Users/x/.cargo/registry/src/index/tauri-2.11.5/src/lib.rsmore junk")
    #expect(b.version(.tauri) == "2.11.5")
}

@Test func aWryOnlyAppIsNotGivenATauriVersion() throws {
    // Longbridge's shape: it matches the Tauri fingerprint but carries wry alone.
    // A nil here is the honest answer, and it is what keeps the detail from
    // asserting a version for an app that has no Tauri in it.
    let b = try VersionBundle("Trading"); defer { b.cleanUp() }
    try b.executable("Trading", containing:
        "registry/src/index/wry-0.53.3/src/lib.rs and tauri-runtime-wry-2.11.4/src/lib.rs")
    #expect(b.version(.tauri) == nil)
}

@Test func theTauriScanIsSkippedWhenScanningIsNotAllowed() throws {
    // The scan walks the whole executable, so a full library scan must never do it.
    let b = try VersionBundle("Shell"); defer { b.cleanUp() }
    try b.executable("Shell", containing: "tauri-2.11.5/src/lib.rs")
    #expect(b.version(.tauri, scanning: false) == nil)
}

@Test func theRuntimesWithNoTrustworthyVersionReportNone() throws {
    let b = try VersionBundle("Any"); defer { b.cleanUp() }
    // Chromium, Flutter and the three Apple cases each have a number that could be
    // read and would mean something else. See `RuntimeVersion`.
    for runtime in [AppRuntime.chromium, .flutter, .native, .catalyst, .iOSApp] {
        #expect(b.version(runtime) == nil, "\(runtime.rawValue) should report no version")
    }
}

@Test func chromiumComesFromTheUserAgentInItsFramework() throws {
    // Chrome's framework reports the Chrome version, an embedded CEF reports CEF's,
    // and a fork reports its own app version — the user-agent is the one field that
    // means the same thing in all three.
    let b = try VersionBundle("Browser"); defer { b.cleanUp() }
    let frameworks = b.bundle.appendingPathComponent("Contents/Frameworks/Acme Framework.framework/Versions/A")
    try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
    try Data("filler Mozilla/5.0 (Macintosh) Chrome/152.0.7977.65 Safari/537.36 filler".utf8)
        .write(to: frameworks.appendingPathComponent("Acme Framework"))
    #expect(b.version(.chromium) == "152.0.7977.65")
}

@Test func theChromiumScanIsSkippedWhenScanningIsNotAllowed() throws {
    let b = try VersionBundle("Browser"); defer { b.cleanUp() }
    let frameworks = b.bundle.appendingPathComponent("Contents/Frameworks/Acme Framework.framework/Versions/A")
    try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
    try Data("Chrome/152.0.7977.65".utf8).write(to: frameworks.appendingPathComponent("Acme Framework"))
    #expect(b.version(.chromium, scanning: false) == nil)
}

@Test func anAnswerIsRememberedAgainstTheAppVersion() throws {
    // The expensive readers walk a whole binary; asking twice for an app that has
    // not changed must not pay twice. Deleting the evidence between the two reads
    // is how the test can tell a cached answer from a fresh one.
    let b = try VersionBundle("Shell"); defer { b.cleanUp() }
    try b.executable("Shell", containing: "registry/src/index/tauri-2.11.5/src/lib.rs")
    #expect(RuntimeVersion.read(.tauri, bundleAt: b.bundle, appVersion: "1.0", scanningBinaries: true) == "2.11.5")

    try FileManager.default.removeItem(at: b.bundle.appendingPathComponent("Contents/MacOS/Shell"))
    #expect(RuntimeVersion.read(.tauri, bundleAt: b.bundle, appVersion: "1.0", scanningBinaries: true) == "2.11.5",
            "same version — the remembered answer stands")
    #expect(RuntimeVersion.read(.tauri, bundleAt: b.bundle, appVersion: "1.1", scanningBinaries: true) == nil,
            "a new app version is a new question, and the binary is gone")
}
