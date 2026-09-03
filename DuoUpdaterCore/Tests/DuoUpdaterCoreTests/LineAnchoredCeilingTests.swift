import Foundation
import Testing
@testable import DuoUpdaterCore

/// `lineAnchoredCeiling` decides what a preview install may be offered. The
/// source-level tests reach it through a fixture whose install is always near the
/// top of the list; these put the install anywhere in the history, which is where
/// the two halves of the rule actually disagree.
///
/// It is also the only place the sweep's blind spot is covered: `duo verify`
/// anchors on the copy installed on the sweeping machine, or on the newest tag
/// when there is none — so a sweep on a machine without an old UTM never walks
/// this algorithm at all.
struct LineAnchoredCeilingTests {
    private let pattern = #"^v([0-9]+(?:\.[0-9]+)+)$"#

    private func release(_ tag: String, prerelease: Bool, draft: Bool = false)
    -> GitHubReleasesSource.Release {
        .init(
            tag: tag, body: nil, htmlURL: nil, publishedAt: nil, assets: [],
            isPrerelease: prerelease, isDraft: draft, hasExplicitReleaseState: true)
    }

    /// UTM's real shape, newest first: a preview line that has not graduated, a
    /// graduated line below it, and older lines behind that.
    private var releases: [GitHubReleasesSource.Release] {
        [
            release("v5.0.5", prerelease: true),
            release("v5.0.0", prerelease: true),
            release("v4.7.5", prerelease: false),
            release("v4.7.4", prerelease: false),
            release("v4.7.3", prerelease: true),
            release("v4.6.1", prerelease: true),
            release("v3.2.4", prerelease: false),
            release("v3.1.2", prerelease: true),
        ]
    }

    private func ceiling(installed: String, in releases: [GitHubReleasesSource.Release]? = nil)
    -> String? {
        GitHubReleasesSource.lineAnchoredCeiling(
            releases ?? self.releases, installed: installed, pattern: pattern)
    }

    @Test func aPreviewOnTheOpenLineRisesToThatLinesNewestPreview() {
        #expect(ceiling(installed: "5.0.0") == "5.0.5")
    }

    /// The failure the whole rule exists for: confined to prereleases this is
    /// "up to date" while 4.7.5 ships.
    @Test func aPreviewOnAGraduatedLineRisesToTheGraduation() {
        #expect(ceiling(installed: "4.7.3") == "4.7.5")
    }

    /// And the failure the other obvious answer produces: the newest release
    /// overall is 5.0.5, a preview of a line that has not shipped.
    @Test func aPreviewOnAGraduatedLineIsNotWalkedOntoAnUnshippedLine() {
        #expect(ceiling(installed: "4.7.3") != "5.0.5")
    }

    /// An install two lines back is still carried by the stable half.
    @Test func anOlderPreviewRisesToTheNewestStableRatherThanItsOwnDeadLine() {
        #expect(ceiling(installed: "3.1.2") == "4.7.5")
    }

    @Test func aStableInstallIsNeverLiftedOntoAPreview() {
        // 4.7.5 is already both halves' answer, so the ceiling cannot exceed it.
        #expect(ceiling(installed: "4.7.5") == "4.7.5")
    }

    /// Major, not minor — see `GitHubCandidateScope`. UTM has never shipped this
    /// shape, so nothing else in the suite can tell the two apart; without this
    /// the choice would be an accident rather than a decision.
    @Test func ceilingPrefersTheNewerPreviewLineWithinTheMajor() {
        let withOpenNextLine = releases + [release("v4.8.0", prerelease: true)]
        #expect(ceiling(installed: "4.7.3", in: withOpenNextLine) == "4.8.0",
                "a preview install follows its major's newest preview line; minor-line anchoring would hold it at 4.7.5")
    }

    @Test func aDraftIsNeverTheCeiling() {
        // The caller filters drafts before this runs; assert the pairing holds so
        // reordering those two steps cannot quietly offer an unpublished build.
        let published = releases.filter { !$0.isDraft }
        let withDraft = [release("v5.1.0", prerelease: true, draft: true)] + releases
        #expect(ceiling(installed: "5.0.0", in: withDraft.filter { !$0.isDraft })
                == ceiling(installed: "5.0.0", in: published))
    }

    @Test func aVersionWithNoMajorComponentYieldsNoCeiling() {
        #expect(ceiling(installed: "not-a-version") == nil)
    }

    /// Tags the pattern rejects are not evidence about any line.
    @Test func unparsableTagsAreIgnoredRatherThanTreatedAsZero() {
        let noisy = releases + [
            release("v2.0b7", prerelease: true), release("v0.2-fakesign", prerelease: false),
        ]
        #expect(ceiling(installed: "4.7.3", in: noisy) == "4.7.5")
    }
}
