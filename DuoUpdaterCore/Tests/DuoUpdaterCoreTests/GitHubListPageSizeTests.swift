import Testing
import Foundation
@testable import DuoUpdaterCore

/// `listPageSize` — how many rows a `usePrereleases: true` rule pages through on
/// GitHub's `/releases` list endpoint (see `GitHubReleaseRule.listPageSize`).
/// Get it wrong in either direction: too big and every round pays for `body`
/// (release-notes prose the version probe never reads — measured at 6%-51% of
/// the JSON, 421 KB across six installed repos at the old blanket
/// `per_page=20`, 2026-09-04); too small and the release the rule is actually
/// looking for scrolls off the page, which reads as "no update" rather than as
/// an error.
///
/// This file pins the SECOND failure mode: every `usePrereleases: true` rule's
/// `listPageSize` must be at least as deep as what was actually measured
/// against the live GitHub endpoint, not just "some number smaller than 20".
struct GitHubListPageSizeTests {

    /// Minimum safe depth measured against the LIVE endpoint (2026-09-04, newest
    /// 100 releases per repo, independently recomputed in Python per CLAUDE.md's
    /// "合并前独立复算" — not reread out of the Swift rule). For each rule: the
    /// worst observed run-length between two releases the rule's pattern
    /// accepts, plus 1 (the minimum depth that would have still caught the
    /// worse of the two). The `listPageSize` chosen in the registry carries
    /// further headroom above this floor; this table only pins the floor a
    /// value must clear, not the value itself.
    ///
    /// Keyed by `bundleID/channel` since one bundle id can carry two rules
    /// (GitHub Desktop stable/beta, T3 Code alpha/nightly) — `bundleID` alone
    /// would collide.
    ///
    /// UTM beta (`com.utmapp.UTM/beta`) is deliberately ABSENT: its
    /// `candidateScope` is `.installedMajorLineOrNewestStable`, which doesn't
    /// need "first pattern match" depth — `lineAnchoredCeiling` only needs to
    /// find EITHER the newest release in the installed major line OR the
    /// newest STABLE release in the fetched page. That's a different
    /// measurement (done, and left at the 20 default, in the rule's own
    /// comment), and a floor here would silently measure the wrong algorithm.
    /// `ruleWithLineAnchoredScopeIsExcludedOnPurpose` pins that this is a
    /// decision, not an oversight.
    static let measuredMinimumDepth: [String: Int] = [
        "dev.zed.Zed-Preview/preview": 4,     // worst gap 3 (v1.5.1-pre→v1.5.0-pre), +1
        "com.insomnia.app/stable": 10,        // worst gap 9 (core@11.0.0→core@10.3.1), +1
        "com.github.GitHubClient/beta": 5,    // worst gap 4 (release-3.4.16-beta1→…3.4.13-beta2), +1
        "com.vorssaint.utils/beta": 2,        // worst gap 1 (only 4 -beta. tags ever), +1
        "com.microsoft.Headlamp/stable": 5,   // worst gap 4 (v0.23.0→v0.22.0), +1
        "com.bitwarden.desktop/stable": 8,    // worst gap 7 (desktop-v2026.6.0→…2026.5.0), +1
        "com.t3tools.t3code/nightly": 3,      // worst gap 2 (…20260902.1252→…20260901.1250), +1
    ]

    private static func key(_ rule: GitHubReleaseRule) -> String {
        "\(rule.bundleID)/\(rule.channel.rawValue)"
    }

    /// The rules this whole mechanism is about: every rule that reads the list
    /// endpoint EXCEPT the line-anchored one, which measures a different
    /// question (see the table's doc comment above).
    private static var depthCheckedListRules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter {
            $0.usePrereleases && $0.candidateScope != .installedMajorLineOrNewestStable
        }
    }

    /// The one judgement this file makes, factored out so the real test and the
    /// mutation test below run the SAME code rather than two copies of the same
    /// inequality. Returns the keys of every rule sitting below its measured
    /// floor — empty means all clear. A rule with no floor on record is
    /// reported too: a missing measurement is not a satisfied one.
    static func rulesBelowTheirMeasuredFloor(_ rules: [GitHubReleaseRule]) -> [String] {
        rules.compactMap { rule in
            guard let floor = measuredMinimumDepth[key(rule)] else { return key(rule) }
            return rule.listPageSize >= floor ? nil : key(rule)
        }
    }

    /// Every depth-checked rule's `listPageSize` clears its measured floor.
    @Test func everyListRuleMeetsItsMeasuredDepth() {
        let offenders = Self.rulesBelowTheirMeasuredFloor(Self.depthCheckedListRules)
        #expect(offenders.isEmpty,
                "these rules' listPageSize is below the depth measured against the live endpoint: \(offenders.sorted())")
    }

    /// Drift guard, both directions — the same shape as
    /// `GitHubAssetSelectionTests.multiCandidatePatternsAreAllCovered`: a rule
    /// added to the registry without a matching table entry must fail here
    /// rather than have `everyListRuleMeetsItsMeasuredDepth` quietly skip it
    /// (a missing floor is not the same as a satisfied one), and a table entry
    /// whose rule has been removed or reworked must fail too, so a stale
    /// measurement can't linger as if it still applied to something.
    @Test func measuredMinimumDepthCoversEveryDepthCheckedRule() {
        let ruleKeys = Set(Self.depthCheckedListRules.map(Self.key))
        let tableKeys = Set(Self.measuredMinimumDepth.keys)
        for key in ruleKeys {
            #expect(tableKeys.contains(key),
                    "\(key) uses the list endpoint (and isn't line-anchored) but has no entry in measuredMinimumDepth")
        }
        for key in tableKeys {
            #expect(ruleKeys.contains(key),
                    "measuredMinimumDepth names '\(key)', which no longer matches a depth-checked registry rule")
        }
    }

    /// The line-anchored exclusion is a decision, not an accident: if UTM beta
    /// ever stops being `.installedMajorLineOrNewestStable`, it becomes a
    /// depth-checked rule and `measuredMinimumDepthCoversEveryDepthCheckedRule`
    /// will demand a floor for it that this file doesn't have — which is the
    /// point (a different measurement is owed, not a silent default).
    @Test func ruleWithLineAnchoredScopeIsExcludedOnPurpose() {
        let utmBeta = GitHubReleaseRegistry.rules.first {
            $0.bundleID == "com.utmapp.UTM" && $0.channel == .beta
        }
        #expect(utmBeta?.candidateScope == .installedMajorLineOrNewestStable)
        #expect(utmBeta?.usePrereleases == true)
        #expect(Self.measuredMinimumDepth[Self.key(utmBeta!)] == nil)
    }

    /// A rule that reads `/releases/latest` (`usePrereleases == false`) never
    /// reaches the list branch of `fetchReleases`, so its `listPageSize` should
    /// stay at the untouched default — carrying a non-default value there would
    /// mean nothing and would be a sign the field was set on the wrong rule.
    @Test func nonListRulesKeepTheUntouchedDefault() {
        for rule in GitHubReleaseRegistry.rules where !rule.usePrereleases {
            #expect(rule.listPageSize == 20,
                    "\(rule.bundleID)/\(rule.channel.rawValue) doesn't use the list endpoint, so listPageSize should be the untouched default")
        }
    }

    /// Mutation check (CLAUDE.md: a new guard needs one).
    ///
    /// The first version of this test asserted `!(floor - 1 >= floor)`, which is
    /// true for every Int and touches no production code at all — it could not
    /// fail, so it was decoration rather than a gate. This one runs the real
    /// judgement (`rulesBelowTheirMeasuredFloor`, the same function
    /// `everyListRuleMeetsItsMeasuredDepth` calls) over a registry list with one
    /// real rule rebuilt one below its floor, and demands that the function name
    /// exactly that rule.
    ///
    /// Measured, not asserted: replacing the helper's
    /// `rule.listPageSize >= floor ? nil : key(rule)` with a bare `return nil`
    /// turns THIS test red and leaves `everyListRuleMeetsItsMeasuredDepth`
    /// green. That asymmetry is the whole reason this test exists — the real
    /// test is green on a healthy registry by construction, so it cannot notice
    /// its own judgement being deleted. Only a case that supplies a known-bad
    /// rule can.
    @Test func theFloorCheckNamesARuleThatSitsBelowItsFloor() {
        let victim = "dev.zed.Zed-Preview/preview"
        let floor = Self.measuredMinimumDepth[victim]!
        let mutated = GitHubReleaseRule(
            bundleID: "dev.zed.Zed-Preview", owner: "zed-industries", repo: "zed",
            usePrereleases: true, listPageSize: floor - 1,
            versionPattern: #"v([0-9]+\.[0-9]+\.[0-9]+)-pre"#,
            channel: .preview)

        // The healthy registry is clean...
        #expect(Self.rulesBelowTheirMeasuredFloor(Self.depthCheckedListRules).isEmpty)
        // ...and swapping in the under-sized rule is caught, by name.
        let withMutant = Self.depthCheckedListRules.filter { Self.key($0) != victim } + [mutated]
        #expect(Self.rulesBelowTheirMeasuredFloor(withMutant) == [victim])
    }
}
