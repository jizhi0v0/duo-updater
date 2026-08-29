import Testing
import Foundation
@testable import DuoUpdaterCore

/// Build the two bundle layouts on disk. A wrapped iPhone/iPad app has no
/// `Contents/` at all: `Wrapper/<Inner>.app` holds a flat iOS bundle and
/// `WrappedBundle` is a symlink to it. Built rather than mocked because the
/// discriminator being tested is a filesystem fact.
private func makeBundle(wrapped: Bool, short: String, build: String) throws -> URL {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appendingPathComponent("bundle-layout-\(UUID().uuidString)", isDirectory: true)
    let app = root.appendingPathComponent("Sample.app", isDirectory: true)
    let plist: [String: Any] = [
        "CFBundleShortVersionString": short,
        "CFBundleVersion": build,
        "CFBundleIdentifier": "com.example.sample",
        "CFBundleName": "Sample",
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
    if wrapped {
        let inner = app.appendingPathComponent("Wrapper/Sample.app", isDirectory: true)
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        try data.write(to: inner.appendingPathComponent("Info.plist"))
        try fm.createSymbolicLink(
            at: app.appendingPathComponent("WrappedBundle"),
            withDestinationURL: inner)
    } else {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
    return app
}

@Test func resolvesTheClassicLayout() throws {
    let app = try makeBundle(wrapped: false, short: "3.1", build: "310")
    defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

    #expect(BundleLayout.infoPlistURL(for: app).path
            == app.appendingPathComponent("Contents/Info.plist").path)
}

/// The regression this exists for: the outer `.app` of a wrapped iPhone/iPad app
/// has no `Contents/Info.plist`, so the classic path reads *nothing* — not a
/// wrong version, an absent one. Assert the file we resolve to is actually
/// readable, since "returns a URL" was never the failure.
@Test func resolvesTheWrappediOSLayout() throws {
    let app = try makeBundle(wrapped: true, short: "1.0.7", build: "48")
    defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

    let classic = app.appendingPathComponent("Contents/Info.plist")
    #expect(!FileManager.default.fileExists(atPath: classic.path))

    let resolved = BundleLayout.infoPlistURL(for: app)
    let dict = NSDictionary(contentsOf: resolved)
    #expect(dict?["CFBundleShortVersionString"] as? String == "1.0.7")
    #expect(dict?["CFBundleVersion"] as? String == "48")
}

/// `InstalledBuild.read` is what records which build landed after a swap, and
/// what `DeltaApplier` checks a delta against. On the classic layout it always
/// worked; on a wrapped one it returned nil, which reads downstream as "couldn't
/// tell" and silently disables every build-based comparison.
@Test func readsTheBuildFromEitherLayout() throws {
    let classic = try makeBundle(wrapped: false, short: "3.1", build: "310")
    defer { try? FileManager.default.removeItem(at: classic.deletingLastPathComponent()) }
    let iosOnMac = try makeBundle(wrapped: true, short: "1.0.7", build: "48")
    defer { try? FileManager.default.removeItem(at: iosOnMac.deletingLastPathComponent()) }

    #expect(InstalledBuild.read(at: classic) == "310")
    #expect(InstalledBuild.read(at: iosOnMac) == "48")
}

/// The exact shape of the six-minute spin, asserted through the installer's own
/// rule rather than a stand-in: baseline is read before the store swaps the
/// bundle, the swap lands, and `versionChanged` is asked whether the on-disk
/// version moved. With the plist unreadable both readings are nil and the answer
/// is "no" however long it waits, so the poll can only end in a timeout on an
/// update that already succeeded.
///
/// An earlier version of this test re-implemented the read with `NSDictionary`
/// and could not fail for any mutation of the installer — the same "守卫在、判据废了"
/// shape as the bug it was meant to pin.
@Test func theInstallerObservesAWrappedBundleSwap() throws {
    let app = try makeBundle(wrapped: true, short: "1.0.6", build: "47")
    defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

    let baseline = AppStoreAXInstaller.installedVersions(at: app, fallbackShort: "1.0.6")
    #expect(baseline.short == "1.0.6")
    #expect(baseline.build == "47")   // nil here is the pre-fix reading
    #expect(!AppStoreAXInstaller.versionChanged(from: baseline, appPath: app))

    // Stand in for storedownloadd replacing the wrapped bundle in place.
    let inner = app.appendingPathComponent("Wrapper/Sample.app/Info.plist")
    try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleShortVersionString": "1.0.7",
                           "CFBundleVersion": "48"] as [String: Any],
        format: .xml, options: 0).write(to: inner)

    #expect(AppStoreAXInstaller.versionChanged(from: baseline, appPath: app))
}

/// A build-only bump is the case marketing strings cannot see, and wrapped apps
/// hit it (Amp ships many builds under a frozen "1.0"). The completion rule has
/// to settle on the build alone.
@Test func theInstallerObservesABuildOnlySwap() throws {
    let app = try makeBundle(wrapped: true, short: "1.0", build: "47")
    defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

    let baseline = AppStoreAXInstaller.installedVersions(at: app)
    let inner = app.appendingPathComponent("Wrapper/Sample.app/Info.plist")
    try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleShortVersionString": "1.0",
                           "CFBundleVersion": "48"] as [String: Any],
        format: .xml, options: 0).write(to: inner)

    #expect(AppStoreAXInstaller.versionChanged(from: baseline, appPath: app))
}

/// `BackupManifest` walks the bundle from its root and looks each unreadable file
/// up in the seal, whose keys are relative to the bundle's interior. For a
/// wrapped app that interior is `Wrapper/<Inner>.app/`, not `Contents/`, and both
/// the seal's location and the prefix to strip move with it — get either wrong
/// and every shipped file reads as an unsealed dropping (or the reverse).
@Test func theSealIsFoundWhereAWrappedBundleKeepsIt() throws {
    let classic = try makeBundle(wrapped: false, short: "3.1", build: "310")
    defer { try? FileManager.default.removeItem(at: classic.deletingLastPathComponent()) }
    let iosOnMac = try makeBundle(wrapped: true, short: "1.0.7", build: "48")
    defer { try? FileManager.default.removeItem(at: iosOnMac.deletingLastPathComponent()) }

    #expect(BundleLayout.interiorPrefix(for: classic) == "Contents/")
    #expect(BundleLayout.codeResourcesURL(for: classic).path
            == classic.appendingPathComponent("Contents/_CodeSignature/CodeResources").path)

    // Read from the symlink's destination, so it lines up with a directory walk
    // of the same bundle — which yields Wrapper/…, never the WrappedBundle alias.
    #expect(BundleLayout.interiorPrefix(for: iosOnMac) == "Wrapper/Sample.app/")
    #expect(BundleLayout.codeResourcesURL(for: iosOnMac).path
            == iosOnMac.appendingPathComponent(
                "Wrapper/Sample.app/_CodeSignature/CodeResources").path)
}
