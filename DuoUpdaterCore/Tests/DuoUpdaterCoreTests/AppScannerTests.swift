import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func scanFindsRealApps() {
    let apps = AppScanner(testflight: TestFlightInventory(macRows: [])).scan()
    #expect(!apps.isEmpty, "expected to find at least one app in /Applications")
}

/// Vendor suites and people's own sorted folders put an app one folder below a
/// scan root; scanning one level deep finds those. Two levels is the line: the
/// user's deeper tree is what a custom scan folder is for, and walking into it
/// would only add uninstallers and helper bundles (issue #1759).
@Test func scanReachesAppsOneFolderDeepButNotTwo() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appendingPathComponent("scanner-depth-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }

    try writeFixtureApp(at: root.appendingPathComponent("Flat.app"),
                        id: "com.example.flat", name: "Flat")
    try writeFixtureApp(at: root.appendingPathComponent("Adobe Photoshop 2025/Adobe Photoshop.app"),
                        id: "com.example.photoshop", name: "Adobe Photoshop")
    try writeFixtureApp(at: root.appendingPathComponent("Vendor/Product/Deep.app"),
                        id: "com.example.deep", name: "Deep")
    // Chrome's web-app shims live one folder deep in `~/Applications/…localized`;
    // one level down is exactly the depth that would now reach them.
    try writeFixtureApp(at: root.appendingPathComponent("Chrome Apps.localized/Gmail.app"),
                        id: "com.google.Chrome.app.gmail", name: "Gmail")

    let scanner = AppScanner(locations: [root], testflight: TestFlightInventory(macRows: []))
    #expect(scanner.scan().map(\.name) == ["Adobe Photoshop", "Flat"])
}

/// A folder that is itself a scan root must not be read twice as a root and as
/// `/Applications`'s subfolder (`Utilities` is both on every Mac). The path
/// dedupe already keeps the row single; this pins the count so a future change
/// that drops the root check cannot double the scan work silently.
@Test func folderThatIsAlsoARootIsReadOnce() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appendingPathComponent("scanner-root-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    let utilities = root.appendingPathComponent("Utilities")
    try writeFixtureApp(at: utilities.appendingPathComponent("Inside.app"),
                        id: "com.example.inside", name: "Inside")

    let scanner = AppScanner(locations: [root, utilities],
                             testflight: TestFlightInventory(macRows: []))
    #expect(scanner.scan().map(\.name) == ["Inside"])
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
    // The channel binding is injected, not read. The real one is a live read of
    // another app's preferences under a 2s deadline, and on 2026-10-09 the CI
    // mini's AppData consent gate let the full scan read CotEditor's `.beta` and
    // then held the scoped re-read past the deadline (non-authoritative
    // `.stable`) — two scans disagreeing about the machine, not about the bundle.
    // The stand-in answers for EVERY bundle and is a pure function of what the
    // scanner hands it, with each input echoed into a different field of the
    // row: a scoped path that skipped the binding, or handed it another id or
    // other feeds, still yields a row that differs. What this no longer covers is
    // whether the preference read itself answers in time — that is
    // `ChannelBindingBoundTests` and the per-app channel tests.
    let scanner = AppScanner(
        testflight: TestFlightInventory(macRows: []),
        channelBinding: { bundleID, feeds, strings in
            guard let bundleID else { return nil }
            let keys = feeds.keys.sorted()
            return ResolvedChannel(
                channel: .beta,
                feedOverride: URL(string: "https://binding.invalid/\(bundleID)"),
                feedHTTPHeaders: Dictionary(uniqueKeysWithValues: keys.map { ($0, feeds[$0]!.absoluteString) }),
                sparkleChannelNames: Set([bundleID] + strings.map { "\($0.key)=\($0.value)" }))
        })
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
    #expect(AppScanner(testflight: TestFlightInventory(macRows: [])).scan(bundlesAt: [gone]).isEmpty)
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

    let app = try #require(AppScanner(testflight: TestFlightInventory(macRows: [])).scan(bundlesAt: [wrapper]).first)
    #expect(app.runtime == .electron)
    #expect(!app.hasSelfUpdater)
    #expect(!app.hasSparkleUpdater)
    #expect(app.electronUpdate == nil)
    #expect(app.sparkleFeedURL == nil)
}

/// Helium ships Sparkle inside its Chromium framework, reached the way a real
/// versioned framework is laid out: `Helium Framework.framework/Frameworks` is a
/// symlink to `Versions/Current/Frameworks`, and `Current` points at the version.
/// Before this, the flag looked only at `Contents/Frameworks/Sparkle.framework`, so
/// a build Helium's own Sparkle had staged was invisible to `SelfUpdaterStaging`.
///
/// Mutation: drop `nestsSparkleOneFrameworkDeep` from the scanner's check.
@Test func sparkleNestedInAVersionedFrameworkIsSeen() throws {
    let bundle = try makeBundleWithNestedSparkle(depth: 1, id: "net.example.zzfixture.nested1")
    defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
    let app = try #require(AppScanner(testflight: TestFlightInventory(macRows: [])).scan(bundlesAt: [bundle]).first)
    #expect(app.hasSparkleUpdater)
}

/// The check is bounded on purpose (it runs for every bundle on every scan), so a
/// Sparkle two frameworks down is not looked for.
///
/// Mutation: replace the one-level check with a recursive walk of the bundle.
@Test func sparkleTwoFrameworksDownIsNotSearched() throws {
    let bundle = try makeBundleWithNestedSparkle(depth: 2, id: "net.example.zzfixture.nested2")
    defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
    let app = try #require(AppScanner(testflight: TestFlightInventory(macRows: [])).scan(bundlesAt: [bundle]).first)
    #expect(!app.hasSparkleUpdater)
}

/// A bundle with `Sparkle.framework` `depth` frameworks below `Contents/Frameworks`,
/// each level laid out as a versioned framework with a `Frameworks` symlink.
private func makeBundleWithNestedSparkle(depth: Int, id: String) throws -> URL {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("scanner-nested-sparkle-\(UUID().uuidString)")
    let bundle = root.appendingPathComponent("ZZNested.app")
    var frameworks = bundle.appendingPathComponent("Contents/Frameworks")
    for level in 0..<depth {
        let framework = frameworks.appendingPathComponent("Host\(level) Framework.framework")
        let versioned = framework.appendingPathComponent("Versions/A/Frameworks")
        try fm.createDirectory(at: versioned, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: framework.appendingPathComponent("Versions/Current").path,
            withDestinationPath: "A")
        try fm.createSymbolicLink(
            atPath: framework.appendingPathComponent("Frameworks").path,
            withDestinationPath: "Versions/Current/Frameworks")
        frameworks = versioned
    }
    try fm.createDirectory(
        at: frameworks.appendingPathComponent("Sparkle.framework"), withIntermediateDirectories: true)
    let info = bundle.appendingPathComponent("Contents/Info.plist")
    try PropertyListSerialization
        .data(fromPropertyList: [
            "CFBundleIdentifier": id, "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1", "CFBundleName": "ZZNested",
        ], format: .xml, options: 0)
        .write(to: info)
    return bundle
}

/// Both installer matchers — `SparkleStagingClearance`'s job match and
/// `SelfUpdaterStaging`'s process walk — read their homes from here. Before this,
/// each kept the top-level path, so Helium's `Autoupdate`, running from inside its
/// Chromium framework, read as "no installer" to the orphan check even after the
/// job match had been fixed (found on the mini, 2026-10-15).
///
/// Mutation: build the homes from the top-level path alone again.
@Test func installerHomesIncludeASparkleNestedInAFramework() throws {
    let bundle = try makeBundleWithNestedSparkle(depth: 1, id: "net.example.zzfixture.homes")
    defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
    let app = InstalledApp(
        name: "ZZNested", bundleID: "net.example.zzfixture.homes", shortVersion: "1.0",
        buildVersion: "1", path: bundle, isMASApp: false, sparkleFeedURL: nil,
        hasSparkleUpdater: true)
    let homes = SelfUpdaterStaging.sparkleInstallerHomes(for: app, sparkleRoots: [])
    let nested = bundle
        .appendingPathComponent("Contents/Frameworks/Host0 Framework.framework/Versions/A/Frameworks/Sparkle.framework")
        .resolvingSymlinksInPath().path
    #expect(homes == [nested])
}

/// A bundle `readApp` will accept, without the cost of a real app: the only
/// things it requires are a readable Info.plist and a marketing version.
private func writeFixtureApp(at bundle: URL, id: String, name: String) throws {
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try PropertyListSerialization
        .data(fromPropertyList: [
            "CFBundleIdentifier": id, "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1", "CFBundleName": name,
        ], format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
}
