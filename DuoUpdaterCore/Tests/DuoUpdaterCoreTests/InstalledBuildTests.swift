import Testing
import Foundation
@testable import DuoUpdaterCore

/// The build recorded as "what this install landed on" is measured off disk, so
/// the fragile parts are (a) never reading disk when the swap has not happened,
/// and (b) the read genuinely re-reading rather than answering from a cache.

private func makeBundle(build: String, at url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": "com.example.app",
        "CFBundleShortVersionString": "6.9.0",
        "CFBundleVersion": build,
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
}

private func scratch() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("installed-build-\(UUID().uuidString)")
}

// MARK: - Reading

@Test func readsTheBuildOutOfABundle() throws {
    let base = scratch()
    let app = base.appendingPathComponent("Example.app")
    try makeBundle(build: "12030", at: app)
    defer { try? FileManager.default.removeItem(at: base) }
    #expect(InstalledBuild.read(at: app) == "12030")
}

/// The whole point: this runs immediately after an in-place swap replaced the
/// bundle at that exact path. `Bundle(path:)` memoises one instance per path for
/// the life of the process and would answer with the build we just overwrote —
/// so a second read of the same path must see the new value.
@Test func readingAgainSeesABundleThatWasReplacedUnderIt() throws {
    let base = scratch()
    let app = base.appendingPathComponent("Example.app")
    try makeBundle(build: "12200", at: app)
    defer { try? FileManager.default.removeItem(at: base) }
    #expect(InstalledBuild.read(at: app) == "12200")

    // Same path, new contents — exactly what an install does.
    try makeBundle(build: "12240", at: app)
    #expect(InstalledBuild.read(at: app) == "12240")
}

@Test func anUnreadableOrBuildlessBundleReadsAsNil() throws {
    let base = scratch()
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    #expect(InstalledBuild.read(at: base.appendingPathComponent("Missing.app")) == nil)

    // Present but with no CFBundleVersion.
    let bare = base.appendingPathComponent("Bare.app")
    try FileManager.default.createDirectory(
        at: bare.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleIdentifier": "x"], format: .xml, options: 0)
    try data.write(to: bare.appendingPathComponent("Contents/Info.plist"))
    #expect(InstalledBuild.read(at: bare) == nil)

    // Present but empty — an empty string is not a build number.
    let blank = base.appendingPathComponent("Blank.app")
    try FileManager.default.createDirectory(
        at: blank.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let blankData = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleVersion": ""], format: .xml, options: 0)
    try blankData.write(to: blank.appendingPathComponent("Contents/Info.plist"))
    #expect(InstalledBuild.read(at: blank) == nil)

    // Present but whitespace-only — issue #287: a bare `isEmpty` check (what
    // this read used before converging onto `VersionSide.plistVersionField`)
    // lets "   " through as a "real" build number.
    let whitespace = base.appendingPathComponent("Whitespace.app")
    try FileManager.default.createDirectory(
        at: whitespace.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let whitespaceData = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleVersion": "   "], format: .xml, options: 0)
    try whitespaceData.write(to: whitespace.appendingPathComponent("Contents/Info.plist"))
    #expect(InstalledBuild.read(at: whitespace) == nil)
}

// MARK: - Deciding

/// A staged .pkg has not been applied: macOS's installer still has a window open
/// and the bundle on disk is the build being REPLACED. Reading it there would
/// record the old build as the new one — worse than recording nothing.
@Test func aStagedInstallNeverTouchesTheBundle() {
    var read = false
    let result = InstalledBuild.recorded(
        applied: false,
        onDisk: { read = true; return "OLD-BUILD-ON-DISK" },
        declared: "12240")
    #expect(result == "12240")
    #expect(read == false, "the bundle must not be read when the swap has not landed")
}

@Test func anAppliedInstallPrefersWhatIsActuallyOnDisk() {
    let result = InstalledBuild.recorded(
        applied: true, onDisk: { "12240" }, declared: "12200")
    // The source advertised 12200; 12240 is what landed. Feeds do misreport.
    #expect(result == "12240")
}

@Test func anAppliedInstallFallsBackToTheDeclaredBuild() {
    let result = InstalledBuild.recorded(
        applied: true, onDisk: { nil }, declared: "12240")
    #expect(result == "12240")
}

/// GitHub, Homebrew and the App Store publish no build number, so `declared` is
/// nil — and reading disk is the only way those rows ever get one.
@Test func aSourceWithNoDeclaredBuildStillGetsTheInstalledOne() {
    #expect(InstalledBuild.recorded(
        applied: true, onDisk: { "12240" }, declared: nil) == "12240")
    #expect(InstalledBuild.recorded(
        applied: false, onDisk: { "12240" }, declared: nil) == nil)
}
