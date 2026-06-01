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
