import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `duo install` and an update the app asks about on its row and leaves out of
/// Update All (`UpdatePolicy.installConfirmation`): a vendor rewrite or a
/// license-boundary major. `--all` and `--yes` skip it with the command that
/// installs it on purpose; an app named without `--yes` is asked.
@Suite struct InstallConfirmationTests {

    private func workbench(version: String) -> InstalledApp {
        InstalledApp(
            name: "MySQLWorkbench", bundleID: "com.oracle.workbench.MySQLWorkbench",
            shortVersion: version, buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/MySQL Workbench.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// 8.0 → 26.7.0 is the rewrite (`BundleIDMigration.isRewrite`); 8.0.46 → 8.0.47
    /// is an old-line point release from the same source.
    private func offer(from installed: String = "8.0.47.CE", to latest: String) -> UpdateResult {
        UpdateResult(
            app: workbench(version: installed),
            remote: RemoteVersion(
                shortVersion: latest, version: nil,
                downloadURL: URL(string: "https://example.com/workbench.dmg"),
                sourceName: "Vendor", requiresManualInstaller: false,
                vendorInstallerKind: .dmg),
            status: .updateAvailable(latest: latest))
    }

    private func settings() -> Settings {
        Settings(
            updateSettings: UpdateSettings(
                appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning),
            ignoredKeys: [], skippedVersions: [:], customScanPaths: [],
            maxConcurrency: 12, testFlightDetection: .off, keepBackups: true,
            githubToken: nil, alcove: nil)
    }

    private func environment() -> InstallEnvironment {
        InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
    }

    @Test func allSkipsTheRewriteWithTheCommandThatInstallsIt() {
        let step = Install.confirmationStep(for: offer(to: "26.7.0"), named: false, assumeYes: true)
        #expect(step == .refuse(
            "8.0.47.CE → 26.7.0 replaces this app with the vendor's rewrite, whose features and "
                + "settings may differ — not part of --all; install it on its own: "
                + "duo install '/Applications/MySQL Workbench.app'"))
    }

    @Test func yesDoesNotCoverANamedRewrite() {
        guard case .refuse(let why) = Install.confirmationStep(
            for: offer(to: "26.7.0"), named: true, assumeYes: true) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(why.hasSuffix("--yes does not cover it; run duo install "
            + "'/Applications/MySQL Workbench.app' without --yes to confirm it"))
    }

    @Test func aNamedRewriteWithoutYesIsAsked() {
        #expect(Install.confirmationStep(for: offer(to: "26.7.0"), named: true, assumeYes: false)
            == .ask(.vendorRewrite))
    }

    @Test func anOrdinaryUpdateNeedsNoConfirmation() {
        #expect(Install.confirmationStep(
            for: offer(from: "8.0.46.CE", to: "8.0.47"), named: false, assumeYes: true) == .notNeeded)
    }

    /// The re-check right before the install answers the rewrite where the plan
    /// had a point release: nobody was asked, so it is skipped, not installed.
    /// Mutation: drop the confirmation check in `reconsider` → red.
    @Test func aRewriteFoundOnlyByTheRecheckIsSkipped() {
        let outcome = Install.reconsider(
            offered: offer(from: "8.0.46.CE", to: "8.0.47"), confirmed: offer(to: "26.7.0"),
            settings: settings(), environment: environment(), routes: [])
        guard case .skip(let why, _) = outcome else {
            Issue.record("expected a skip, got \(outcome)")
            return
        }
        #expect(why.contains("found on the re-check, not confirmed"))
    }

    @Test func aConfirmedRewriteProceeds() {
        let outcome = Install.reconsider(
            offered: offer(to: "26.7.0"), confirmed: offer(to: "26.7.0"),
            settings: settings(), environment: environment(), routes: [],
            approved: .vendorRewrite)
        guard case .proceed = outcome else {
            Issue.record("expected to proceed, got \(outcome)")
            return
        }
    }

    /// The plan names the question before the plan's own prompt.
    @Test func thePlanNotesTheQuestion() {
        var lines: [String] = []
        Install.describe(
            [Install.Planned(result: offer(to: "26.7.0"), route: .vendor, confirmation: .vendorRewrite)],
            refusals: [], print: { lines.append($0) })
        #expect(lines.contains(
            "      note: asks before installing — 8.0.47.CE → 26.7.0 replaces this app with the "
                + "vendor's rewrite, whose features and settings may differ"))
    }
}
