import Foundation
import Testing
@testable import DuoUpdaterCore

/// `UpdateResult.relaunchLine` decides one thing: whether the build numbers earn
/// their place on the row. The rule is the one `buildBump` already applies to the
/// update line — a build is worth showing only when the marketing versions cannot
/// tell the two versions apart — plus the constraint that a side with no marketing
/// version of its own has nothing else to be read against.
@Suite struct RelaunchLineTests {

    private typealias Side = UpdateResult.VersionSide

    private func app(short: String?, build: String?) -> InstalledApp {
        InstalledApp(
            name: "Google Chrome", bundleID: "com.google.Chrome", shortVersion: short,
            buildVersion: build, path: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: true, hasSparkleUpdater: false)
    }

    private func result(short: String?, build: String?) -> UpdateResult {
        UpdateResult(app: app(short: short, build: build), remote: nil, status: .upToDate)
    }

    /// The case that prompted this. Chrome's marketing version *ends in* its build,
    /// so the parenthesised half was pure repetition — and it cost enough width that
    /// the running side truncated mid-number, losing the digits that differed.
    @Test func chromeDropsBuildsTheMarketingVersionAlreadySpellsOut() {
        let line = UpdateResult.relaunchLine(
            from: Side(marketing: "151.0.7922.174", build: "7922.174"),
            to: Side(marketing: "152.0.7977.65", build: "7977.65"))
        #expect(line.from == "151.0.7922.174")
        #expect(line.to == "152.0.7977.65")
    }

    /// The reason builds are shown at all: Surge shipped four separate releases as
    /// "6.9.0", where dropping the build leaves a line that reads as a no-op.
    @Test func sameMarketingVersionKeepsTheBuildsThatDiffer() {
        let line = UpdateResult.relaunchLine(
            from: Side(marketing: "6.9.0", build: "12028"),
            to: Side(marketing: "6.9.0", build: "12030"))
        #expect(line.from == "6.9.0 (12028)")
        #expect(line.to == "6.9.0 (12030)")
    }

    /// `lsappinfo` exposes only the running build. When nothing recovered a marketing
    /// version to pair with it, the target's build is the only value in the running
    /// side's namespace — dropping it would leave "3965 → 1.7.3", two numbers that
    /// cannot be read against each other.
    @Test func abareRunningBuildKeepsTheTargetsBuild() {
        let line = UpdateResult.relaunchLine(
            from: Side(marketing: nil, build: "3965"),
            to: Side(marketing: "1.7.3", build: "194"))
        #expect(line.from == "3965")
        #expect(line.to == "1.7.3 (194)")
    }

    /// The deferred-batch line: the pre-install version we recorded is a marketing
    /// version with no build, so both sides are named and the target's build goes.
    @Test func aFromSideWithNoBuildStillSuppressesTheTargets() {
        let line = UpdateResult.relaunchLine(
            from: Side(marketing: "1.7.2", build: nil),
            to: Side(marketing: "1.7.3", build: "194"))
        #expect(line.from == "1.7.2")
        #expect(line.to == "1.7.3")
    }

    /// Date/serial apps whose CFBundleVersion repeats CFBundleShortVersionString:
    /// never print the same number twice, whatever the rule decided.
    @Test func aBuildEqualToItsMarketingVersionIsNeverRepeated() {
        let line = UpdateResult.relaunchLine(
            from: Side(marketing: "2026.08.19", build: "2026.08.19"),
            to: Side(marketing: "2026.08.19", build: "2026.08.19"))
        #expect(line.from == "2026.08.19")
        #expect(line.to == "2026.08.19")
    }

    @Test func aSideWithNothingAtAllDegradesRatherThanCrashing() {
        #expect(Side(marketing: nil, build: nil).text(withBuild: true) == "?")
        #expect(Side(marketing: nil, build: nil).text(withBuild: false) == "?")
    }

    /// `relaunchTargetSide` reads the bundle's own two fields, stripping the
    /// JetBrains-style product prefix so it lands in the same namespace as the
    /// running build `strippingBuildPrefix` also cleans.
    @Test func theTargetSideComesOffTheBundleWithItsBuildPrefixStripped() {
        #expect(result(short: "2026.2", build: "IU-262.7132.23").relaunchTargetSide
                == Side(marketing: "2026.2", build: "262.7132.23"))
        #expect(result(short: "1.7.3", build: nil).relaunchTargetSide
                == Side(marketing: "1.7.3", build: nil))
        #expect(result(short: nil, build: "194").relaunchTargetSide
                == Side(marketing: nil, build: "194"))
    }

    /// Whatever the rule decides, it decides for both ends: a row that parenthesised
    /// a build on one side only would invite reading the two halves as different
    /// kinds of number.
    ///
    /// Judged over the sides that *could* carry a parenthesised build. One holding
    /// only a bare build has no marketing version to put in front of it, so its
    /// missing parentheses are the format rather than a suppressed build — asserting
    /// on the parentheses alone called that case a violation when it is the intended
    /// output.
    @Test func neitherEndSuppressesABuildTheOtherIsShowing() {
        let cases: [(Side, Side)] = [
            (Side(marketing: "1.0", build: "10"), Side(marketing: "2.0", build: "20")),
            (Side(marketing: "1.0", build: "10"), Side(marketing: "1.0", build: "20")),
            (Side(marketing: nil, build: "10"), Side(marketing: "2.0", build: "20")),
            (Side(marketing: "1.0", build: nil), Side(marketing: "1.0", build: "20")),
        ]
        for (from, to) in cases {
            let line = UpdateResult.relaunchLine(from: from, to: to)
            let shown = zip([from, to], [line.from, line.to])
                .filter { $0.0.marketing != nil && $0.0.build != nil }
                .map { $0.1.contains("(") }
            #expect(Set(shown).count <= 1,
                    "one end kept its build and the other dropped it: \(line)")
        }
    }

    // MARK: - The staged relaunch line

    private func staged(version: String, build: String?) -> StagedSelfUpdate {
        StagedSelfUpdate(
            version: version, buildVersion: build,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/staged/Amp.app"))
    }

    /// The bug this pair exists for: `stagedVersionLine` formatted each side as a
    /// bare `CFBundleShortVersionString`, so the rule above reached only ONE of the
    /// two relaunch lines. Amp ships every build as "1.0" — the row read
    /// "1.0 → 1.0" and named no difference at all, while both build numbers were
    /// already in hand (`SelfUpdaterStaging` compares them to decide the row is
    /// offerable).
    @Test func stagedLineKeepsTheBuildsWhenTheMarketingVersionDoesNotMove() {
        let line = result(short: "1.0", build: "128")
            .stagedRelaunchLine(staged(version: "1.0", build: "130"))
        #expect(line.from == "1.0 (128)")
        #expect(line.to == "1.0 (130)")
    }

    /// The other half of the same rule, so the fix cannot be "always show builds":
    /// when the marketing versions already differ, the build is noise.
    @Test func stagedLineDropsTheBuildsWhenTheMarketingVersionsAlreadyDiffer() {
        let line = result(short: "1.7.3", build: "194")
            .stagedRelaunchLine(staged(version: "1.8.0", build: "201"))
        #expect(line.from == "1.7.3")
        #expect(line.to == "1.8.0")
    }

    /// Both ends are put through `strippingBuildPrefix`, matching
    /// `relaunchTargetSide` — a vendor that prefixes its build must not end up with
    /// one side stripped and the other not, which would read as two namespaces.
    ///
    /// The prefix it strips is a letters-then-dash one (`nightly-1234`); a bare
    /// `v1234` has no dash and is left alone, which is the existing contract and is
    /// asserted here so this test cannot be read as claiming more than it does.
    @Test func stagedLineStripsBuildPrefixesOnBothEnds() {
        let line = result(short: "2.0", build: "nightly-1234")
            .stagedRelaunchLine(staged(version: "2.0", build: "nightly-1235"))
        #expect(line.from == "2.0 (1234)")
        #expect(line.to == "2.0 (1235)")

        let undashed = result(short: "2.0", build: "v1234")
            .stagedRelaunchLine(staged(version: "2.0", build: "v1235"))
        #expect(undashed.from == "2.0 (v1234)")
        #expect(undashed.to == "2.0 (v1235)")
    }

    /// A staged bundle with no `CFBundleVersion` leaves the installed side showing
    /// its build against a bare target. That asymmetry is the established format,
    /// not a bug: `neitherEndSuppressesABuildTheOtherIsShowing` above judges only
    /// the sides that COULD carry a parenthesised build, because a side with no
    /// build has nothing to put in parentheses. Pinned here so the staged line is
    /// held to the same reading as the restart line rather than quietly diverging.
    @Test func stagedLineWithNoStagedBuildKeepsTheInstalledBuildAsIs() {
        let line = result(short: "1.0", build: "128")
            .stagedRelaunchLine(staged(version: "1.0", build: nil))
        #expect(line.from == "1.0 (128)")
        #expect(line.to == "1.0")
    }
}
