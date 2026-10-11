import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// What `duo verify-install` calls a fault in a download it read successfully.
/// The download itself is measured against the real vendor (WorkBuddy CN, keyed
/// back to its pre-5.5.4 id, reads as `bundleIDMismatch`); these pin the
/// judgement so it cannot quietly stop firing.
@Suite struct InstallVerifyJudgementTests {

    private func identity(
        bundleID: String? = "com.example.app", team: String? = "ABCDE12345",
        version: String? = "2.0"
    ) -> ArtifactInspection.Identity {
        ArtifactInspection.Identity(
            signedIdentifier: bundleID, bundleIdentifier: bundleID, teamIdentifier: team,
            shortVersion: version, bundleVersion: nil, architectures: ["arm64"],
            minimumSystemVersion: nil, sparklePublicKey: nil)
    }

    private func remote(
        version: String? = "2.0", trust: InstallTrust = .developerID
    ) -> RemoteVersion {
        RemoteVersion(
            shortVersion: version, version: nil,
            downloadURL: URL(string: "https://example.com/App.dmg"),
            sourceName: "Vendor", vendorInstallerKind: .dmg, installTrust: trust)
    }

    @Test func theDownloadTheRecipeNamesIsClean() {
        #expect(InstallVerify.warnings(
            identity: identity(), remote: remote(), recipeBundleID: "com.example.app").isEmpty)
    }

    /// WorkBuddy CN from 5.5.4 on: same vendor, same Team, another bundle id.
    @Test func anotherBundleIDIsAWarning() {
        let warnings = InstallVerify.warnings(
            identity: identity(bundleID: "com.example.renamed"), remote: remote(),
            recipeBundleID: "com.example.app")
        #expect(warnings.count == 1)
        #expect(warnings.first?.hasPrefix("bundleIDMismatch:") == true)
    }

    /// The plist is what recipes are keyed by; the signed identifier only stands
    /// in when the plist has none.
    @Test func theSignedIdentifierStandsInForAMissingPlistID() {
        var signedOnly = identity()
        signedOnly.bundleIdentifier = nil
        signedOnly.signedIdentifier = "com.example.other"
        #expect(InstallVerify.warnings(
            identity: signedOnly, remote: remote(), recipeBundleID: "com.example.app").count == 1)

        var signedOtherwise = identity()
        signedOtherwise.signedIdentifier = "com.example.app.signed"
        #expect(InstallVerify.warnings(
            identity: signedOtherwise, remote: remote(), recipeBundleID: "com.example.app").isEmpty)
    }

    @Test func noTeamIsAWarningOnTheDeveloperIDRoute() {
        let warnings = InstallVerify.warnings(
            identity: identity(team: nil), remote: remote(), recipeBundleID: "com.example.app")
        #expect(warnings.map { $0.prefix(16) } == ["noTeamIdentifier"])
    }

    /// An ad-hoc build on the digest-only route has no Team by design.
    @Test func noTeamIsExpectedOnTheDigestOnlyRoute() {
        #expect(InstallVerify.warnings(
            identity: identity(team: nil), remote: remote(trust: .publishedDigestOnly),
            recipeBundleID: "com.example.app").isEmpty)
    }

    /// A package has no bundle to read; its Team is reported separately.
    @Test func aPackageHasNothingToJudge() {
        #expect(InstallVerify.warnings(
            identity: nil, remote: remote(), recipeBundleID: "com.example.app").isEmpty)
    }

    @Test func aDifferentVersionIsANoteNotAWarning() {
        #expect(InstallVerify.notes(identity: identity(version: "2.0.1"), remote: remote()).count == 1)
        #expect(InstallVerify.notes(identity: identity(), remote: remote()).isEmpty)
    }
}

/// How a `duo verify-install` item reaches `Baseline` and `Reconcile`.
@Suite struct InstallVerifyFindingTests {

    private func item(
        _ status: InstallVerify.Status, stage: ArtifactInspection.Stage? = nil,
        warnings: [String] = []
    ) -> InstallVerify.Item {
        var item = InstallVerify.Item(
            recipeID: "vendor:com.example.app:stable", registry: "vendor",
            bundleID: "com.example.app", probeHost: "example.com", status: status)
        item.stage = stage
        item.detail = stage == nil ? nil : "it went wrong"
        item.warnings = warnings
        item.url = "https://cdn.example.com/App.dmg"
        item.version = "1.0"
        return item
    }

    /// Its own namespace, so it never shares a streak or an issue with the
    /// sweep's finding for the same recipe.
    @Test func idsAreNamespaced() {
        let finding = InstallVerify.finding(item(.ok))
        #expect(finding.recipeID == "install:vendor:com.example.app:stable")
        #expect(finding.registry == .install)
        #expect(finding.endpointHost == "cdn.example.com")
    }

    @Test func statusesMapToWhatTheBaselineCounts() {
        #expect(InstallVerify.finding(item(.ok)).status == .ok)
        #expect(InstallVerify.finding(item(.warn, warnings: ["identityChanged: …"])).status == .warn)
        // A dropped transfer is the network until a run of them says otherwise.
        #expect(InstallVerify.finding(item(.failed, stage: .download)).status == .infra)
        // A refusal is the link, not the network; a 5xx, 408 or 429 may pass.
        for (status, expected) in [(404, FindingStatus.broken), (403, .broken), (410, .broken),
                                   (500, .infra), (503, .infra), (408, .infra), (429, .infra)] {
            var refused = item(.failed, stage: .download)
            refused.httpStatus = status
            #expect(InstallVerify.finding(refused).status == expected, "HTTP \(status)")
        }
        #expect(InstallVerify.finding(item(.failed, stage: .checksum)).status == .broken)
        #expect(InstallVerify.finding(item(.failed, stage: .unpack)).status == .broken)
        #expect(InstallVerify.finding(item(.failed, stage: .signature)).status == .broken)
        // Resolving the installer is the sweep's finding to file.
        #expect(InstallVerify.finding(item(.unresolved)).status == .skipped)
        #expect(InstallVerify.finding(item(.skipped)).status == .skipped)
    }

    /// The sweep files a renamed release asset under its own id; filing it here
    /// too would open two issues for one problem.
    @Test func installPatternWarningsAreTheSweepsToFile() {
        let renamed = "installAssetRenamed: a newer release's macOS installer no longer matches …"
        let only = InstallVerify.finding(item(.warn, warnings: [renamed]))
        #expect(only.status == .ok)
        #expect(only.warnings.isEmpty)
        let mixed = InstallVerify.finding(item(.warn, warnings: [renamed, "identityChanged: Team A → B"]))
        #expect(mixed.status == .warn)
        #expect(mixed.warnings == ["identityChanged: Team A → B"])
    }

    @Test func aFailureCarriesItsStage() {
        let finding = InstallVerify.finding(item(.failed, stage: .checksum))
        #expect(finding.failureKind == "install.checksum")
        #expect(finding.failureDetail == "it went wrong")
    }

    /// No version: the baseline would otherwise repeat the sweep's own
    /// "went backwards" check under a second id.
    @Test func noVersionReachesTheBaseline() {
        #expect(InstallVerify.finding(item(.ok)).version == nil)
    }

    /// An installer issue reproduces with the command that found it.
    @Test func anInstallerIssueSaysHowToReproduceIt() {
        let finding = InstallVerify.finding(item(.failed, stage: .checksum))
        #expect(Reconcile.reproduce(finding, samples: true).contains("duo verify-install --only com.example.app"))
        let body = Reconcile.body(for: finding, entry: Baseline.Entry())
        #expect(body.contains("`duo verify-install`"))
        #expect(!body.contains("duo verify --install"))
    }
}

/// Which installers a run leaves undownloaded (#1203), and that leaving one
/// undownloaded changes nothing anyone keeps: no streak, no issue, no identity.
@Suite struct InstallVerifyIncrementalTests {

    private let day1 = Date(timeIntervalSince1970: 1_790_000_000)
    private let url = "https://downloads.example.com/App-1.0.dmg"

    private func recorded(
        version: String? = "1.0", url: String? = "https://downloads.example.com/App-1.0.dmg"
    ) -> InstallIdentities.Recorded {
        InstallIdentities.Recorded(
            bundleIdentifier: "com.example.app", signedIdentifier: "com.example.app",
            teamIdentifier: "ABCDE12345", packageTeamIdentifier: nil, sparklePublicKey: nil,
            architectures: ["arm64"], firstSeenAt: day1, firstSeenVersion: version,
            lastSeenAt: day1, lastSeenVersion: version, lastSeenURL: url)
    }

    private func previous(
        recorded: InstallIdentities.Recorded?, _ adjust: (inout Baseline.Entry) -> Void = { _ in }
    ) -> InstallVerify.Previous {
        var entry = Baseline.Entry()
        adjust(&entry)
        return InstallVerify.Previous(recorded: recorded, baseline: entry)
    }

    @Test func theSameVersionAndURLWithACleanPastIsSkipped() {
        #expect(InstallVerify.skipsDownload(
            version: "1.0", url: url, previous: previous(recorded: recorded())))
    }

    @Test func noRecordedIdentityIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", url: url, previous: previous(recorded: nil)))
    }

    @Test func aNewVersionIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: "1.1", url: url, previous: previous(recorded: recorded())))
    }

    @Test func aNewURLIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", url: "https://downloads.example.com/App-1.0-b.dmg",
            previous: previous(recorded: recorded())))
    }

    /// An entry written before `lastSeenURL` existed matches no URL.
    @Test func anEntryWithNoURLIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", url: url, previous: previous(recorded: recorded(url: nil))))
    }

    /// Two nils are not the same version.
    @Test func noVersionIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: nil, url: url, previous: previous(recorded: recorded(version: nil))))
    }

    @Test func noBaselineEntryIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", url: url,
            previous: InstallVerify.Previous(recorded: recorded(), baseline: nil)))
    }

    /// A warning or failure last time: skipping would freeze the streak, and a
    /// fix would never register.
    @Test func aRunningStreakIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", url: url,
            previous: previous(recorded: recorded()) { $0.consecutiveActionable = 1 }))
    }

    @Test func anUnreachableStreakIsDownloaded() {
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", url: url,
            previous: previous(recorded: recorded()) { $0.consecutiveInfra = 1 }))
    }

    /// Only a clean download closes an issue.
    @Test func anOpenIssueIsDownloaded() {
        let closed = day1
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", url: url,
            previous: previous(recorded: recorded()) { $0.issueNumber = 42 }))
        #expect(InstallVerify.skipsDownload(
            version: "1.0", url: url,
            previous: previous(recorded: recorded()) { $0.issueNumber = 42; $0.closedAt = closed }))
    }

    // MARK: a skipped installer disturbs nothing

    private func skippedItem() -> InstallVerify.Item {
        var item = InstallVerify.Item(
            recipeID: "vendor:a", registry: "vendor", bundleID: "com.example.app",
            probeHost: "downloads.example.com", status: .skipped,
            detail: "unchanged since 2026-09-21: same version and URL, last outcome clean — not downloaded")
        item.version = "1.0"
        item.url = url
        return item
    }

    @Test func aSkippedInstallerIsASkippedFinding() {
        let finding = InstallVerify.finding(skippedItem())
        #expect(finding.status == .skipped)
        #expect(finding.version == nil)
    }

    @Test func aSkippedInstallerLeavesTheBaselineAlone() {
        var baseline = Baseline()
        var entry = Baseline.Entry()
        entry.consecutiveActionable = 1
        entry.consecutiveInfra = 2
        entry.infraSince = day1
        entry.lastSignature = "install.download"
        entry.issueNumber = 7
        entry.sweepsSinceComment = 3
        let id = InstallVerify.findingID("vendor:a")
        baseline.entries[id] = entry
        baseline.reconcile(InstallVerify.finding(skippedItem()))
        let after = baseline.entries[id]
        #expect(after?.consecutiveActionable == 1)
        #expect(after?.consecutiveInfra == 2)
        #expect(after?.infraSince == day1)
        #expect(after?.lastSignature == "install.download")
        #expect(after?.issueNumber == 7)
        #expect(after?.closedAt == nil)
        #expect(after?.sweepsSinceComment == 3)
        #expect(after?.lastGoodVersion == nil)
    }

    @Test func aSkippedInstallerClosesNoIssue() {
        var entry = Baseline.Entry()
        entry.issueNumber = 7
        let action = Reconcile.decide(
            InstallVerify.finding(skippedItem()), entry: entry, reportable: true, now: day1)
        guard case .none = action else {
            Issue.record("expected no action, got \(action)")
            return
        }
    }

    @Test func aSkippedInstallerLeavesItsIdentityAlone() {
        var store = InstallIdentities()
        store.entries["vendor:a"] = recorded(url: nil)
        let before = store
        var item = skippedItem()
        item.identity = ArtifactInspection.Identity(
            signedIdentifier: "com.example.other", bundleIdentifier: "com.example.other",
            teamIdentifier: "ZZZZZ99999", shortVersion: "1.0", bundleVersion: nil,
            architectures: ["arm64"], minimumSystemVersion: nil, sparklePublicKey: nil)
        InstallVerify.compare(&item, with: &store, at: day1.addingTimeInterval(86_400))
        #expect(store == before)
        #expect(item.status == .skipped)
        #expect(item.warnings.isEmpty)
    }

    /// Pruning goes by the registries, not by what a run downloaded.
    @Test func aSkippedInstallerIsNotPruned() {
        var baseline = Baseline()
        let id = InstallVerify.findingID("vendor:a")
        baseline.reconcile(InstallVerify.finding(skippedItem()))
        _ = baseline.prune(keeping: [id, InstallVerify.findingID("vendor:b")])
        #expect(baseline.entries[id] != nil)
        var store = InstallIdentities()
        store.entries["vendor:a"] = recorded()
        store.prune(keeping: ["vendor:a"])
        #expect(store.entries["vendor:a"] != nil)
    }

    /// The report's table lists what needs reading; an installer left alone
    /// because nothing changed is only counted.
    @Test func theMarkdownTableLeavesOutUnchangedInstallers() {
        let credential = InstallVerify.Item(
            recipeID: "vendor:secret", registry: "vendor", bundleID: "com.example.secret",
            probeHost: "example.com", status: .skipped, detail: "credential-bearing — never fetched")
        let report = InstallVerify.Report(
            generatedAt: day1, seconds: 1, bytes: 0, minimumFreeBytes: nil, hostConcurrency: 3,
            items: [skippedItem(), credential])
        let markdown = InstallVerify.markdown(report)
        #expect(!markdown.contains("`vendor:a`"))
        #expect(markdown.contains("`vendor:secret`"))
        #expect(markdown.contains("**skipped** 2"))
    }
}
