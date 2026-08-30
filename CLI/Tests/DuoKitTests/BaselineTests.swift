import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// The baseline is the only part of the verifier that remembers anything, which
/// makes it the only part that can distinguish "broken" from "broken twice" and
/// "reads a version" from "reads a version that went backwards". Both of those
/// decisions gate whether a human gets paged, so both are pinned here.
@Suite struct BaselineTests {

    private func finding(
        _ id: String = "vendor:com.example.app:stable",
        status: FindingStatus, version: String? = nil, failureKind: String? = nil
    ) -> Finding {
        Finding(
            recipeID: id, registry: .vendor, bundleID: "com.example.app", channel: "stable",
            status: status, version: version, failureKind: failureKind,
            endpointHost: "example.invalid")
    }

    /// One bad sweep files nothing. Vendors have five-minute outages; issues are
    /// forever, and an issue tracker that cries wolf gets muted.
    @Test func aSingleFailureIsNotYetReportable() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        #expect(baseline.streak("vendor:com.example.app:stable") == 1)
        #expect(!baseline.isReportable("vendor:com.example.app:stable"))

        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        #expect(baseline.isReportable("vendor:com.example.app:stable"))
    }

    /// Recovery clears the streak, so a recipe that heals stops being reported
    /// without anyone touching the state by hand.
    @Test func aSuccessfulSweepClearsTheFailureStreak() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .broken, failureKind: "httpStatus404"))
        _ = baseline.reconcile(finding(status: .broken, failureKind: "httpStatus404"))
        #expect(baseline.isReportable("vendor:com.example.app:stable"))

        _ = baseline.reconcile(finding(status: .ok, version: "1.2.3"))
        #expect(baseline.streak("vendor:com.example.app:stable") == 0)
        #expect(!baseline.isReportable("vendor:com.example.app:stable"))
    }

    /// Infrastructure trouble must be inert against the *actionable* streak in
    /// both directions: it can't push a recipe over the threshold, and it can't
    /// reset a real failure streak that is still running. Getting the second half
    /// wrong would make a genuinely broken recipe unreportable forever on a flaky
    /// network.
    @Test func infraOutcomesNeitherAccumulateNorResetTheActionableStreak() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .infra))
        _ = baseline.reconcile(finding(status: .infra))
        _ = baseline.reconcile(finding(status: .infra))
        #expect(baseline.streak("vendor:com.example.app:stable") == 0)

        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        _ = baseline.reconcile(finding(status: .infra))
        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        #expect(baseline.streak("vendor:com.example.app:stable") == 2)
    }

    /// …but it is no longer inert against everything. A host that answers on no
    /// sweep at all, night after night, has been retired, and before this counter
    /// existed that case changed no state and so was invisible forever — the
    /// exact silent degradation the sweep was built to end.
    @Test func unreachabilityAccumulatesOnItsOwnCounter() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        let start = Date()
        for _ in 1...6 {
            _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        }
        // Enough sweeps, but the run is minutes old: still the network.
        #expect(!baseline.isInfraReportable(id, now: start.addingTimeInterval(3_600)),
                "a few bad sweeps in an hour is still the network")

        // Same sweeps, now five days in.
        let later = start.addingTimeInterval(Baseline.infraWindow + 60)
        #expect(baseline.isInfraReportable(id, now: later))
        #expect(baseline.infraStreak(id) == 6)
        #expect(baseline.entries[id]?.infraSince != nil)
    }

    /// The gate is wall-clock, but wall-clock alone breaks in the one case where
    /// the *sweep* is what stopped: after a week of downtime the first sweep back
    /// records `infraSince`, and the second — minutes later — would otherwise
    /// satisfy an elapsed-time test against a timestamp that is already days old.
    /// Two observations must never retire a host.
    @Test func aLongGapBetweenSweepsDoesNotRetireAHostOnTwoObservations() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        let start = Date()
        for _ in 1...2 {
            _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        }
        let wayLater = start.addingTimeInterval(Baseline.infraWindow * 2)
        #expect(!baseline.isInfraReportable(id, now: wayLater),
                "two sweeps is not evidence, however old the first one is")

        _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        #expect(baseline.isInfraReportable(id, now: wayLater),
                "the third observation clears the minimum")
    }

    /// The point of the change: the gate no longer moves when the sweep cadence
    /// does. The same five days of downtime reports either way, whether it was
    /// observed nightly or four times a day.
    @Test func theGateDoesNotMoveWithTheSweepCadence() {
        let start = Date()
        let later = start.addingTimeInterval(Baseline.infraWindow + 60)
        for sweepsOverTheWindow in [5, 20] {
            var baseline = Baseline()
            for _ in 1...sweepsOverTheWindow {
                _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
            }
            #expect(baseline.isInfraReportable("vendor:com.example.app:stable", now: later),
                    "\(sweepsOverTheWindow) sweeps across the same five days must report")
        }
    }

    /// Any answer at all — even a broken one — is proof the host is still there,
    /// so it clears the unreachable streak. Without this a recipe that failed to
    /// parse once every few nights would eventually be reported as a dead host.
    @Test func reachingTheHostAtAllClearsTheUnreachableStreak() {
        let id = "vendor:com.example.app:stable"
        for reachable in [FindingStatus.ok, .broken, .warn] {
            var baseline = Baseline()
            let start = Date()
            let later = start.addingTimeInterval(Baseline.infraWindow + 60)
            for _ in 1...6 {
                _ = baseline.reconcile(finding(status: .infra))
            }
            #expect(baseline.isInfraReportable(id, now: later))

            _ = baseline.reconcile(finding(status: reachable, version: "1.0.0",
                                           failureKind: "versionPatternNoMatch"))
            #expect(!baseline.isInfraReportable(id, now: later),
                    "\(reachable.rawValue) proves the host is up")
            #expect(baseline.infraStreak(id) == 0)
            #expect(baseline.entries[id]?.infraSince == nil)
        }
    }

    /// `skipped` means we never looked, which is not evidence of anything. A
    /// credential-bearing recipe is skipped on every single sweep, so counting
    /// those would report every one of them as a dead host within a week.
    @Test func skippedSweepsAreNotEvidenceOfADeadHost() {
        var baseline = Baseline()
        for _ in 1...60 {
            _ = baseline.reconcile(finding(status: .skipped))
        }
        #expect(baseline.infraStreak("vendor:com.example.app:stable") == 0)
        #expect(!baseline.isInfraReportable("vendor:com.example.app:stable",
                                            now: Date().addingTimeInterval(Baseline.infraWindow * 3)))
    }

    /// An unreachable sweep in the middle of a broken streak must not make the
    /// next broken sweep look like the failure "changed shape" — that comparison
    /// drives a comment, and a comment per network blip is the noise this whole
    /// design exists to avoid.
    @Test func anInfraSweepDoesNotDisturbTheActionableSignature() {
        var baseline = Baseline()
        let id = "vendor:com.example.app:stable"
        _ = baseline.reconcile(finding(status: .broken, failureKind: "versionPatternNoMatch"))
        let signature = baseline.entries[id]?.lastSignature
        _ = baseline.reconcile(finding(status: .infra, failureKind: "transport"))
        #expect(baseline.entries[id]?.lastSignature == signature)
    }

    /// A version going backwards is the fingerprint of a pattern that started
    /// matching a different, shorter thing on the page. Nothing else detects it:
    /// the answer is well-formed, the fetch succeeded, and in isolation it looks
    /// completely healthy.
    @Test func aVersionGoingBackwardsIsFlagged() {
        var baseline = Baseline()
        #expect(baseline.reconcile(finding(status: .ok, version: "4.7.9")) == nil)

        let complaint = baseline.reconcile(finding(status: .ok, version: "4.7"))
        #expect(complaint?.contains("BACKWARDS") == true)
        #expect(complaint?.contains("4.7.9") == true)
    }

    @Test func movingForwardOrStandingStillIsNotFlagged() {
        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .ok, version: "4.7.9"))
        #expect(baseline.reconcile(finding(status: .ok, version: "4.8.0")) == nil)
        #expect(baseline.reconcile(finding(status: .ok, version: "4.8.0")) == nil)
    }

    @Test func baselineRoundTripsThroughDisk() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-baseline-\(UUID().uuidString)/baseline.json")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }

        var baseline = Baseline()
        _ = baseline.reconcile(finding(status: .ok, version: "1.0.0"))
        _ = baseline.reconcile(finding(status: .broken, failureKind: "httpStatus404"))
        baseline.entries["vendor:com.example.app:stable"]?.issueNumber = 42
        try baseline.save(to: path)

        let reloaded = Baseline.load(from: path)
        let entry = try #require(reloaded.entries["vendor:com.example.app:stable"])
        #expect(entry.lastGoodVersion == "1.0.0")
        #expect(entry.consecutiveActionable == 1)
        #expect(entry.issueNumber == 42)
    }

    /// A missing or corrupt baseline must degrade to "no history", never crash a
    /// scheduled run.
    @Test func aMissingBaselineIsEmptyRatherThanFatal() {
        let missing = Baseline.load(
            from: URL(fileURLWithPath: "/nonexistent/duo/baseline.json"))
        #expect(missing.entries.isEmpty)
    }
}

/// The noise filters. Every one of these exists because its absence produced a
/// false positive on a real sweep — an issue tracker full of correct behaviour
/// is worse than no tracker at all.
@Suite struct NoiseFilterTests {

    /// JetBrains keys release notes to the major version (`2026.2`) while the
    /// probe reads the build (`2026.2.0.1`); Toolbox publishes marketing versions
    /// against build-numbered installs. Comparing full strings flagged six
    /// recipes, five of which were working exactly as designed.
    @Test func ordinaryChangelogLagIsNotFlagged() {
        let ordinary = [
            ("2026.2", "2026.2.0.1"),           // IntelliJ: notes are per-major
            ("3.6.4", "3.6.4.86641"),           // Toolbox: marketing vs build
            ("262.132.29", "262.132.34"),       // Air: one patch behind
            ("0.2026.08.05.09.03", "0.2026.08.05.09.03.01"),
        ]
        for (entry, detected) in ordinary {
            #expect(
                Verify.changelogLagComplaint(entry: entry, detected: detected) == nil,
                "\(entry) vs \(detected) should be treated as normal lag")
        }
    }

    /// Recipes whose vendor doesn't number releases capture a headline into the
    /// version group on purpose. Comparing a sentence to a version number
    /// produces confident nonsense.
    @Test func changelogTitlesAreNotComparedAsVersions() {
        #expect(Verify.changelogLagComplaint(
            entry: "AI credit user limits and credit requests", detected: "126.7.10") == nil)
        #expect(Verify.changelogLagComplaint(
            entry: "Share context with Custom Agents", detected: "7.29.0") == nil)
    }

    // MARK: - phantom updates

    /// LocalSend's regression, in the shape the check sees it. v1.18.1 was
    /// published 2026-08-12 carrying only Android artifacts; Homebrew's cask
    /// stayed on 1.18.0 because there was no macOS build to package, and would
    /// have stayed there forever. Eight days in it is still ordinary brew lag;
    /// past the pickup window it is the tell that the version isn't real here.
    @Test func aVersionHomebrewNeverPicksUpIsFlaggedAsPhantom() {
        let published = Date(timeIntervalSince1970: 1_786_000_000)  // 2026-08-12
        func complain(daysLater: Int) -> String? {
            Verify.phantomVersionComplaint(
                caskToken: "localsend", caskVersion: "1.18.0", version: "1.18.1",
                publishedAt: published,
                now: published.addingTimeInterval(Double(daysLater) * 86_400))
        }
        // Inside the window this is just brew being brew — the whole reason the
        // ahead direction went unchecked for so long.
        #expect(complain(daysLater: 1) == nil)
        #expect(complain(daysLater: 8) == nil)
        // Past it, nothing else explains the gap.
        #expect(complain(daysLater: 14)?.contains("may not exist for macOS") == true)
    }

    /// The check must stay silent on the healthy case it most resembles: a cask
    /// that simply caught up, and a source that carries no publish date at all
    /// (guessing there would fire on every recipe the night it updates).
    @Test func phantomCheckStaysQuietWhenBrewAgreesOrTheDateIsUnknown() {
        let published = Date(timeIntervalSince1970: 1_786_000_000)
        #expect(Verify.phantomVersionComplaint(
            caskToken: "localsend", caskVersion: "1.18.1", version: "1.18.1",
            publishedAt: published,
            now: published.addingTimeInterval(365 * 86_400)) == nil)
        #expect(Verify.phantomVersionComplaint(
            caskToken: "localsend", caskVersion: "1.18.0", version: "1.18.1",
            publishedAt: nil, now: Date()) == nil)
        // Brew's `version,build` spelling. Flameshot's cask reads `14.0.0,14.0`
        // against our 14.0.0 — identical upstream versions that compared raw look
        // like we are a release ahead. The first full sweep with this check filed
        // exactly this, which is what the noise gate is for.
        let old = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(Verify.phantomVersionComplaint(
            caskToken: "flameshot", caskVersion: "14.0.0,14.0", version: "14.0.0",
            publishedAt: old, now: old.addingTimeInterval(61 * 86_400)) == nil)
    }

    /// …but a changelog a whole release behind still is.
    @Test func aChangelogAWholeReleaseBehindIsFlagged() {
        let complaint = Verify.changelogLagComplaint(entry: "1.85", detected: "1.123.4")
        #expect(complaint?.contains("trails") == true)
    }

    /// Issue #88: the complaint that can never clear.
    ///
    /// WorkBuddy's international docs site carries two entries and stops at 5.2.7
    /// while its own endpoint ships 5.4.2 — verified live, and the identical
    /// pattern returns 58 entries from the Chinese site, so the recipe is right
    /// and the vendor is the stale one. Every sweep flagged it; every sweep
    /// re-filed a "recipe degraded" issue against working code.
    @Test func anAcknowledgedVendorLagIsNotFlagged() {
        #expect(Verify.changelogLagComplaint(
            entry: "5.2.7", detected: "5.4.2", acknowledged: "5.2.7") == nil)
    }

    /// …and the acknowledgement is deliberately NOT an off switch, which is the
    /// only reason it is safe to have. It holds for exactly the entry it names,
    /// so the check comes back the moment the page moves in either direction:
    /// backward means the pattern slipped to an older section (the failure this
    /// check exists for, now on a recipe nobody is watching), forward means the
    /// vendor published and a human should re-read the situation.
    @Test func anAcknowledgementDoesNotSilenceTheRecipeForever() {
        // The pattern slipped to an older section.
        #expect(Verify.changelogLagComplaint(
            entry: "4.7.5", detected: "5.4.2", acknowledged: "5.2.7")?.contains("trails") == true)
        // The vendor published something newer, but still not current.
        #expect(Verify.changelogLagComplaint(
            entry: "5.3.0", detected: "5.4.2", acknowledged: "5.2.7")?.contains("trails") == true)
        // And an acknowledgement never invents a complaint where there was none:
        // once the vendor catches up the check passes on its own merits.
        #expect(Verify.changelogLagComplaint(
            entry: "5.4.2", detected: "5.4.2", acknowledged: "5.2.7") == nil)
    }

    /// Derived from the registry rather than a hand-written list, so an
    /// acknowledgement added later is covered too: this field silences a real
    /// detector, so every use of it has to be an entry that some page actually
    /// serves, not a wildcard or a leftover from a vendor who has since caught up.
    @Test func everyAcknowledgedStaleEntryIsAConcreteVersion() {
        let acknowledged = ChangelogRecipeRegistry.recipes
            .compactMap { recipe in recipe.acknowledgedStaleEntry.map { (recipe.recipeID, $0) } }
        for (recipeID, entry) in acknowledged {
            #expect(entry.first?.isNumber == true,
                    "\(recipeID) acknowledges '\(entry)', which is not version-shaped — changelogLagComplaint only ever compares version-shaped entries, so this can only be a typo that silences nothing or a wildcard that silences everything")
        }
        // The one this shipped for. Pinned by bundle id rather than by count, so
        // adding a second acknowledgement elsewhere does not have to touch this.
        #expect(acknowledged.contains { $0.0.contains("com.workbuddy.workbuddy-ai") })
    }

    /// Codex numbers builds and notes alike as `YY.MDD`, so the date lands in the
    /// slot the major.minor comparison uses and one publishing cycle looks like a
    /// whole release. 26.727 → 26.803 is seven days: their notes come out weekly.
    @Test func aDateNumberedChangelogIsJudgedInDaysNotReleases() {
        #expect(Verify.changelogLagComplaint(entry: "26.727", detected: "26.803.41515") == nil)
        #expect(Verify.changelogLagComplaint(entry: "25.1215", detected: "26.103") == nil)
        // Only a gap no publishing cadence explains still counts.
        let complaint = Verify.changelogLagComplaint(entry: "26.115", detected: "26.803.41515")
        #expect(complaint?.contains("200 days") == true)
    }

    /// The date reading has to be sure of itself: a two-digit major with a
    /// three-digit minor is not a date when the minor is not a valid `MDD`.
    @Test func versionsThatOnlyLookLikeDatesAreNotReadAsDates() {
        #expect(Verify.buildDate("26.803") != nil)
        #expect(Verify.buildDate("26.1215") != nil)
        #expect(Verify.buildDate("26.099") == nil)     // month 0
        #expect(Verify.buildDate("26.1332") == nil)    // month 13
        #expect(Verify.buildDate("26.845") == nil)     // day 45
        #expect(Verify.buildDate("2026.2") == nil)     // JetBrains major.minor
        #expect(Verify.buildDate("3.6.4") == nil)
    }
}

/// Pruning is the only operation that DELETES from the baseline, and it runs
/// unattended on every sweep, so each guard on it is pinned rather than trusted.
@Suite struct BaselinePruneTests {

    private func baseline(_ ids: [String]) -> Baseline {
        var b = Baseline()
        for id in ids { b.entries[id] = Baseline.Entry() }
        return b
    }

    @Test func dropsRowsNoRecipeProducesAnyMore() {
        var b = baseline(["vendor:a:stable", "changelog:gone:-", "github:o/r:stable"])
        let out = b.prune(keeping: ["vendor:a:stable", "github:o/r:stable"])
        #expect(out.removed == ["changelog:gone:-"])
        #expect(b.entries.keys.sorted() == ["github:o/r:stable", "vendor:a:stable"])
    }

    /// The real shape this exists for: a recipe that was re-keyed rather than
    /// deleted. Claude Desktop's split into `:ga` + `:rollout` left the bare
    /// `:stable` row behind reading as nine-days-stale.
    @Test func dropsTheOldKeyWhenARecipeIsReKeyed() {
        var b = baseline([
            "vendor:com.anthropic.claudefordesktop:stable",
            "vendor:com.anthropic.claudefordesktop:stable:ga",
            "vendor:com.anthropic.claudefordesktop:stable:rollout",
        ])
        let out = b.prune(keeping: [
            "vendor:com.anthropic.claudefordesktop:stable:ga",
            "vendor:com.anthropic.claudefordesktop:stable:rollout",
        ])
        #expect(out.removed == ["vendor:com.anthropic.claudefordesktop:stable"])
        #expect(b.entries.count == 2)
    }

    /// Issues close when a recipe verifies clean. A removed recipe never
    /// verifies again, so dropping its row would strand the issue with nothing
    /// left that could ever close it.
    @Test func keepsAnOrphanWhoseIssueIsStillOpen() {
        var b = baseline(["changelog:gone:-"])
        b.entries["changelog:gone:-"]?.issueNumber = 42
        let out = b.prune(keeping: ["vendor:other:stable"])
        #expect(out.removed.isEmpty)
        #expect(out.keptWithOpenIssue == ["changelog:gone:-"])
        #expect(b.entries["changelog:gone:-"] != nil)
    }

    @Test func dropsAnOrphanWhoseIssueWasAlreadyClosed() {
        var b = baseline(["changelog:gone:-"])
        b.entries["changelog:gone:-"]?.issueNumber = 42
        b.entries["changelog:gone:-"]?.closedAt = Date()
        #expect(b.prune(keeping: ["vendor:other:stable"]).removed == ["changelog:gone:-"])
        #expect(b.entries.isEmpty)
    }

    /// A caller that fails to build the live set must not wipe the file. This is
    /// the difference between a bug and a data loss.
    @Test func anEmptyLiveSetPrunesNothing() {
        var b = baseline(["vendor:a:stable", "changelog:b:-"])
        let out = b.prune(keeping: [])
        #expect(out.removed.isEmpty)
        #expect(b.entries.count == 2)
    }

    /// The set the sweep actually passes has to cover every row the sweep writes,
    /// or the next run deletes what this one recorded. Derived from the
    /// registries, never a literal list.
    @Test func everyRegistryRecipeIDIsInTheLiveSet() {
        let live = Set(
            VendorProbeRegistry.recipes.map(\.recipeID)
                + ChangelogRecipeRegistry.recipes.map(\.recipeID)
                + GitHubReleaseRegistry.rules.map(\.recipeID))
        #expect(live.count > 250, "only \(live.count) ids — a registry stopped contributing?")
        var b = Baseline()
        for id in live { b.entries[id] = Baseline.Entry() }
        #expect(b.prune(keeping: live).removed.isEmpty)
    }
}
