import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func scanFindsRealApps() {
    let apps = AppScanner().scan()
    #expect(!apps.isEmpty, "expected to find at least one app in /Applications")
}

@Test func cleansNoisyJetBrainsEAPVersion() {
    // A JetBrains EAP bundle reports "EAP IU-262.6653.22" as its marketing version;
    // with no Toolbox to supply a clean "2026.2" we reduce it to the bare build.
    #expect(AppScanner.cleanedJetBrainsVersion(
        "EAP IU-262.6653.22", bundleID: "com.jetbrains.intellij-EAP") == "262.6653.22")
    // A clean stable version (no "EAP "/product-code prefix) passes through.
    #expect(AppScanner.cleanedJetBrainsVersion(
        "2026.1.3", bundleID: "com.jetbrains.intellij") == "2026.1.3")
    // Non-JetBrains strings are never touched, even if oddly shaped.
    #expect(AppScanner.cleanedJetBrainsVersion(
        "EAP IU-1.2.3", bundleID: "com.example.app") == "EAP IU-1.2.3")
}

/// The scoped scan the App uses for a single-row recheck (issue #226) must answer
/// exactly what the full scan answered for that row — same fields, same identity —
/// or the recheck silently rewrites a row with a different reading of the same
/// bundle. Derived from the real machine rather than a fixture list: every app the
/// full scan returns is re-read alone and compared whole (`InstalledApp` is
/// `Hashable`). One scanner instance so both reads share the Toolbox/TestFlight
/// inventories, as the App's recheck does.
@Test func scopedScanMatchesTheFullScanRowForRow() throws {
    let scanner = AppScanner()
    let full = scanner.scan()
    try #require(!full.isEmpty, "expected at least one app in the default locations")
    for app in full {
        let scoped = scanner.scan(bundlesAt: [app.path])
        #expect(scoped == [app], "\(app.path.path) re-read alone differs from its full-scan row")
    }
    // The batch form (`retryFailedChecks` hands over many rows at once) returns the
    // same rows, sorted by name like the full scan. Handed over in REVERSE: in scan
    // order the assertion passed with the sort deleted (checked by mutation),
    // because the output simply inherited the input's order. Not `== full`: apps
    // sharing a display name (two Amps, two WeChats on the machine this was
    // written on) keep input order in both scans, and no caller reads the order —
    // rows are replaced by id — so "same rows, sorted" is the whole contract.
    let batch = scanner.scan(bundlesAt: full.reversed().map(\.path))
    #expect(batch.count == full.count)
    #expect(Set(batch) == Set(full))
    #expect(zip(batch, batch.dropFirst()).allSatisfy {
        $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedDescending
    })
}

/// Callers read "missing from the scoped result" as "uninstalled between the
/// full scan and now" (`recheckMany` returns nothing and the caller keeps its own
/// row), so a bundle that is gone must yield nothing rather than a stub or a
/// crash.
@Test func scopedScanYieldsNothingForABundleThatIsGone() {
    let gone = URL(fileURLWithPath: "/Applications/DuoUpdaterTests-\(UUID().uuidString).app")
    #expect(AppScanner().scan(bundlesAt: [gone]).isEmpty)
}

/// Runtime attribution and update ownership are different questions. Docker's
/// outer bundle launches the product, while its one nested GUI supplies the
/// Electron runtime label. That nested GUI also happens to embed Squirrel,
/// Sparkle and an electron-builder manifest, but Docker updates through
/// `com.docker.backend.updater`, not ShipIt (#217). The fixture plants all
/// three files (plus a nested `SUFeedURL`) precisely so each probe has
/// something to wrongly find if it ever descended into the nested bundle —
/// see #290: an earlier version of this fixture only planted Squirrel, so a
/// mutation moving `hasSparkleUpdater` or `ElectronUpdateConfig.read` onto
/// `AppRuntimeDetector.interfaceBundle(at:)` left this test green.
@Test func nestedInterfaceDoesNotLendItsUpdaterToTheWrapper() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appendingPathComponent("scanner-docker-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }

    let wrapper = root.appendingPathComponent("Docker.app")
    let nested = wrapper.appendingPathComponent("Contents/MacOS/Docker Desktop.app")
    let nestedFrameworks = nested.appendingPathComponent("Contents/Frameworks")
    try fm.createDirectory(
        at: nestedFrameworks.appendingPathComponent("Electron Framework.framework"),
        withIntermediateDirectories: true)
    try fm.createDirectory(
        at: nestedFrameworks.appendingPathComponent("Squirrel.framework"),
        withIntermediateDirectories: true)
    try fm.createDirectory(
        at: nestedFrameworks.appendingPathComponent("Sparkle.framework"),
        withIntermediateDirectories: true)
    let nestedResources = nested.appendingPathComponent("Contents/Resources")
    try fm.createDirectory(at: nestedResources, withIntermediateDirectories: true)
    try "provider: generic\nurl: https://example.com/nested-updates\n".write(
        to: nestedResources.appendingPathComponent("app-update.yml"),
        atomically: true, encoding: .utf8)

    let outerPlist: [String: Any] = [
        "CFBundleDisplayName": "Docker",
        "CFBundleIdentifier": "com.docker.docker",
        "CFBundleShortVersionString": "4.89.0",
        "CFBundleVersion": "238018",
        "CFBundleExecutable": "com.docker.backend",
    ]
    // `SUFeedURL` on the nested plist is a belt-and-suspenders addition, not a
    // mutation witness: `sparkleFeedURL` reads the SHARED `plist` this test
    // parses once from `wrapper`'s own Info.plist (see `AppScanner.readApp`,
    // which loads `infoURL` from `bundleURL` before either bundle's identity
    // is known), never a plist re-read from `interfaceBundle`. A path-swap
    // mutation analogous to the other three probes' therefore has nothing to
    // move — the address would have to come from swapping `bundleID` itself
    // (SparkleFeedCatalog looks up by bundle id, not by path), which is a
    // change to a different, shared fact and not a faithful analog of "this
    // one probe descended a level". Confirmed by hand (#290): rerouting the
    // `SUFeedURL` read through a plist loaded from `interfaceBundle(at:)`
    // left this test green, because neither plist here sets `SUFeedURL` and
    // the `SparkleFeedCatalog` fallback still keys off the outer bundle id.
    let nestedPlist: [String: Any] = [
        "CFBundleDisplayName": "Docker Desktop",
        "CFBundleIdentifier": "com.electron.dockerdesktop",
        "CFBundleShortVersionString": "4.89.0",
        "CFBundleVersion": "4.89.0.9",
        "SUFeedURL": "https://example.com/nested-appcast.xml",
    ]
    for (bundle, plist) in [(wrapper, outerPlist), (nested, nestedPlist)] {
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        try fm.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: info)
    }

    let app = try #require(AppScanner().scan(bundlesAt: [wrapper]).first)
    #expect(app.runtime == .electron)
    #expect(!app.hasSelfUpdater)
    #expect(!app.hasSparkleUpdater)
    #expect(app.electronUpdate == nil)
    #expect(app.sparkleFeedURL == nil)
}
