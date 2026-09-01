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
        // Every bundle gets an executable and an Info.plist naming it, even the
        // ones whose rule never looks at either. The cache keys on that file, so a
        // fixture without one is a fixture with the cache silently switched off —
        // which is how seven of these tests came to assert their values against an
        // uncached reader without anything noticing.
        try executable(name, containing: "")
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

    /// The same as below, for a payload measured in megabytes rather than
    /// characters.
    func executable(_ name: String, containingBytes bytes: Data) throws {
        try executable(name, containing: "")
        try bytes.write(to: bundle.appendingPathComponent("Contents/MacOS/\(name)"))
    }

    /// Writes the executable *and* the Info.plist that names it, the way a bundle
    /// the reader has to find its way around actually looks.
    ///
    /// - Parameters:
    ///   - stampedAt: a fixed modification date, for the one test that needs two
    ///     different payloads to look identical to the cache key.
    func executable(_ name: String, containing text: String, stampedAt stamp: Date? = nil) throws {
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let executable = macos.appendingPathComponent(name)
        try Data(text.utf8).write(to: executable)
        if let stamp {
            try FileManager.default.setAttributes([.modificationDate: stamp],
                                                  ofItemAtPath: executable.path)
        }
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": name], format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    }

    func version(_ runtime: AppRuntime, scanning: Bool = true) -> String? {
        // A fresh key per bundle — each test builds its own temp directory, so the
        // path already makes the cache entry unique.
        RuntimeVersion.read(runtime, bundleAt: bundle, scanningBinaries: scanning)
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
    // Not a statement that a library-wide scan never walks a binary — since #206 it
    // does, for the handful of bundles `AppRuntimeDetector` has narrowed to. This
    // pins the flag itself: a caller that passes false gets no walk and, because
    // nothing was proved, nothing is remembered either.
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

@Test(.enabled(if: geteuid() != 0, "chmod 000 does not stop root, and these turn on a read failing"))
func anAnswerIsRememberedAgainstTheBinaryItWasReadFrom() throws {
    // The expensive readers walk a whole binary; asking twice for a binary that has
    // not changed must not pay twice. Taking away read permission between the two
    // is how the test tells a remembered answer from a fresh one: `stat` still
    // succeeds so the key is unchanged, while a re-read would fail and return nil.
    // Deleting the file would not do — that changes the key rather than the answer.
    let b = try VersionBundle("Shell"); defer { b.cleanUp() }
    try b.executable("Shell", containing: "registry/src/index/tauri-2.11.5/src/lib.rs")
    #expect(b.version(.tauri) == "2.11.5")

    let executable = b.bundle.appendingPathComponent("Contents/MacOS/Shell")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: executable.path)
    #expect(b.version(.tauri) == "2.11.5", "same binary — the remembered answer stands")
}

@Test func aRewrittenBinaryIsANewQuestionEvenUnderTheSameAppVersion() throws {
    // What the old version-string key could not see. An app that ships a new build
    // under an unchanged marketing version is ordinary — Amp shipped ten in a day,
    // all called 1.0 — and so is a bundle rewritten under a running scan by an
    // install. Either one has to invalidate the answer, and only the bytes can say.
    let b = try VersionBundle("Shell"); defer { b.cleanUp() }
    try b.executable("Shell", containing: "registry/src/index/tauri-2.11.5/src/lib.rs")
    #expect(b.version(.tauri) == "2.11.5")

    try b.executable("Shell", containing: "registry/src/index/tauri-2.12.0/src/lib.rs and padding")
    #expect(b.version(.tauri) == "2.12.0", "different bytes — read again, do not remember 2.11.5")
}

/// `RuntimeVersion` walks a binary in 4 MiB chunks. Both tests below place their
/// payload against that boundary, which is the only place the two window-edge rules
/// can be observed at all.
private let chunkSize = 4 * 1024 * 1024

/// A bundle whose executable is larger than one chunk, with `payload` written at
/// `offset` so it straddles — or sits just before — the first boundary.
private func bundleWithPayload(
    _ name: String, _ payload: String, at offset: Int
) throws -> VersionBundle {
    let b = try VersionBundle(name)
    var bytes = [UInt8](repeating: UInt8(ascii: "."), count: chunkSize + 4096)
    bytes.replaceSubrange(offset..<(offset + payload.utf8.count), with: Array(payload.utf8))
    try b.executable(name, containingBytes: Data(bytes))
    return b
}

@Test func aCandidateAtAChunkBoundaryIsStillHeldToTheIdentifierRule() throws {
    // `xtauri-2.11.5` is not a Tauri crate path anywhere — the character before the
    // needle makes it part of a longer identifier. It was accepted at exactly one
    // offset per chunk: the first byte of a continuation window, whose real
    // predecessor lives in the previous chunk and so could not be checked.
    //
    // For a displayed version that was cosmetic. For a verdict it is the false
    // positive this whole change exists to prevent, so it is pinned here.
    //
    // The offset is taken from `RuntimeVersion.scanOverlap` rather than written as
    // a number, and that is the point of the test rather than a detail of it: with
    // 128 hardcoded, this passed against the unfixed reader — whose overlap was 64,
    // which put the payload in the middle of a window where the guard works fine.
    // Any future change to the overlap has to keep dragging the payload onto the
    // seam, or the test quietly stops testing anything.
    let b = try bundleWithPayload(
        "Shell", "xtauri-2.11.5 ", at: chunkSize - RuntimeVersion.scanOverlap - 1)
    defer { b.cleanUp() }
    #expect(b.version(.tauri) == nil)
}

@Test func aVersionCutByAChunkBoundaryIsReadWhole() throws {
    // `tauri-2.11.50` positioned so the boundary falls between the `5` and the `0`.
    // Three components with a digit last looks like a finished version, so the
    // truncated `2.11.5` was returned — a real version, for a real app, off by a
    // factor of ten.
    let b = try bundleWithPayload("Shell", " tauri-2.11.50 ", at: chunkSize - " tauri-2.11.5".utf8.count)
    defer { b.cleanUp() }
    #expect(b.version(.tauri) == "2.11.50")
}

private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

@Test func aProvenAbsenceIsRememberedToo() throws {
    // The expensive answer, and the one a scan pays for on every cargo-bundled
    // WebView app that turns out not to be Tauri: proving the crate is absent means
    // reading the binary end to end. Longbridge's is 262 MB.
    //
    // Nil is indistinguishable from a failed read at the call site, so this cannot
    // be tested by breaking the file — it swaps the contents for a version that
    // *would* match while restoring the size and modification date, so the key is
    // unchanged. A second reader that answers 2.9.9 did not use the cache. (This
    // caught a real bug: `read(upToCount:)` returns nil at EOF, so an earlier draft
    // reported every completed walk as unreadable and cached nothing at all.)
    let b = try VersionBundle("Shell"); defer { b.cleanUp() }
    try b.executable("Shell", containing: "registry/src/index/wry-0.53.3/src/lib.rs", stampedAt: stamp)
    #expect(b.version(.tauri) == nil)

    let executable = b.bundle.appendingPathComponent("Contents/MacOS/Shell")
    let before = try FileManager.default.attributesOfItem(atPath: executable.path)
    try b.executable("Shell", containing: "registry/src/index/tauri-2.9.9/src/lib.r", stampedAt: stamp)
    let after = try FileManager.default.attributesOfItem(atPath: executable.path)
    try #require(after[.size] as? NSNumber == before[.size] as? NSNumber,
                 "the two payloads must be the same length or the key changes for the wrong reason")
    try #require(after[.modificationDate] as? Date == stamp,
                 "and the same modification date — restoring one is lossy, so both are stamped")

    #expect(b.version(.tauri) == nil, "the proven absence is remembered, not walked again")
}

@Test(.enabled(if: geteuid() != 0, "chmod 000 does not stop root, and these turn on a read failing"))
func aBinaryThatCannotBeReadThroughIsNotRememberedAsProofOfAbsence() throws {
    // The distinction `Probe` exists for. A nil from the Tauri reader is a verdict —
    // `carriesTauriCrate` turns it into "not Tauri" — so a read that never reached
    // the end must leave nothing behind, or one unlucky moment during an install
    // would mislabel the app for the life of the process.
    let b = try VersionBundle("Shell"); defer { b.cleanUp() }
    try b.executable("Shell", containing: "registry/src/index/tauri-2.11.5/src/lib.rs")
    let executable = b.bundle.appendingPathComponent("Contents/MacOS/Shell")

    // Unreadable at the moment of asking: no answer, and nothing cached.
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: executable.path)
    #expect(b.version(.tauri) == nil)

    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
    #expect(b.version(.tauri) == "2.11.5", "the earlier failure was not remembered as an answer")
}
