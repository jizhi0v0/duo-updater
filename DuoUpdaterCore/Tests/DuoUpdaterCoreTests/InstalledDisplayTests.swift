import Testing
import Foundation
@testable import DuoUpdaterCore

/// `UpdateResult.installedDisplay` — the label on the LEFT of every "installed →
/// available" row, in the menu bar, the workbench and `duo check`.
///
/// The invariant it has to keep is that both halves of that row name versions
/// from the same namespace. An app that versions itself in `CFBundleVersion`
/// breaks it the moment the left half reads `CFBundleShortVersionString`: nothing
/// is miscompared, but the user is shown a version they do not have.
struct InstalledDisplayTests {

    private func installed(
        short: String?, build: String?, vendorBuild: String? = nil
    ) -> InstalledApp {
        InstalledApp(
            name: "CapCut", bundleID: "com.lemon.lvoverseas",
            shortVersion: short, buildVersion: build,
            vendorBuildVersion: vendorBuild,
            path: URL(fileURLWithPath: "/Applications/CapCut.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .beta)
    }

    /// CapCut's beta bundle exactly as it sits on disk (2026-08-31): the marketing
    /// string is a stale `9.3.4545` while the build carries the version the app,
    /// Finder and the vendor all call it. Its recipe is `versionIsBuild` for that
    /// reason, so the remote half of the row is a build too — and the installed
    /// half has to follow it.
    @Test func aBuildOnlyRemoteNamesTheInstalledBuild() {
        let remote = RemoteVersion(
            shortVersion: nil, version: "9.4.0-beta6",
            downloadURL: nil, sourceName: "Vendor")
        let result = UpdateResult(
            app: installed(short: "9.3.4545", build: "9.4.0-beta5"), remote: remote,
            status: .updateAvailable(latest: "9.4.0-beta6"))

        #expect(result.installedDisplay == "9.4.0-beta5")
        // The whole point: one namespace on both sides of the arrow.
        #expect(result.remote?.displayVersion == "9.4.0-beta6")
    }

    /// The same shape when there is nothing to install — the "· up to date" line
    /// has to name the installed copy correctly too, not only the update row.
    @Test func anUpToDateBuildOnlyRowAlsoNamesTheBuild() {
        let remote = RemoteVersion(
            shortVersion: nil, version: "9.4.0-beta5",
            downloadURL: nil, sourceName: "Vendor")
        let result = UpdateResult(
            app: installed(short: "9.3.4545", build: "9.4.0-beta5"),
            remote: remote, status: .upToDate)
        #expect(result.installedDisplay == "9.4.0-beta5")
    }

    /// A `versionIsBuild` recipe that ALSO supplies a `displayVersionPattern` puts
    /// a marketing string in `shortVersion` deliberately, so the row already reads
    /// as marketing on the right (Android Studio: "2025.2.3 → 2026.1.2 RC 1").
    /// Switching the left half to `AI-252.28238…` would be the same bug pointed
    /// the other way.
    @Test func aRemoteCarryingAMarketingStringLeavesTheInstalledSideAlone() {
        let remote = RemoteVersion(
            shortVersion: "2026.1.2 RC 1", version: "AI-261.1234.5",
            downloadURL: nil, sourceName: "Vendor")
        let result = UpdateResult(
            app: installed(short: "2025.2.3", build: "AI-252.28238.7"), remote: remote,
            status: .updateAvailable(latest: "2026.1.2 RC 1"))
        #expect(result.installedDisplay == "2025.2.3")
    }

    /// Mozilla's pre-release recipes compare against `application.ini`'s `BuildID`,
    /// not `CFBundleVersion`. If a build-only remote ever reaches this path it must
    /// read the namespace the remote declares — reaching for `CFBundleVersion`
    /// would print a number from an unrelated system.
    @Test func theInstalledBuildIsReadFromTheRemotesOwnNamespace() {
        let remote = RemoteVersion(
            shortVersion: nil, version: "20260829211045", buildNamespace: .vendor,
            downloadURL: nil, sourceName: "Vendor")
        let result = UpdateResult(
            app: installed(short: "157.0a1", build: "15726.8.29",
                           vendorBuild: "20260828211045"),
            remote: remote, status: .updateAvailable(latest: "20260829211045"))
        #expect(result.installedDisplay == "20260828211045")
    }

    /// A source that names the installed build itself still wins — Xcode on disk
    /// says only "27.0" and which beta that is exists nowhere in the bundle.
    @Test func aSourceSuppliedInstalledNameStillWins() {
        let remote = RemoteVersion(
            shortVersion: nil, version: "27A5300b",
            downloadURL: nil, installedDisplayVersion: "27.0 beta 1",
            sourceName: "Xcode Releases")
        let result = UpdateResult(
            app: installed(short: "27.0", build: "27A5194q"), remote: remote,
            status: .updateAvailable(latest: "27A5300b"))
        #expect(result.installedDisplay == "27.0 beta 1")
    }

    /// No remote at all, or a remote with no build to speak of, keeps the old
    /// behaviour: the marketing version.
    @Test func withoutABuildOnlyRemoteTheMarketingVersionIsShown() {
        #expect(UpdateResult(
            app: installed(short: "9.3.4545", build: "9.4.0-beta5"),
            remote: nil, status: .unknown).installedDisplay == "9.3.4545")

        let marketingRemote = RemoteVersion(
            shortVersion: "9.5.0", version: nil, downloadURL: nil, sourceName: "Vendor")
        #expect(UpdateResult(
            app: installed(short: "9.3.4545", build: "9.4.0-beta5"),
            remote: marketingRemote,
            status: .updateAvailable(latest: "9.5.0")).installedDisplay == "9.3.4545")
    }

    /// Derived from the registry rather than restating it: the fix keys on the
    /// remote being build-shaped, and that shape is produced by a `versionIsBuild`
    /// recipe with no `displayVersionPattern`. Assert CapCut's beta recipe really
    /// is one, so this test file stops meaning what it claims if the recipe is
    /// ever given a display pattern.
    @Test func capCutsBetaRecipeProducesABuildShapedRemote() throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.lemon.lvoverseas" && $0.channel == .beta
        })
        #expect(recipe.versionIsBuild)
        #expect(recipe.displayVersionPattern == nil)

        let remote = VendorProbeSource.makeRemoteVersion(
            recipe: recipe, version: "9.4.0-beta6", install: nil, plan: nil,
            resolvedDownload: nil)
        #expect(remote.shortVersion == nil)
        #expect(remote.version == "9.4.0-beta6")
    }
}
