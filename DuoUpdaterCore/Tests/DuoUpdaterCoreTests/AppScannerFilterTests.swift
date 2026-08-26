import Testing
import Foundation
@testable import DuoUpdaterCore

/// Build a throwaway `.app` bundle with the given Info.plist keys.
private func makeApp(at dir: URL, name: String, info: [String: Any]) throws -> URL {
    let bundle = dir.appendingPathComponent("\(name).app")
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return bundle
}

@Test func scannerSkipsBundlesWithNoMarketingVersion() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeApp(at: tmp, name: "Real", info: [
        "CFBundleIdentifier": "com.example.real",
        "CFBundleShortVersionString": "1.2.3",
    ])
    // Helper/background bundle: a URL handler with no marketing version.
    _ = try makeApp(at: tmp, name: "URL Handler", info: [
        "CFBundleIdentifier": "com.example.helper",
        "CFBundleVersion": "1.0",
        "LSBackgroundOnly": true,
    ])

    let apps = AppScanner(locations: [tmp]).scan()
    #expect(apps.map(\.name) == ["Real"])  // helper excluded
}

@Test func scannerStripsInvisibleBidiMarksFromDisplayName() throws {
    // WhatsApp ships CFBundleDisplayName "\u{200E}WhatsApp" (a leading LEFT-TO-RIGHT
    // MARK). That invisible mark made the canonical name "\u{200E}WhatsApp", which
    // never matched the App Store page's plain "WhatsApp" in the AX updater's
    // `heroOwns` guard — surfacing as "Couldn't find the update button".
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeApp(at: tmp, name: "WhatsAppRaw", info: [
        "CFBundleIdentifier": "net.whatsapp.WhatsApp",
        "CFBundleShortVersionString": "26.21.73",
        "CFBundleDisplayName": "\u{200E}WhatsApp",
    ])

    let apps = AppScanner(locations: [tmp]).scan()
    #expect(apps.map(\.name) == ["WhatsApp"])  // bidi mark stripped
    #expect(!(apps.first?.name.unicodeScalars.contains("\u{200E}") ?? true))
}

@Test func stripInvisibleMarksKeepsZeroWidthJoiner() {
    // ZWJ (U+200D) binds emoji / Indic clusters — stripping it would corrupt the
    // name, so it's deliberately preserved while bidi marks are removed.
    #expect(AppScanner.stripInvisibleMarks("\u{200E}A\u{200B}B\u{FEFF}") == "AB")
    #expect(AppScanner.stripInvisibleMarks("man\u{200D}woman") == "man\u{200D}woman")
    #expect(AppScanner.stripInvisibleMarks("  Plain  ") == "Plain")
}

@Test func twoBundlesSharingABundleIDGetDistinctIDs() throws {
    // Two JetBrains-Toolbox Android Studio installs (Otter + Koala) ship the
    // same CFBundleIdentifier. Identity keys on the on-disk path, not the
    // bundleID, so they must stay two distinct rows — keying on bundleID
    // collapsed them to one id, which rendered a blank SwiftUI ForEach ghost
    // row and dropped a copy in refreshLocal's id-keyed dict.
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeApp(at: tmp, name: "Android Studio Otter", info: [
        "CFBundleIdentifier": "com.google.android.studio",
        "CFBundleShortVersionString": "2025.2",
    ])
    _ = try makeApp(at: tmp, name: "Android Studio Koala", info: [
        "CFBundleIdentifier": "com.google.android.studio",
        "CFBundleShortVersionString": "2024.1",
    ])

    let apps = AppScanner(locations: [tmp]).scan()
    #expect(apps.count == 2)
    #expect(Set(apps.map(\.id)).count == 2)  // distinct identities, no ghost row
    #expect(Set(apps.map(\.scratchSlug)).count == 2)  // distinct installer scratch dirs
}

/// Build a throwaway wrapped iOS app: `<Name>.app/Wrapper/<Inner>.app/Info.plist`
/// with a `WrappedBundle` symlink, mirroring how iPhone/iPad apps install on
/// Apple Silicon. The outer bundle deliberately has no `Contents/`.
private func makeWrappedIOSApp(at dir: URL, name: String, info: [String: Any]) throws -> URL {
    let bundle = dir.appendingPathComponent("\(name).app")
    let inner = bundle
        .appendingPathComponent("Wrapper")
        .appendingPathComponent("\(name).app")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: inner.appendingPathComponent("Info.plist"))  // flat iOS layout, no Contents/
    try FileManager.default.createSymbolicLink(
        atPath: bundle.appendingPathComponent("WrappedBundle").path,
        withDestinationPath: "Wrapper/\(name).app"
    )
    return bundle
}

@Test func scannerReadsWrappedIOSAppAndFlagsItMAS() throws {
    // iPhone/iPad apps on Apple Silicon (e.g. Aqara Home) have no
    // Contents/Info.plist — the real bundle is under Wrapper/. Before the fix
    // these were silently dropped from the scan entirely.
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeWrappedIOSApp(at: tmp, name: "Aqara Home", info: [
        "CFBundleIdentifier": "com.lumiunited.pre.homekit",
        "CFBundleDisplayName": "Aqara Home",
        "CFBundleShortVersionString": "6.1.6",
    ])

    let apps = AppScanner(locations: [tmp]).scan()
    #expect(apps.count == 1)
    let app = try #require(apps.first)
    #expect(app.name == "Aqara Home")
    #expect(app.bundleID == "com.lumiunited.pre.homekit")
    #expect(app.shortVersion == "6.1.6")
    #expect(app.isiOSAppOnMac)         // routes to the App Store source's direct path
    #expect(app.isMASApp)              // iOS-on-Mac apps only come from the App Store
}

@Test func extraLocationsAreScannedOnTopOfBuiltInRoots() throws {
    // A user adds a folder outside the standard roots (Settings → Folders), e.g.
    // a developer build dir holding an app. `extraLocations` appends it to the
    // defaults, so the app surfaces without losing the built-in coverage.
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // Unique per run so it can't collide with a real app the test machine happens
    // to have installed under the built-in roots (else the negative check below
    // fails — e.g. NotchBadge.app actually sitting in /Applications).
    let fixtureID = "com.duoupdater.tests.extralocation-\(UUID().uuidString)"
    _ = try makeApp(at: tmp, name: "ScanFixture", info: [
        "CFBundleIdentifier": fixtureID,
        "CFBundleShortVersionString": "1.2",
        "LSUIElement": true,   // menu-bar app — still scanned (only no-version bundles drop)
    ])

    // Default roots alone don't reach the temp dir.
    #expect(!AppScanner().scan().contains { $0.bundleID == fixtureID })
    // With the folder added it shows up, alongside the real /Applications scan.
    let apps = AppScanner(extraLocations: [tmp]).scan()
    #expect(apps.contains { $0.bundleID == fixtureID })
    #expect(!apps.isEmpty)
}

@Test func scannerSkipsSymlinksIntoSystem() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // A symlink mimicking /Applications/Utilities → /System/... (Feedback
    // Assistant). resolvingSymlinksInPath should land under /System and be
    // skipped. We can't create files in /System, so point at a real system app.
    let systemApp = "/System/Library/CoreServices/Applications/Feedback Assistant.app"
    try? FileManager.default.createSymbolicLink(
        atPath: tmp.appendingPathComponent("Feedback Assistant.app").path,
        withDestinationPath: systemApp
    )

    let apps = AppScanner(locations: [tmp]).scan()
    #expect(!apps.contains { $0.bundleID?.hasPrefix("com.apple") == true })
}

@Test func scannerSkipsSidecarBackupAndDuplicateBundles() throws {
    // DuoPaste's own updater parks `DuoPaste.backup-<stamp>.app` next to the real
    // bundle on every self-update. Three of them accumulated in ~/Applications and
    // the list showed four identical DuoPaste rows, each offering to install into a
    // dead path.
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    _ = try makeApp(at: tmp, name: "DuoPaste", info: [
        "CFBundleIdentifier": "io.duopaste.daemon",
        "CFBundleShortVersionString": "0.1.1270",
        "CFBundleVersion": "1271",
    ])
    for stamp in ["20260716-183428", "20260716-185238"] {
        _ = try makeApp(at: tmp, name: "DuoPaste.backup-\(stamp)", info: [
            "CFBundleIdentifier": "io.duopaste.daemon",
            "CFBundleShortVersionString": "0.1.1269-beta+9c7aa27",
            "CFBundleVersion": "1269",
        ])
    }
    _ = try makeApp(at: tmp, name: "DuoPaste copy", info: [
        "CFBundleIdentifier": "io.duopaste.daemon",
        "CFBundleShortVersionString": "0.1.1268",
        "CFBundleVersion": "1268",
    ])
    _ = try makeApp(at: tmp, name: "DuoPaste 副本 2", info: [
        "CFBundleIdentifier": "io.duopaste.daemon",
        "CFBundleShortVersionString": "0.1.1267",
        "CFBundleVersion": "1267",
    ])

    let apps = AppScanner(locations: [tmp]).scan()
    #expect(apps.count == 1)
    #expect(apps.first?.shortVersion == "0.1.1270")
}

@Test func sidecarMatcherLeavesOrdinaryAppNamesAlone() {
    let sidecars = [
        "DuoPaste.backup-20260716-183428", "Foo.backup", "Foo.old", "Foo.OLD",
        "Foo copy", "Foo copy 2", "Foo 副本", "Foo 的副本 2",
    ]
    for name in sidecars {
        #expect(AppScanner.isSidecarCopy(URL(fileURLWithPath: "/Applications/\(name).app")),
                "expected \(name) to be treated as a sidecar copy")
    }
    // Real app names that must survive: "Copy"/"Backup" as words, and versioned
    // or dotted names that merely look similar.
    let keepers = [
        "Copy", "Copy'em", "Backup Buddy", "Time Machine Backups", "iOldMac",
        "Adobe Photoshop 2026", "DuoPaste", "Old School RuneScape",
    ]
    for name in keepers {
        #expect(!AppScanner.isSidecarCopy(URL(fileURLWithPath: "/Applications/\(name).app")),
                "expected \(name) to be kept")
    }
}

@Test func dedupeKeepsSameBundleIDInstallsThatDifferInVersionOrChannel() {
    // Two Toolbox Android Studio majors share `com.google.android.studio` and both
    // must keep their row; Firefox Stable and Beta share `org.mozilla.firefox` and
    // are told apart only by channel. Only an exact id+channel+version clone folds.
    func app(_ name: String, _ id: String, _ version: String,
             _ channel: ReleaseChannel, _ path: String) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: channel)
    }
    let apps = [
        app("Android Studio", "com.google.android.studio", "2025.1", .stable, "/Applications/AS-Koala.app"),
        app("Android Studio", "com.google.android.studio", "2025.2", .stable, "/Applications/AS-Otter.app"),
        app("Firefox", "org.mozilla.firefox", "153.0", .stable, "/Applications/Firefox.app"),
        app("Firefox Beta", "org.mozilla.firefox", "153.0", .beta, "/Applications/Firefox Beta.app"),
        // A true clone: same id, channel and version, different folder.
        app("Firefox", "org.mozilla.firefox", "153.0", .stable, "/Users/me/Applications/Firefox.app"),
    ]
    let deduped = AppScanner.dedupeIdenticalInstalls(apps)
    #expect(deduped.count == 4)
    #expect(deduped.map(\.path.path).contains("/Applications/Firefox.app"))
    #expect(!deduped.map(\.path.path).contains("/Users/me/Applications/Firefox.app"))
}
