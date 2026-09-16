import Testing
import Foundation
@testable import DuoUpdaterCore

/// The per-host install gate's keying decision: which host an app's download
/// should be charged against.
///
/// The property that matters is the one #671 broke and shipped without a test
/// for: apps whose feeds share an entry host (six Microsoft specs share
/// `go.microsoft.com`, three Discord specs share `discord.com`) must not
/// inherit each other's CDN once one of them has downloaded — that host never
/// sends the others a byte, and throttling against it defeats the cap.
///
/// Fixture hosts use the `.example` TLD (reserved for documentation by RFC
/// 2606, never resolvable) and fixture app ids are invented bundle-id-shaped
/// strings — none of them name a real vendor or a path on this machine.
///
/// Each test names the mutation it is here to catch; every one was run and
/// confirmed red before this file was committed (see the worktree notes for
/// the raw pass/fail output).
struct EffectiveInstallHostTests {

    /// The regression itself. #671 made several unrelated apps' feed URLs share
    /// one entry host; the gate must key each app on the host that served IT,
    /// not on whatever a sibling last wrote under that shared feed host.
    ///
    /// Mutation: faithfully restoring the pre-#671 keying — `learn` writes
    /// `byApp[feedHost]` and `host(forApp:feedHost:)` reads `byApp[feedHost]`,
    /// both keyed by feed host instead of app id.
    @Test func siblingsSharingAFeedHostDoNotInheritEachOthersCDN() {
        let sharedFeedHost = "go.fixture.example"
        var table = EffectiveInstallHost()

        // Interleaved on purpose: each sibling's query runs right after its OWN
        // `learn` call, not after both `learn` calls have happened. See the
        // vacuity-guard note below for why the interleaving is load-bearing.
        table.learn(appID: "zz.fixture.wordish", feedHost: sharedFeedHost, servedBy: "res.onecdn.fixture.example")
        #expect(table.host(forApp: "zz.fixture.wordish", feedHost: sharedFeedHost) == "res.onecdn.fixture.example")

        table.learn(appID: "zz.fixture.edgeish", feedHost: sharedFeedHost, servedBy: "msedge.delivery.fixture.example")
        #expect(table.host(forApp: "zz.fixture.edgeish", feedHost: sharedFeedHost) == "msedge.delivery.fixture.example")

        // Vacuity guard. A third sibling that has never downloaded anything
        // shares the same feed host but must still key on that feed host
        // itself — not on whichever CDN a sibling last wrote there.
        //
        // Without this third app, the two assertions above stay green even
        // under the broken (feed-host-keyed) implementation, PROVIDED they are
        // interleaved as above: each sibling's own `learn` call is the last
        // write to the shared key before its own query runs, so querying
        // immediately after learning happens to read back what you just wrote
        // regardless of which string is the key. (Un-interleaved — both
        // `learn` calls before both queries — the broken implementation would
        // already fail the wordish assertion, because edgeish's later write
        // clobbers wordish's answer.) This assertion is the only one that
        // distinguishes the two implementations under the interleaved fixture
        // — it is the one a fresh caller (the prototype used Excel) makes,
        // having never downloaded, and the broken implementation answers it
        // with whichever CDN was written last.
        #expect(table.host(forApp: "zz.fixture.excelish", feedHost: sharedFeedHost) == sharedFeedHost)
    }

    /// The `feedHost != finalHost` guard in `learn`. Its effect is only
    /// observable after the app's OWN feed URL later changes to a new host —
    /// recording a value equal to the old feed host would sit in the map and
    /// permanently mask the new one, since `host(forApp:feedHost:)` prefers a
    /// learned entry over the host passed in.
    ///
    /// Mutation: dropping `feedHost != finalHost` from `learn`'s guard.
    @Test func aHostThatServedItselfIsNotRememberedAsIfItHadRedirected() {
        var table = EffectiveInstallHost()
        let appID = "zz.fixture.selfserving"
        let originalFeedHost = "cdn.fixture.example"

        // No redirect happened: the feed host served its own bytes directly.
        table.learn(appID: appID, feedHost: originalFeedHost, servedBy: originalFeedHost)

        // The vendor later moves this app's feed to a different host.
        let newFeedHost = "new-cdn.fixture.example"

        // Under the mutant, the no-op `learn` above would instead have
        // recorded `byApp[appID] = originalFeedHost`, and this query would
        // wrongly return `originalFeedHost` — pinning the app to a host it
        // will never see traffic from again — instead of falling through to
        // the new feed host.
        #expect(table.host(forApp: appID, feedHost: newFeedHost) == newFeedHost)
    }

    /// No mutation of its own catches this (see the mutation table in the
    /// worktree notes) — kept anyway because it states the reason the map is
    /// keyed the way it is: this gate exists for the CDN, not for the feed.
    /// Two apps whose feeds point at different hosts still converge on a
    /// shared cap once each has independently learned the same CDN.
    @Test func twoAppsWhoseFeedsBounceToOneCDNConvergeOnThatCDN() {
        var table = EffectiveInstallHost()
        let sharedCDN = "shared-cdn.fixture.example"
        table.learn(appID: "zz.fixture.appAlpha", feedHost: "vendor-alpha.fixture.example", servedBy: sharedCDN)
        table.learn(appID: "zz.fixture.appBeta", feedHost: "vendor-beta.fixture.example", servedBy: sharedCDN)

        #expect(table.host(forApp: "zz.fixture.appAlpha", feedHost: "vendor-alpha.fixture.example") == sharedCDN)
        #expect(table.host(forApp: "zz.fixture.appBeta", feedHost: "vendor-beta.fixture.example") == sharedCDN)
    }

    /// No mutation of its own catches this either — same reason as the test
    /// above, from the single-app side: once an app has learned who serves
    /// it, that learned host is what the gate keys on, not the feed host.
    @Test func onceLearnedItIsThrottledOnTheHostThatServedIt() {
        var table = EffectiveInstallHost()
        let appID = "zz.fixture.appGamma"
        let feedHost = "vendor-gamma.fixture.example"
        let servedHost = "cdn-gamma.fixture.example"

        table.learn(appID: appID, feedHost: feedHost, servedBy: servedHost)

        #expect(table.host(forApp: appID, feedHost: feedHost) == servedHost)
    }

    /// The base case the `?? feedHost` fallback exists for: an app nothing has
    /// ever been learned about keys on the feed host it's asked about.
    ///
    /// Mutation: the read becoming `byApp[appID] ?? ""`, dropping the fallback.
    @Test func anAppNothingHasBeenLearnedAboutFallsBackToItsFeedHost() {
        let table = EffectiveInstallHost()
        #expect(table.host(forApp: "zz.fixture.appDelta", feedHost: "vendor-delta.fixture.example") == "vendor-delta.fixture.example")
    }

    /// `learn` with a nil feed host records nothing, so the next query still
    /// falls through to whatever feed host it's asked about.
    ///
    /// Mutation: same as above — a dropped `?? feedHost` fallback would also
    /// turn this into a mismatch, since nothing was ever recorded here either.
    @Test func learnWithANilFeedHostRecordsNothing() {
        var table = EffectiveInstallHost()
        table.learn(appID: "zz.fixture.appEpsilon", feedHost: nil, servedBy: "cdn-epsilon.fixture.example")
        #expect(table.host(forApp: "zz.fixture.appEpsilon", feedHost: "vendor-epsilon.fixture.example") == "vendor-epsilon.fixture.example")
    }

    /// `learn` with a nil served-by host records nothing — a download whose
    /// final host was never determined must not overwrite a good entry, or
    /// erase the app's ability to fall back to its feed host.
    @Test func learnWithANilServedByHostRecordsNothing() {
        var table = EffectiveInstallHost()
        table.learn(appID: "zz.fixture.appZeta", feedHost: "vendor-zeta.fixture.example", servedBy: nil)
        #expect(table.host(forApp: "zz.fixture.appZeta", feedHost: "vendor-zeta.fixture.example") == "vendor-zeta.fixture.example")
    }
}
