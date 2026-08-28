import Testing
import Foundation
@testable import DuoUpdaterCore

/// Regression coverage for the stale-notes bug found in the adversarial review of
/// PR #125: the workbench's in-memory formula release-notes state was keyed by
/// formula NAME alone and never cleared, so once a formula's notes had been
/// loaded, every later request for that formula was taken for a hit no matter
/// which version it asked about — leaving the pane rendering the old version's
/// notes for the rest of the app session. The disk cache underneath was already
/// version-keyed (`BrewFormulaReleaseService.fileURL`), so this was purely the UI
/// layer.
///
/// The cases below say "the version moves", not "brew upgrade", deliberately: a
/// plain `brew upgrade` does NOT move the key. `FormulaReleaseStore`'s doc comment
/// lists the refreshes that actually do.
struct FormulaReleaseStoreTests {

    private static func makeRelease(_ version: String) -> FormulaRelease {
        FormulaRelease(
            changelog: Changelog(entries: [
                Changelog.Entry(version: version, date: "2026-01-01", items: ["Notes for \(version)"]),
            ]),
            pageURL: URL(string: "https://github.com/example/example/releases/tag/v\(version)"))
    }

    /// The defect itself: a load finished for 1.2, then a refresh moves the wanted
    /// version to 1.3 and everything asks about that. Both the read and the claim
    /// must treat it as a miss — a hit here is exactly what served 1.2's notes
    /// against 1.3 for the rest of the session.
    @Test func newVersionIsAMissAfterAnEarlierVersionLoaded() {
        var store = FormulaReleaseStore()
        let claimedOld = store.claim(name: "ripgrep", version: "1.2")
        #expect(claimedOld)
        store.finish(name: "ripgrep", version: "1.2", release: Self.makeRelease("1.2"))
        #expect(store.state(name: "ripgrep", version: "1.2") == .loaded(Self.makeRelease("1.2")))

        // The version moves: nothing may hand back 1.2's notes under 1.3's name.
        #expect(store.state(name: "ripgrep", version: "1.3") == nil)
        let claimedNew = store.claim(name: "ripgrep", version: "1.3")
        #expect(claimedNew)
        #expect(store.state(name: "ripgrep", version: "1.3") == .loading)

        store.finish(name: "ripgrep", version: "1.3", release: Self.makeRelease("1.3"))
        #expect(store.state(name: "ripgrep", version: "1.3") == .loaded(Self.makeRelease("1.3")))
    }

    /// A formula holds at most one entry: re-claiming at a new version REPLACES the
    /// old one rather than leaving it readable (or accumulating one per version).
    @Test func reclaimingAtANewVersionEvictsTheOldEntry() {
        var store = FormulaReleaseStore()
        _ = store.claim(name: "ripgrep", version: "1.2")
        store.finish(name: "ripgrep", version: "1.2", release: Self.makeRelease("1.2"))
        _ = store.claim(name: "ripgrep", version: "1.3")
        #expect(store.state(name: "ripgrep", version: "1.2") == nil)
    }

    /// The property the version keying must not break: a second claimant for the
    /// SAME version is rejected, so the pre-warm and a user selecting the same row
    /// don't both spawn a `brew info` + GitHub fetch. That is the rate-limit
    /// guarantee — whichever of the two claims first loads, and the other drops
    /// out, in either arrival order.
    @Test func sameVersionIsClaimedOnlyOnce() {
        var store = FormulaReleaseStore()
        let first = store.claim(name: "ripgrep", version: "1.2")
        let second = store.claim(name: "ripgrep", version: "1.2")
        #expect(first)
        #expect(second == false)
        store.finish(name: "ripgrep", version: "1.2", release: Self.makeRelease("1.2"))
        let third = store.claim(name: "ripgrep", version: "1.2")
        #expect(third == false)
    }

    /// A fetch that was in flight when the version moved must not overwrite the
    /// fresh claim with its stale result.
    @Test func lateFinishForAnOldVersionIsIgnored() {
        var store = FormulaReleaseStore()
        _ = store.claim(name: "ripgrep", version: "1.2")
        _ = store.claim(name: "ripgrep", version: "1.3")
        store.finish(name: "ripgrep", version: "1.2", release: Self.makeRelease("1.2"))
        #expect(store.state(name: "ripgrep", version: "1.3") == .loading)
    }

    /// Formulae don't share state.
    @Test func entriesAreIndependentPerFormula() {
        var store = FormulaReleaseStore()
        _ = store.claim(name: "ripgrep", version: "1.2")
        store.finish(name: "ripgrep", version: "1.2", release: Self.makeRelease("1.2"))
        #expect(store.state(name: "fd", version: "1.2") == nil)
        let claimedOther = store.claim(name: "fd", version: "1.2")
        #expect(claimedOther)
    }
}
