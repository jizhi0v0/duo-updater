import Foundation
import Testing
@testable import DuoUpdaterCore

/// "Skip this version" is supposed to decline exactly one release and let the
/// next one through. It was keyed on the marketing string, so for an app that
/// ships many builds under one name it declined *every* release after it —
/// silently, and persisted in preferences across restarts.
///
/// This was the most damaging instance of the frozen-marketing defect found on
/// 2026-08-28: nothing in the UI says an app has been silenced, and the user's
/// own action is what armed it.
@Suite struct SkippedVersionTests {

    private func app(build: String?) -> InstalledApp {
        InstalledApp(
            name: "Amp", bundleID: "com.ampcode.amp.macos",
            shortVersion: "1.0", buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/Amp.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
    }
    private func side(_ build: String?) -> VersionSide {
        VersionSide(marketing: "1.0", build: build)
    }
    private func store(_ app: InstalledApp, _ value: String) -> [String: String] {
        [InstallPreferenceKey.key(for: app): value]
    }

    /// The bug. Skipping build 129 must not decline build 130.
    @Test func skippingOneBuildDoesNotSilenceTheNextOne() {
        let amp = app(build: "129")
        let skipped = store(amp, VisibilityRules.skipKey(side("129")))

        #expect(VisibilityRules.isVersionSkipped(amp, version: side("129"),
                                                 skippedVersions: skipped),
                "the build that was skipped stays skipped")
        #expect(!VisibilityRules.isVersionSkipped(amp, version: side("130"),
                                                  skippedVersions: skipped),
                "a LATER build must still be offered — this is the whole bug")
    }

    /// An app with no `CFBundleVersion` at all: the marketing string is the whole
    /// identity, and skipping must keep working exactly as before.
    @Test func anAppWithNoBuildStillSkipsOnItsMarketingVersion() {
        let plain = InstalledApp(
            name: "Fixture", bundleID: "com.example.fixture",
            shortVersion: "1.7.3", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Fixture.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: false)
        let v = VersionSide(marketing: "1.7.3", build: nil)
        let skipped = store(plain, VisibilityRules.skipKey(v))

        #expect(VisibilityRules.isVersionSkipped(plain, version: v, skippedVersions: skipped))
        #expect(!VisibilityRules.isVersionSkipped(
            plain, version: VersionSide(marketing: "1.8.0"), skippedVersions: skipped))
    }

    /// Migration. An entry written by an older build is a bare marketing string.
    ///
    /// For an app that HAS a build it cannot say which one was skipped, so it
    /// stops matching — the user is offered that version once more and their next
    /// skip rewrites it. Honouring it instead is exactly the bug, so the one-time
    /// re-offer is the deliberate trade.
    @Test func aLegacyEntryIsNotHonouredWhenABuildCouldDisambiguateIt() {
        let amp = app(build: "129")
        let legacy = store(amp, "1.0")   // what a shipped build wrote

        #expect(!VisibilityRules.isVersionSkipped(amp, version: side("129"),
                                                  skippedVersions: legacy),
                "a bare \"1.0\" cannot name a build; honouring it silenced every release")
    }

    /// ...but a legacy entry for an app with no build is still the whole identity,
    /// so it must keep working rather than resurfacing.
    @Test func aLegacyEntryStillWorksWhereThereIsNoBuildToDisambiguate() {
        let plain = InstalledApp(
            name: "Fixture", bundleID: "com.example.fixture",
            shortVersion: "1.7.3", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Fixture.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: false)
        #expect(VisibilityRules.isVersionSkipped(
            plain, version: VersionSide(marketing: "1.7.3"),
            skippedVersions: store(plain, "1.7.3")))
    }

    /// Nothing skipped, nothing to compare: never report a skip.
    @Test func anEmptyVersionOrEmptyStoreIsNeverSkipped() {
        let amp = app(build: "129")
        #expect(!VisibilityRules.isVersionSkipped(amp, version: nil, skippedVersions: [:]))
        #expect(!VisibilityRules.isVersionSkipped(amp, version: VersionSide(),
                                                  skippedVersions: store(amp, "1.0 (129)")))
        #expect(!VisibilityRules.isVersionSkipped(amp, version: side("129"),
                                                  skippedVersions: [:]))
    }
}
