import Testing
import Foundation
import DuoUpdaterCore
@testable import DuoKit

/// The one check that can see an UPSTREAM rename.
///
/// Everything else in the sweep goes green while a renamed slug rides GitHub's
/// 301: detection returns the right version, the pattern fixtures pass, and
/// `batchRuleSlugsArePinned` compares our slug to our own pinned copy of it, so
/// it agrees with itself. Three rules drifted that way unnoticed. What the
/// redirect actually costs is the request's `Authorization` header — measured
/// 2026-08-29: the same URLSession answered `x-ratelimit-limit: 5000` on the
/// canonical name and `60` (the anonymous ceiling) through the redirect. See #135.
struct GitHubEndpointAuditTests {

    private static func observation(
        requested: String = "block/goose",
        canonical: String? = "aaif-goose/goose",
        redirected: Bool = true,
        ceiling: Int? = 60,
        sentToken: Bool = true
    ) -> GitHubEndpointAudit.Observation {
        GitHubEndpointAudit.Observation(
            requestedSlug: requested, canonicalSlug: canonical,
            redirected: redirected, rateLimitCeiling: ceiling, sentToken: sentToken)
    }

    // MARK: - the two conditions

    @Test func aRenamedSlugIsNamedWithWhatItShouldBe() throws {
        let complaints = Verify.endpointComplaints([Self.observation()])
        let stale = try #require(complaints.first { $0.hasPrefix("staleSlug:") })
        #expect(stale.contains("block/goose"))
        #expect(stale.contains("aaif-goose/goose"))
    }

    /// The vacuity guard. Every other test here asserts that some shape produces
    /// NO complaint, and all of those keep passing if `endpointComplaints` is
    /// gutted to `return []`. This one pins the shape that actually happened —
    /// redirected, token sent, answered on the anonymous ceiling — and fails if
    /// the check ever stops firing.
    @Test func theShapeThatActuallyHappenedProducesBothComplaints() {
        let complaints = Verify.endpointComplaints([Self.observation()])
        #expect(complaints.contains { $0.hasPrefix("staleSlug:") })
        #expect(complaints.contains { $0.hasPrefix("anonymousDespiteToken:") })
    }

    @Test func aHealthyRuleSaysNothing() {
        #expect(Verify.endpointComplaints([Self.observation(
            requested: "aaif-goose/goose", canonical: "aaif-goose/goose",
            redirected: false, ceiling: 5000)]).isEmpty)
    }

    @Test func slugComparisonIgnoresCase() {
        // GitHub is case-insensitive about owner/repo and will happily answer
        // `AAIF-Goose/goose`; that is not a rename and must not be reported as one.
        #expect(Verify.endpointComplaints([Self.observation(
            requested: "AAIF-Goose/Goose", canonical: "aaif-goose/goose",
            redirected: false, ceiling: 5000)]).isEmpty)
    }

    // MARK: - what must NOT be reported

    /// The whole point of gating on `sentToken`. A user with no token is answered
    /// `60` on every one of the 69 rules; complaining there would bury the signal
    /// under 69 copies of "you have no token", which is not what this check is for.
    @Test func noTokenMeansSixtyIsSimplyTheTruth() {
        let complaints = Verify.endpointComplaints([Self.observation(
            requested: "aaif-goose/goose", canonical: "aaif-goose/goose",
            redirected: false, ceiling: 60, sentToken: false)])
        #expect(!complaints.contains { $0.hasPrefix("anonymousDespiteToken:") })
    }

    @Test func anAuthenticatedCeilingIsNotAComplaint() {
        #expect(!Verify.endpointComplaints([Self.observation(
            requested: "aaif-goose/goose", canonical: "aaif-goose/goose",
            redirected: false, ceiling: 5000)])
            .contains { $0.hasPrefix("anonymousDespiteToken:") })
    }

    @Test func aMissingCeilingHeaderIsNotReadAsAnonymous() {
        // A response with no `x-ratelimit-limit` says nothing either way, and
        // guessing would turn every proxy that strips headers into a false alarm.
        #expect(!Verify.endpointComplaints([Self.observation(
            requested: "aaif-goose/goose", canonical: "aaif-goose/goose",
            redirected: false, ceiling: nil)])
            .contains { $0.hasPrefix("anonymousDespiteToken:") })
    }

    // MARK: - a redirect nobody can name

    /// A redirect we cannot name is not reported as a rename — there is no
    /// canonical slug to put in the message — but it must not be reported as
    /// *nothing* either. Every non-2xx answer arrives this way (no body, so no
    /// `html_url`), and a 403 from an exhausted anonymous budget is the loudest
    /// form of the problem this whole audit exists to explain.
    @Test func aRedirectWithNoReleaseToNameItFallsBackToTheWeakerComplaint() {
        let complaints = Verify.endpointComplaints([Self.observation(canonical: nil)])
        #expect(!complaints.contains { $0.hasPrefix("staleSlug:") })
        let unnamed = complaints.first { $0.hasPrefix("staleSlugUnnamed:") }
        #expect(unnamed != nil, "a redirect with no name must still be reported")
        #expect(unnamed?.contains("block/goose") == true, "it has to name what we asked for")
    }

    /// The 403 shape end to end: no token would have helped, because the token
    /// never reached the endpoint that answered. Both halves have to speak.
    @Test func anExhaustedBudgetBehindARenameReportsBothHalves() {
        let complaints = Verify.endpointComplaints([Self.observation(
            requested: "block/goose", canonical: nil, redirected: true,
            ceiling: 60, sentToken: true)])
        #expect(complaints.contains { $0.hasPrefix("staleSlugUnnamed:") })
        #expect(complaints.contains { $0.hasPrefix("anonymousDespiteToken:") })
    }

    /// Named and unnamed are alternatives, never both — two lines describing one
    /// redirect would read as two problems.
    @Test func aNamedRenameSuppressesTheWeakerLine() {
        let complaints = Verify.endpointComplaints([Self.observation()])
        #expect(complaints.contains { $0.hasPrefix("staleSlug:") })
        #expect(!complaints.contains { $0.hasPrefix("staleSlugUnnamed:") })
    }

    // MARK: - one rule, several requests

    /// `/releases/latest` then the list fallback is two observations of one rule.
    /// The reader gets one line per problem, not one per HTTP request.
    @Test func twoRequestsForOneRuleStillComplainOnce() {
        let complaints = Verify.endpointComplaints([Self.observation(), Self.observation()])
        #expect(complaints.filter { $0.hasPrefix("staleSlug:") }.count == 1)
        #expect(complaints.filter { $0.hasPrefix("anonymousDespiteToken:") }.count == 1)
    }
}
