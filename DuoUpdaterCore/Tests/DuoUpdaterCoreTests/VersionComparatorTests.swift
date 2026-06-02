import Testing
@testable import DuoUpdaterCore

@Test func basicOrdering() {
    #expect(VersionComparator.isNewer("1.2.3", than: "1.2.2"))
    #expect(VersionComparator.isNewer("1.3.0", than: "1.2.9"))
    #expect(VersionComparator.isNewer("2.0", than: "1.9.9"))
    #expect(!VersionComparator.isNewer("1.2.3", than: "1.2.3"))
    #expect(!VersionComparator.isNewer("1.2.2", than: "1.2.3"))
}

@Test func missingComponentsAreZero() {
    #expect(VersionComparator.compare("1.2", "1.2.0") == .orderedSame)
    #expect(VersionComparator.isNewer("1.2.1", than: "1.2"))
}

@Test func buildNumbers() {
    #expect(VersionComparator.isNewer("45830", than: "45821"))
    #expect(!VersionComparator.isNewer("45821", than: "45830"))
}

@Test func preReleaseTags() {
    // A final release beats its own pre-release.
    #expect(VersionComparator.isNewer("2.0", than: "2.0-beta1"))
    #expect(VersionComparator.isNewer("2.0-beta2", than: "2.0-beta1"))
}

@Test func evaluatePrefersBuildVersion() {
    let app = InstalledApp(
        name: "X", bundleID: "x", shortVersion: "1.0", buildVersion: "100",
        path: .init(fileURLWithPath: "/X.app"), isMASApp: false, sparkleFeedURL: nil
    )
    let remote = RemoteVersion(
        shortVersion: "1.1", version: "110", downloadURL: nil, sourceName: "Test"
    )
    #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .updateAvailable(latest: "1.1"))
}

/// A vendor that folds the build into its version string (Oray AweSun:
/// "16.5.0.30757") must compare equal to a bundle that splits it into short
/// "16.5.0" + build "30757" — otherwise the row shows a perpetual update even
/// right after a successful install. The probe has no separate build version
/// (remote.version == nil), so this exercises the short-version fallback.
@Test func evaluateFoldsBuildIntoVendorVersion() {
    func aweSun(short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "AweSun", bundleID: "com.oray.sunlogin.macclient",
            shortVersion: short, buildVersion: build,
            path: .init(fileURLWithPath: "/AweSun.app"), isMASApp: false, sparkleFeedURL: nil)
    }
    let remote = RemoteVersion(
        shortVersion: "16.5.0.30757", version: nil, downloadURL: nil, sourceName: "Vendor")

    // Installed == target (short 16.5.0 + build 30757) → current, not "update".
    #expect(UpdateChecker.evaluate(installed: aweSun(short: "16.5.0", build: "30757"), remote: remote)
        == .upToDate)
    // Older build of the same marketing version → still detected.
    #expect(UpdateChecker.evaluate(installed: aweSun(short: "16.5.0", build: "30000"), remote: remote)
        == .updateAvailable(latest: "16.5.0.30757"))
    // Older marketing version → still detected.
    #expect(UpdateChecker.evaluate(installed: aweSun(short: "16.3.0", build: "29530"), remote: remote)
        == .updateAvailable(latest: "16.5.0.30757"))
}

/// The build-folding fallback must NOT make a genuinely-behind normal app (whose
/// short version is simply older) look current.
@Test func evaluateBuildFoldingDoesNotMaskRealUpdate() {
    let app = InstalledApp(
        name: "X", bundleID: "x", shortVersion: "1.96.0", buildVersion: "171",
        path: .init(fileURLWithPath: "/X.app"), isMASApp: false, sparkleFeedURL: nil)
    let remote = RemoteVersion(
        shortVersion: "1.97.0", version: nil, downloadURL: nil, sourceName: "Vendor")
    #expect(UpdateChecker.evaluate(installed: app, remote: remote)
        == .updateAvailable(latest: "1.97.0"))
}
