import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// `Verify.classifyFeed` is the pure decision half of `duo verify`'s
/// `SparkleFeedCatalog` sweep (`Verify.probe` does the network half and is not
/// exercised here — see `FeedVerify.swift`'s doc comment for the split, which
/// mirrors `Verify.classifyAppStore`).
///
/// The entries under test are pulled FROM the catalog rather than written out
/// here, so a case's kind and addresses cannot drift between the table and what
/// these tests assume about it — and a new entry is covered the day it lands.
/// Every case names the mutation it catches.
@Suite struct FeedVerifyClassificationTests {

    private func fillInEntry() throws -> SparkleFeedCatalog.VerificationCase {
        try #require(SparkleFeedCatalog.verificationCases.first { $0.kind == .fillIn },
                     "the catalog no longer has a fill-in entry to test against")
    }

    private func supersededEntry() throws -> SparkleFeedCatalog.VerificationCase {
        try #require(SparkleFeedCatalog.verificationCases.first { $0.kind == .superseded },
                     "the catalog no longer has a superseding entry to test against")
    }

    /// A feed answering the way both live feeds answer today: several items,
    /// the newest usable one naming a marketing version and an absolute
    /// enclosure. The baseline every mutation below starts from.
    private func healthy(
        items: Int = 9, usable: Int = 9,
        short: String? = "3.13.2", build: String? = "1172",
        enclosure: String? = "https://example.com/app.zip",
        capped: Int = 0
    ) -> SparkleFeedReading {
        SparkleFeedReading(
            itemCount: items, usableCount: usable,
            headShortVersion: short, headBuildVersion: build,
            headEnclosure: enclosure.flatMap { URL(string: $0) },
            itemsDeclaringMaximumSystemVersion: capped,
            osVersion: "26.0.0", byteCount: 4_734)
    }

    // MARK: - baseline

    /// The version recorded is the MARKETING string, which is what
    /// `Baseline.reconcile` compares run to run.
    ///
    /// Mutation: return `live.headBuildVersion` instead and this reads `1172`.
    /// That is not merely a different label — the baseline would then hold a
    /// build where it used to hold a marketing version, and
    /// `VersionComparator` is documented never to compare across those two
    /// namespaces.
    @Test func aHealthyFillInFeedIsOKAndRecordsItsMarketingVersion() throws {
        let verdict = Verify.classifyFeed(
            try fillInEntry(), FeedObservation(live: .read(healthy()), declared: nil))
        #expect(verdict.status == .ok)
        #expect(verdict.version == "3.13.2")
        #expect(verdict.warnings.isEmpty)
    }

    /// A superseding entry is healthy when the address it redirects AWAY from
    /// is still older than the one it redirects to — which is the entry's whole
    /// justification, and the only thing about it that can expire on its own.
    @Test func aSupersededEntryIsOKWhileTheDeadAddressIsStillBehind() throws {
        let dead = healthy(items: 4, usable: 1, short: "2.5.22", build: "764")
        let verdict = Verify.classifyFeed(
            try supersededEntry(),
            FeedObservation(live: .read(healthy()), declared: .read(dead)))
        #expect(verdict.status == .ok)
        #expect(verdict.version == "3.13.2")
        #expect(verdict.warnings.isEmpty)
    }

    // MARK: - the address itself

    /// Mutation: `.infra` → `.broken` here. A host having a bad minute would
    /// then open an issue on the first sweep that saw it, which is what
    /// `Baseline.isInfraReportable`'s week-long window exists to prevent.
    @Test func anAddressThatDoesNotAnswerIsInfraNotBroken() throws {
        let verdict = Verify.classifyFeed(
            try fillInEntry(),
            FeedObservation(live: .unreachable(httpStatus: 503, detail: "HTTP 503"),
                            declared: nil))
        #expect(verdict.status == .infra)
        #expect(verdict.version == nil)
        #expect(verdict.warnings.first?.hasPrefix("feedUnreachable") == true)
    }

    /// A 200 carrying something that is not an appcast — a CDN's HTML error
    /// page, a redirect landing page, an empty file.
    ///
    /// Mutation: fold this into the `usableCount` branch below. The report then
    /// says the vendor's items were filtered out, sending whoever reads it to
    /// look at OS bounds and channels when there were never any items at all.
    @Test func aBodyWithNoItemsIsBroken() throws {
        let verdict = Verify.classifyFeed(
            try fillInEntry(),
            FeedObservation(live: .read(healthy(items: 0, usable: 0)), declared: nil))
        #expect(verdict.status == .broken)
        #expect(verdict.version == nil)
        #expect(verdict.warnings.first?.hasPrefix("feedParsedToZeroItems") == true)
    }

    /// The silent one, and the reason this sweep exists. Items parse, every one
    /// of them is filtered, `latestVersion` returns nil, and the row renders as
    /// up to date — the exact shape of the frozen feed a superseding entry was
    /// added to escape.
    ///
    /// Mutation: drop the `usableCount > 0` guard. The head fields are all nil
    /// in this state, so the next guard catches it and downgrades the verdict
    /// to a `.warn` about a missing marketing version — a true statement that
    /// describes the wrong problem.
    @Test func aFeedWhoseEveryItemIsFilteredIsBrokenAndSaysWhy() throws {
        let verdict = Verify.classifyFeed(
            try fillInEntry(),
            FeedObservation(
                live: .read(healthy(items: 4, usable: 0, short: nil, build: nil,
                                    enclosure: nil, capped: 3)),
                declared: nil))
        #expect(verdict.status == .broken)
        #expect(verdict.version == nil)
        let warning = try #require(verdict.warnings.first)
        #expect(warning.hasPrefix("everyItemFilteredOut"))
        // The hint `latestVersion` itself logs, so the report points the same
        // way the runtime log does rather than at a re-derived predicate.
        #expect(warning.contains("3 of them declare a maximum system version"))
        #expect(warning.contains("26.0.0"))
    }

    /// A feed whose head item names only `sparkle:version`. Legal Sparkle, but
    /// it changes what this source can promise: `RemoteVersion` marks a Sparkle
    /// answer as carrying the bundle's own marketing string, and `evaluate`'s
    /// downgrade guard reads that.
    ///
    /// Mutation: record `headBuildVersion` as a fallback. The finding then
    /// reads `.ok` with version `1172`, and the baseline silently switches the
    /// namespace it has been recording in.
    @Test func aHeadItemWithNoMarketingVersionWarnsAndRecordsNothing() throws {
        let verdict = Verify.classifyFeed(
            try fillInEntry(),
            FeedObservation(live: .read(healthy(short: nil)), declared: nil))
        #expect(verdict.status == .warn)
        #expect(verdict.version == nil)
        let warning = try #require(verdict.warnings.first)
        #expect(warning.hasPrefix("headItemNamesNoMarketingVersion"))
        // The build is still worth printing — it is what a reader needs to find
        // the item being complained about.
        #expect(warning.contains("1172"))
    }

    // MARK: - the enclosure

    /// An enclosure `Downloader` has no way to fetch. Detection still works,
    /// which is why this is a warning rather than a break — and why it needs to
    /// be said out loud at all.
    ///
    /// ⚠️ The fixture is a non-http SCHEME, not a relative address, and the
    /// difference is the whole reachability of this branch. A relative
    /// enclosure cannot arrive here: `SparkleAppcastParser.resolve` is
    /// `URL(string:relativeTo:)?.absoluteURL` and `readFeed` always passes the
    /// feed's own address as the base, so Helium's
    /// `assets/helium_….dmg` reaches `headEnclosure` already resolved to an
    /// https URL with a host (pinned in
    /// `SparkleFeedCatalogTests.aCatalogFedAppStillInfersItsChannelFromTheFeed`).
    /// Writing this case with a base-less relative URL would be asserting on a
    /// state the sweep cannot produce — a fixture wider than production, which
    /// leaves the branch that CAN fire untested.
    ///
    /// Mutation: drop the scheme/host check. A feed whose downloads cannot be
    /// fetched then sweeps green forever, because the version still parses.
    @Test func aHeadEnclosureOnAnUnfetchableSchemeWarnsAndStillRecordsTheVersion() throws {
        let verdict = Verify.classifyFeed(
            try fillInEntry(),
            FeedObservation(
                live: .read(healthy(enclosure: "ftp://updates.example.com/app.dmg")),
                declared: nil))
        #expect(verdict.status == .warn)
        // Still recorded: detection is intact, and losing the version history
        // would cost the one check that catches a feed going backwards.
        #expect(verdict.version == "3.13.2")
        #expect(verdict.warnings.first?.hasPrefix("headEnclosureIsNotAbsolute") == true)
    }

    /// Mutation: treat a nil enclosure as "nothing to check". A detection-only
    /// feed then reports `.ok` while every Update button on it is dead.
    @Test func aHeadItemWithNoEnclosureAtAllWarns() throws {
        let verdict = Verify.classifyFeed(
            try fillInEntry(),
            FeedObservation(live: .read(healthy(enclosure: nil)), declared: nil))
        #expect(verdict.status == .warn)
        #expect(verdict.version == "3.13.2")
        #expect(verdict.warnings.first?.hasPrefix("headItemHasNoEnclosure") == true)
    }

    // MARK: - the superseded half's expiry

    /// The vendor starts publishing current builds at the address we redirect
    /// away from. The entry is now asserting our 2026 reading of their
    /// infrastructure over theirs, and nothing else would ever say so.
    ///
    /// Mutation: compare with `>=` — i.e. accept "the same version" as still
    /// behind. The two addresses serving identical builds is precisely the
    /// state in which the override has stopped buying anything.
    @Test func aSupersededEntryWarnsWhenTheDeadAddressCaughtUp() throws {
        let verdict = Verify.classifyFeed(
            try supersededEntry(),
            FeedObservation(live: .read(healthy()),
                            declared: .read(healthy(items: 4, usable: 1))))
        #expect(verdict.status == .warn)
        // Recorded anyway: the live half of this entry is healthy, and its
        // version history is worth keeping while the override is reviewed.
        #expect(verdict.version == "3.13.2")
        #expect(verdict.warnings.first?.hasPrefix("supersededAddressIsNoLongerBehind") == true)
    }

    /// Two addresses that both name a version, in namespaces
    /// `VersionComparator` refuses to cross: the dead feed names only a build,
    /// the live one only a marketing string. `isNewer` fails closed, and that
    /// failure is the answer — "we can no longer show this entry is justified"
    /// is worth being told however it became true.
    ///
    /// Mutation: read the fail-closed `false` as "fine". The entry then
    /// outlives the evidence for it without a word.
    @Test func aSupersededEntryWarnsWhenTheTwoAddressesCannotBeRanked() throws {
        let verdict = Verify.classifyFeed(
            try supersededEntry(),
            FeedObservation(
                live: .read(healthy(build: nil)),
                declared: .read(healthy(items: 4, usable: 1, short: nil, build: "764"))))
        #expect(verdict.status == .warn)
        #expect(verdict.warnings.first?.hasPrefix("supersededAddressIsNoLongerBehind") == true)
    }

    /// The other side of that coin, and the one a fail-closed comparison gets
    /// backwards on its own. A dead address that offers NOTHING a
    /// default-channel install could use — a retired path answering with a
    /// landing page, or a vendor capping its last uncapped build — is the
    /// entry's justification at its strongest, not its expiry.
    ///
    /// Mutation: drop the `!deadSide.isEmpty` guard. `isNewer` then answers
    /// false against an empty side, the sweep warns, `consecutiveActionable`
    /// climbs, and after two sweeps an issue is opened against the one entry
    /// behaving perfectly — nightly, forever.
    @Test func aSupersededEntryIsOKWhenTheDeadAddressOffersNothing() throws {
        let verdict = Verify.classifyFeed(
            try supersededEntry(),
            FeedObservation(
                live: .read(healthy()),
                declared: .read(healthy(items: 4, usable: 0, short: nil, build: nil,
                                        enclosure: nil, capped: 4))))
        #expect(verdict.status == .ok)
        #expect(verdict.version == "3.13.2")
        #expect(verdict.warnings.isEmpty)
    }

    /// An abandoned address is allowed to be abandoned. A 404 there says
    /// nothing against the entry — the match is on the address string, not on
    /// fetching it — and complaining would file an issue every night about the
    /// entry working exactly as designed.
    ///
    /// Mutation: fold `.unreachable` on the declared half into the warning
    /// above. Nightly noise, on the one entry that is behaving.
    @Test func anUnreachableDeadAddressIsNotAComplaint() throws {
        let verdict = Verify.classifyFeed(
            try supersededEntry(),
            FeedObservation(live: .read(healthy()),
                            declared: .unreachable(httpStatus: 404, detail: "HTTP 404")))
        #expect(verdict.status == .ok)
        #expect(verdict.version == "3.13.2")
        #expect(verdict.warnings.isEmpty)
    }

    /// A fill-in entry overrides no address, so there is no second read to
    /// compare against and the superseded check must not fire on it.
    ///
    /// Mutation: key the check on `entry.kind` instead of on the observation.
    /// A fill-in has no `declared` address to read, so the check would be
    /// comparing the live feed against nothing and warning about every
    /// fill-in entry in the table.
    @Test func aFillInEntryIsNeverJudgedAgainstADeadAddress() throws {
        let entry = try fillInEntry()
        #expect(entry.declared == nil)
        let verdict = Verify.classifyFeed(
            entry, FeedObservation(live: .read(healthy()), declared: nil))
        #expect(verdict.warnings.isEmpty)
    }
}
