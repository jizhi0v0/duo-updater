import Testing
import Foundation
@testable import DuoKit
@testable import DuoUpdaterCore

/// The two things `duo verify --feed` gained: the channel feeds
/// (`ChannelBinding.feedVerificationCases`) and the head enclosure's served
/// check. Decision half only, against invented answers — the network half
/// (`SparkleAppcastSource.probeEnclosure`) is exercised by a real run, like the
/// rest of `Verify.probe`. Every case names the mutation it catches.
@Suite struct FeedVerifyEnclosureTests {

    private let enclosure = "https://downloads.example.com/app-4.2.0.zip"

    private func catalogEntry() throws -> SparkleFeedCatalog.VerificationCase {
        try #require(SparkleFeedCatalog.verificationCases.first { $0.kind == .fillIn })
    }

    private func channelEntry() throws -> SparkleFeedCatalog.VerificationCase {
        try #require(ChannelBinding.feedVerificationCases.first)
    }

    private func reading(short: String? = "4.2.0", build: String? = "420") -> SparkleFeedReading {
        SparkleFeedReading(
            itemCount: 6, usableCount: 6,
            headShortVersion: short, headBuildVersion: build,
            headEnclosure: URL(string: enclosure),
            itemsDeclaringMaximumSystemVersion: 0,
            osVersion: "26.0.0", byteCount: 2_048)
    }

    private func classify(
        _ answer: SparkleEnclosureAnswer?, entry: SparkleFeedCatalog.VerificationCase? = nil,
        short: String? = "4.2.0"
    ) throws -> (status: FindingStatus, version: String?, warnings: [String]) {
        Verify.classifyFeed(
            try entry ?? catalogEntry(),
            FeedObservation(live: .read(reading(short: short)), declared: nil, enclosure: answer))
    }

    // MARK: - served

    /// 206 is the range honoured; 200 is the range ignored and the file on its
    /// way. Both say the file is there.
    ///
    /// Mutation: accept only 206. Every server that ignores `Range` — the case
    /// the read cap exists for — would then be reported as a dead download.
    @Test func aRangedOrAWholeAnswerIsServed() throws {
        for status in [200, 206, 302] {
            let verdict = try classify(.answered(status: status, bytesRead: 1))
            #expect(verdict.status == .ok, "HTTP \(status)")
            #expect(verdict.warnings.isEmpty, "HTTP \(status)")
            #expect(verdict.version == "4.2.0")
        }
    }

    /// Mutation: treat a missing answer as a failure. A finding is only
    /// classified without one when nothing was asked, and that must not invent
    /// a complaint.
    @Test func noEnclosureAnswerIsNoComplaint() throws {
        let verdict = try classify(nil)
        #expect(verdict.status == .ok)
        #expect(verdict.warnings.isEmpty)
    }

    // MARK: - refused

    /// The vendor deleted or moved the file. Detection still works, so it is
    /// the vendor sweep's `installURLNotFound` warning, with the version kept.
    ///
    /// Mutation: stop consulting `observation.enclosure`, or read these as
    /// transient. A feed whose every Update button 404s then sweeps green.
    @Test func aRefusedEnclosureWarnsAsInstallURLNotFound() throws {
        for status in [404, 410, 403] {
            let verdict = try classify(.answered(status: status, bytesRead: 0))
            #expect(verdict.status == .warn, "HTTP \(status)")
            #expect(verdict.version == "4.2.0")
            #expect(verdict.warnings
                == ["installURLNotFound: HTTP \(status) from downloads.example.com"])
        }
    }

    // MARK: - transient

    /// The server is there and may answer next time, or refused the RANGE and
    /// not the file. Reported, and aged by `Baseline`'s install-transient
    /// counter, but not actionable — the finding stays `.ok`.
    ///
    /// Mutations: drop `>= 500`, `408`, `416` or `429` from the transient set
    /// (that status then files as a deleted file), or drop the
    /// transient filter on the status (every one of them turns the finding
    /// `.warn`).
    @Test func aMomentaryOrRangeRefusingAnswerIsTransient() throws {
        for status in [500, 503, 408, 416, 429, 501] {
            let verdict = try classify(.answered(status: status, bytesRead: 0))
            #expect(verdict.status == .ok, "HTTP \(status)")
            #expect(verdict.version == "4.2.0")
            #expect(verdict.warnings == ["installURLTransient: HTTP \(status)"], "HTTP \(status)")
        }
        let silent = try classify(.noAnswer(detail: "The request timed out."))
        #expect(silent.status == .ok)
        #expect(silent.warnings == ["installURLTransient"])
    }

    /// A transient answer beside a real complaint must not hide it: only the
    /// transient one is set aside when deciding the status.
    ///
    /// Mutation: decide the status on whether ANY warning is transient. The
    /// superseded entry's own complaint is then reported as `.ok`.
    @Test func aTransientEnclosureDoesNotMaskAnotherWarning() throws {
        let entry = try #require(
            SparkleFeedCatalog.verificationCases.first { $0.kind == .superseded })
        let verdict = Verify.classifyFeed(entry, FeedObservation(
            live: .read(reading()), declared: .read(reading()),
            enclosure: .answered(status: 503, bytesRead: 0)))
        #expect(verdict.status == .warn)
        #expect(verdict.warnings.contains("installURLTransient: HTTP 503"))
        #expect(verdict.warnings.contains { $0.hasPrefix("supersededAddressIsNoLongerBehind") })
    }

    // MARK: - what gets asked

    /// The network half spends a request only on an address a download could be
    /// asked of, and the decision half warns about any other — one function, so
    /// the two cannot disagree.
    ///
    /// Mutation: drop the scheme or the host check.
    @Test func onlyAnAbsoluteHTTPEnclosureIsAsked() {
        func head(_ text: String?) -> SparkleFeedReading {
            SparkleFeedReading(
                itemCount: 1, usableCount: 1, headShortVersion: "1.0", headBuildVersion: "1",
                headEnclosure: text.flatMap { URL(string: $0) },
                itemsDeclaringMaximumSystemVersion: 0, osVersion: "26.0.0", byteCount: 1)
        }
        #expect(Verify.fetchableEnclosure(head("https://a.example/x.zip")) != nil)
        #expect(Verify.fetchableEnclosure(head("http://a.example/x.zip")) != nil)
        #expect(Verify.fetchableEnclosure(head("ftp://a.example/x.zip")) == nil)
        #expect(Verify.fetchableEnclosure(head("https:x.zip")) == nil)
        #expect(Verify.fetchableEnclosure(head(nil)) == nil)
    }

    // MARK: - channel feeds

    /// Fork's and iTerm2's feeds name only `sparkle:version`, and always have.
    /// The runtime reads them that way; the sweep must not warn about it every
    /// night. The version stays nil, for the namespace reason `classifyFeed`
    /// gives, and the enclosure is still checked.
    ///
    /// Mutation: drop the `.channel` exemption. Four feeds warn on every sweep.
    @Test func aChannelFeedNamingOnlyABuildIsNotAComplaint() throws {
        let entry = try channelEntry()
        let verdict = try classify(.answered(status: 206, bytesRead: 1), entry: entry, short: nil)
        #expect(verdict.status == .ok)
        #expect(verdict.version == nil)
        #expect(verdict.warnings.isEmpty)

        let gone = try classify(.answered(status: 404, bytesRead: 0), entry: entry, short: nil)
        #expect(gone.status == .warn)
        #expect(gone.warnings.first?.hasPrefix("installURLNotFound") == true)
    }

    /// The catalog keeps the warning: its addresses were chosen with a
    /// marketing string in them, so losing it IS a change.
    @Test func aCatalogFeedNamingOnlyABuildStillWarns() throws {
        let verdict = try classify(.answered(status: 206, bytesRead: 1), short: nil)
        #expect(verdict.status == .warn)
        #expect(verdict.warnings.first?.hasPrefix("headItemNamesNoMarketingVersion") == true)
    }

    /// `--feed` sweeps the channel feeds, and `Baseline` keeps their rows.
    ///
    /// Mutation: leave `feedCases` as the catalog alone, or prune against the
    /// catalog alone — the second deletes every channel feed's streak each run,
    /// so none of them could ever reach `actionableThreshold`.
    @Test func theChannelFeedsAreSweptAndKept() {
        let channel = Set(ChannelBinding.feedVerificationCases.map(\.recipeID))
        #expect(!channel.isEmpty)
        #expect(channel.isSubset(of: Set(Verify.feedCases.map(\.recipeID))))
        #expect(channel.isSubset(of: Verify.liveRecipeIDs()))
        #expect(Set(SparkleFeedCatalog.verificationCases.map(\.recipeID))
            .isSubset(of: Set(Verify.feedCases.map(\.recipeID))))
    }

    /// A new id's first bad sweep files nothing: a fresh baseline row starts at
    /// zero, so one warning is a streak of one, below `actionableThreshold`, and
    /// one transient enclosure answer is a run of one, inside the infra window.
    @Test func aNewIDsFirstBadSweepIsNotReportable() throws {
        let id = try channelEntry().recipeID
        var baseline = Baseline()
        let warn = Finding(
            recipeID: id, registry: .feed, bundleID: "b", channel: "beta", status: .warn,
            warnings: ["installURLNotFound: HTTP 404 from downloads.example.com"],
            endpointHost: "feeds.example.com")
        baseline.reconcile(warn)
        #expect(!baseline.isReportable(id))

        let transientID = id + ":t"
        let transient = Finding(
            recipeID: transientID, registry: .feed, bundleID: "b", channel: "beta", status: .ok,
            version: "4.2.0", warnings: ["installURLTransient: HTTP 503"],
            endpointHost: "feeds.example.com")
        baseline.reconcile(transient)
        let entry = try #require(baseline.entries[transientID])
        #expect(entry.consecutiveInstallTransient == 1)
        #expect(!entry.isInstallTransientReportable())
        #expect(!baseline.isReportable(transientID))
    }
}
