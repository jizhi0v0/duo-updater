import Testing
import Foundation
@testable import DuoUpdaterCore

/// Whether a staged self-update should stop us installing.
///
/// The rule that a TRAILING staged build still blocks comes from a real outcome:
/// on 2026-08-22 the mini installed ChatGPT 6971 and its own Sparkle applied 6962
/// at 14:53, finishing on the OLDER version. Every "is it newer?" filter is blind
/// to that build, because 6962 is not newer than 6971.
///
/// Note what this gate does and does not cover. In that incident the staging began
/// after our install, so no check could have seen it; the gate covers the opposite
/// order — the app staged first, we install second. On Sparkle it is narrower
/// still, since `sparkleStagedBundle` requires a parked installer, which appears
/// only once the app has begun installing.
struct StagedBlocksInstallTests {

    private func result(source: String, version: String = "26.818.41509") -> UpdateResult {
        let app = InstalledApp(
            name: "ChatGPT", bundleID: "com.openai.codex",
            shortVersion: "26.818.41705", buildVersion: "6971",
            path: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
        return UpdateResult(
            app: app,
            remote: RemoteVersion(
                shortVersion: version, version: nil,
                downloadURL: URL(string: "https://example.com/a.zip"),
                sourceName: source),
            status: .updateAvailable(latest: version))
    }

    private func staged(_ version: String, build: String?) -> StagedSelfUpdate {
        StagedSelfUpdate(
            version: version, buildVersion: build,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/staged/ChatGPT.app"))
    }

    /// The mini's exact shape: staged build TRAILS what is on disk, and still wins,
    /// because the parked installer applies it on quit regardless.
    @Test func aStagedBuildOlderThanInstalledStillBlocks() throws {
        let blocking = UpdatePolicy.stagedBlocksInstall(
            result(source: "Vendor"), staged: staged("26.818.41509", build: "6962"))
        #expect(blocking != nil)
    }

    @Test func aStagedBuildNewerThanInstalledBlocksToo() throws {
        let blocking = UpdatePolicy.stagedBlocksInstall(
            result(source: "Sparkle"), staged: staged("27.0.0", build: "7100"))
        #expect(blocking != nil)
    }

    @Test func nothingStagedDoesNotBlock() {
        #expect(UpdatePolicy.stagedBlocksInstall(result(source: "Vendor"), staged: nil) == nil)
    }

    /// Routes we do not swap ourselves must not be blocked by a staging directory
    /// belonging to a different mechanism — brew and the App Store own the bundle.
    @Test func onlyRoutesWeSwapOurselvesAreBlocked() {
        for source in ["Homebrew", "App Store", "Toolbox"] {
            #expect(UpdatePolicy.stagedBlocksInstall(
                result(source: source), staged: staged("9.9.9", build: "999")) == nil,
                "\(source) should not be blocked")
        }
        for source in ["Vendor", "GitHub", "Sparkle"] {
            #expect(UpdatePolicy.stagedBlocksInstall(
                result(source: source), staged: staged("9.9.9", build: "999")) != nil,
                "\(source) should be blocked")
        }
    }

    /// `actionableStaged` and this must not be confused. The former gates the
    /// **Relaunch** affordance and answers "would a relaunch get me current?" —
    /// comparing the staged build against the feed's latest, not against what is
    /// installed. This one answers "would installing survive?", which a staged
    /// build defeats however it compares.
    @Test func theTwoQuestionsAreDifferent() {
        // Feed offers 27.0.0; the app has only staged 26.818.41509.
        let r = result(source: "Vendor", version: "27.0.0")
        let behind = staged("26.818.41509", build: "6962")

        // Relaunching would still leave you a release behind, so it is not offered…
        #expect(UpdatePolicy.actionableStaged(r, staged: behind) == nil)
        // …yet installing now is still undone the moment the app quits.
        #expect(UpdatePolicy.stagedBlocksInstall(r, staged: behind) != nil)
    }
}

extension StagedBlocksInstallTests {

    /// The regression dropping the "must be newer" filter would otherwise introduce.
    /// Once an app applies its own staged update, the staging directory can linger;
    /// a staged build equal to what is on disk has already landed and must not block
    /// installs forever.
    @Test func anAlreadyAppliedStagedBuildDoesNotBlock() {
        // installed build is 6971 (see `result`), and the leftover says the same
        let r = result(source: "Vendor")
        #expect(UpdatePolicy.stagedBlocksInstall(
            r, staged: staged("26.818.41705", build: "6971")) == nil)
    }
}

extension StagedBlocksInstallTests {

    /// `actionableStaged` gates the **Relaunch** button, so it must never point at a
    /// build older than what is installed — relaunching into that applies a
    /// DOWNGRADE, and `relaunchStagedUpdate` waits for the on-disk version to move
    /// *forward*, so it would spin for its full 180 s timeout and report failure for
    /// a swap that actually happened.
    ///
    /// Today no caller can produce this: both sites fill the staged map through
    /// `staged(requireNewerThanInstalled:)` at its default of `true`. That made this
    /// safe by construction — until this change added a `false` path for the install
    /// gate. The invariant now depends on callers passing the right argument, which
    /// is exactly the kind of thing that should be pinned rather than assumed.
    @Test func relaunchIsNeverOfferedForABuildOlderThanInstalled() {
        // installed 6971 (see `result`), staged 6962, feed also offers 6962 —
        // so the "does it trail the latest?" test alone would say this is actionable.
        let r = result(source: "Vendor", version: "26.818.41509")
        let older = staged("26.818.41509", build: "6962")
        #expect(UpdatePolicy.actionableStaged(r, staged: older) == nil)
    }
}
