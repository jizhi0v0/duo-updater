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
    // `pageMentions` guard — surfacing as "Couldn't find the update button".
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
