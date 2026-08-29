import Testing
import Foundation
@testable import DuoUpdaterCore

/// The Core half of the rename guard: reading a repo's real name out of the
/// answer, and deciding what counts as a fault.
///
/// The complaint text and the once-per-rule reduction live in `DuoKit`
/// (`GitHubEndpointAuditTests` there). Split because `slug(fromHTMLURL:)` is an
/// implementation detail of this module and testing it from the CLI would mean
/// making it public for no other reason. See #135.
struct GitHubEndpointAuditTests {

    // MARK: - reading the canonical name out of html_url

    @Test func aReleaseURLNamesTheRepoItReallyCameFrom() {
        #expect(GitHubEndpointAudit.slug(fromHTMLURL:
            URL(string: "https://github.com/aaif-goose/goose/releases/tag/v1.48.0"))
            == "aaif-goose/goose")
    }

    @Test func aNonGitHubHostIsNeverReadAsASlug() {
        // `html_url` is GitHub's own field today, but two path components on some
        // other host must never be mistaken for owner/repo and reported as a
        // rename — that would name a "canonical slug" that does not exist.
        #expect(GitHubEndpointAudit.slug(fromHTMLURL:
            URL(string: "https://example.com/aaif-goose/goose")) == nil)
    }

    /// The host test is an exact match or a real subdomain. `hasSuffix` is the
    /// obvious way to write it and it is wrong: these three all end in
    /// "github.com" without being it, and GitHub Enterprise instances on custom
    /// domains are named exactly like this. A false slug is worse than no slug —
    /// it makes the sweep tell someone to repoint a rule at a repo that does not
    /// exist, which kills detection for that app outright.
    @Test func aHostThatMerelyEndsInGitHubDotComIsNotGitHub() {
        for host in ["mygithub.com", "evil-github.com", "notgithub.com"] {
            #expect(GitHubEndpointAudit.slug(fromHTMLURL:
                URL(string: "https://\(host)/aaif-goose/goose")) == nil,
                "\(host) must not be read as github.com")
        }
    }

    @Test func aRealGitHubSubdomainIsStillGitHub() {
        #expect(GitHubEndpointAudit.slug(fromHTMLURL:
            URL(string: "https://api.github.com/aaif-goose/goose")) == "aaif-goose/goose")
    }

    @Test func aURLTooShortToCarryASlugYieldsNothing() {
        #expect(GitHubEndpointAudit.slug(fromHTMLURL:
            URL(string: "https://github.com/aaif-goose")) == nil)
        #expect(GitHubEndpointAudit.slug(fromHTMLURL: nil) == nil)
    }

    // MARK: - what the observation itself concludes

    private static func observation(
        requested: String, canonical: String?, ceiling: Int?, sentToken: Bool
    ) -> GitHubEndpointAudit.Observation {
        GitHubEndpointAudit.Observation(
            requestedSlug: requested, canonicalSlug: canonical,
            redirected: canonical.map { $0 != requested } ?? false,
            rateLimitCeiling: ceiling, sentToken: sentToken)
    }

    @Test func aDifferentCanonicalNameIsAStaleSlug() {
        #expect(Self.observation(
            requested: "block/goose", canonical: "aaif-goose/goose",
            ceiling: 60, sentToken: true).staleSlug == "aaif-goose/goose")
    }

    @Test func theSameNameInDifferentCaseIsNotARename() {
        // GitHub answers `AAIF-Goose/Goose` as happily as the lowercase form.
        #expect(Self.observation(
            requested: "AAIF-Goose/Goose", canonical: "aaif-goose/goose",
            ceiling: 5000, sentToken: true).staleSlug == nil)
    }

    /// The measured shape from #135: we sent a token and were answered on the
    /// anonymous ceiling, because URLSession dropped `Authorization` following
    /// GitHub's rename redirect. This is the assertion that fails if the check
    /// ever stops noticing.
    @Test func aTokenAnsweredOnTheAnonymousCeilingIsAFault() {
        #expect(Self.observation(
            requested: "block/goose", canonical: "aaif-goose/goose",
            ceiling: 60, sentToken: true).authSilentlyDropped)
    }

    @Test func sixtyWithoutATokenIsSimplyTheTruth() {
        // A user with no token is answered 60 on all 69 rules. Reporting that
        // would bury the real signal under 69 copies of "you have no token".
        #expect(!Self.observation(
            requested: "aaif-goose/goose", canonical: "aaif-goose/goose",
            ceiling: 60, sentToken: false).authSilentlyDropped)
    }

    @Test func anAuthenticatedCeilingIsNotAFault() {
        #expect(!Self.observation(
            requested: "aaif-goose/goose", canonical: "aaif-goose/goose",
            ceiling: 5000, sentToken: true).authSilentlyDropped)
    }

    @Test func aMissingCeilingHeaderIsNotReadAsAnonymous() {
        // Guessing would turn any proxy that strips the header into a false alarm.
        #expect(!Self.observation(
            requested: "aaif-goose/goose", canonical: "aaif-goose/goose",
            ceiling: nil, sentToken: true).authSilentlyDropped)
    }

    // MARK: - a redirect nobody can name

    /// Every non-2xx answer lands here: no body, so no `html_url`, so no
    /// canonical name — but the redirect still happened and still cost the
    /// request its token. Without `redirectedButUnnamed` the case carrying the
    /// least information would also be the case the sweep says nothing about.
    @Test func aRedirectWithNothingToNameItStillSpeaks() {
        let observed = GitHubEndpointAudit.Observation(
            requestedSlug: "block/goose", canonicalSlug: nil, redirected: true,
            rateLimitCeiling: 60, sentToken: false)
        #expect(observed.staleSlug == nil, "there is no name to give")
        #expect(observed.redirectedButUnnamed)
    }

    @Test func aNamedRedirectIsNotAlsoReportedAsUnnamed() {
        let observed = GitHubEndpointAudit.Observation(
            requestedSlug: "block/goose", canonicalSlug: "aaif-goose/goose",
            redirected: true, rateLimitCeiling: 60, sentToken: true)
        #expect(!observed.redirectedButUnnamed, "the named complaint covers it")
    }

    @Test func noRedirectIsNeverUnnamed() {
        let url = "https://github.com/aaif-goose/goose/releases/tag/v1"
        let observed = GitHubEndpointAudit.Observation(
            requestedSlug: "aaif-goose/goose",
            canonicalSlug: GitHubEndpointAudit.slug(fromHTMLURL: URL(string: url)),
            redirected: false, rateLimitCeiling: 5000, sentToken: true)
        #expect(!observed.redirectedButUnnamed)
    }

    // MARK: - the failure path really does record (network)

    /// The finding this test exists for: `record` used to sit *after* the
    /// `guard (200..<300)` in `fetchReleases`, so a non-2xx threw before anything
    /// was written and the ledger came back empty. That is the 403 case — an
    /// exhausted anonymous budget under a rule that lost its token to a rename
    /// redirect — i.e. the audit was blind in precisely the situation it was
    /// built to explain.
    ///
    /// Asserting on `endpointComplaints` cannot catch that: it takes observations
    /// as input, so it passes whether or not any were ever recorded. The only
    /// thing that pins it is driving a real non-2xx through the real source and
    /// looking at the ledger. Hits the network; 404 is stable and costs one
    /// request.
    @Test func aNonSuccessResponseIsStillRecorded() async throws {
        let source = GitHubReleasesSource(token: GitHubToken.resolve())
        let rule = GitHubReleaseRule(
            bundleID: "com.example.nonexistent",
            owner: "jizhi0v0", repo: "duo-updater-no-such-repo-135")
        let ledger = GitHubEndpointAudit.Ledger()
        let outcome = await GitHubEndpointAudit.$ledger.withValue(ledger) {
            await source.resolveDiagnostic(rule)
        }
        // Any non-2xx exercises the path; deliberately NOT pinned to 404. On a
        // machine whose anonymous GitHub budget is spent this comes back 403
        // instead, and a test that insisted on 404 would fail for a reason that
        // has nothing to do with what it is checking.
        let kind = try #require(outcome.failure?.kind)
        #expect(kind.hasPrefix("httpStatus"), "expected a status failure, got \(kind)")
        let observed = try #require(
            ledger.observations.first,
            "a non-2xx must still be recorded — this is the whole finding")
        #expect(observed.requestedSlug == "jizhi0v0/duo-updater-no-such-repo-135")
        #expect(observed.canonicalSlug == nil, "no body, so nothing to name it with")
    }

    // MARK: - the app pays nothing

    /// `record` is a no-op with no ledger installed — that is what keeps this
    /// verification-only machinery out of the shipping check path.
    @Test func withNoLedgerInstalledNothingIsRecorded() {
        #expect(GitHubEndpointAudit.ledger == nil)
        GitHubEndpointAudit.record(
            requestedSlug: "block/goose",
            requestedURL: URL(string: "https://api.github.com/repos/block/goose/releases/latest")!,
            response: HTTPURLResponse(
                url: URL(string: "https://api.github.com/repositories/846698999/releases/latest")!,
                statusCode: 200, httpVersion: nil,
                headerFields: ["x-ratelimit-limit": "60"])!,
            firstReleaseHTMLURL: URL(string: "https://github.com/aaif-goose/goose/releases/tag/v1"),
            sentToken: true)
        // Nothing to assert beyond "this did not trap"; the ledger it would have
        // written to does not exist.
        #expect(GitHubEndpointAudit.ledger == nil)
    }

    @Test func aLedgerRecordsWhatTheResponseSaid() throws {
        let ledger = GitHubEndpointAudit.Ledger()
        GitHubEndpointAudit.$ledger.withValue(ledger) {
            GitHubEndpointAudit.record(
                requestedSlug: "block/goose",
                requestedURL: URL(string: "https://api.github.com/repos/block/goose/releases/latest")!,
                response: HTTPURLResponse(
                    url: URL(string: "https://api.github.com/repositories/846698999/releases/latest")!,
                    statusCode: 200, httpVersion: nil,
                    headerFields: ["x-ratelimit-limit": "60"])!,
                firstReleaseHTMLURL: URL(string: "https://github.com/aaif-goose/goose/releases/tag/v1.48.0"),
                sentToken: true)
        }
        let observed = try #require(ledger.observations.first)
        #expect(observed.redirected, "the final URL differs from the one we asked for")
        #expect(observed.staleSlug == "aaif-goose/goose")
        #expect(observed.authSilentlyDropped)
    }

    @Test func aResponseThatDidNotRedirectSaysSo() throws {
        let url = URL(string: "https://api.github.com/repos/aaif-goose/goose/releases/latest")!
        let ledger = GitHubEndpointAudit.Ledger()
        GitHubEndpointAudit.$ledger.withValue(ledger) {
            GitHubEndpointAudit.record(
                requestedSlug: "aaif-goose/goose", requestedURL: url,
                response: HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["x-ratelimit-limit": "5000"])!,
                firstReleaseHTMLURL: URL(string: "https://github.com/aaif-goose/goose/releases/tag/v1.48.0"),
                sentToken: true)
        }
        let observed = try #require(ledger.observations.first)
        #expect(!observed.redirected)
        #expect(observed.staleSlug == nil)
        #expect(!observed.authSilentlyDropped)
    }
}
