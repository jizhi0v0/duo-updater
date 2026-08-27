import Foundation
import Testing
import DuoUpdaterCore

@testable import DuoKit

/// The check that would have caught the Edge pages (issue #107).
///
/// A `changelogURL` is never parsed, so no other sweep check touches it: a
/// vendor retires the page, the button opens a 404, and every test stays green
/// because the URL's *shape* is still perfectly valid. Three Microsoft Edge
/// channels sat that way until someone fetched all 87 by hand.
///
/// What is worth testing here is not the fetch — it is the judgment. This check
/// runs against 87 third-party docs sites on every sweep, and it is one wrong
/// classification away from filing public issues against recipes that work.
struct ChangelogLinkSweepTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: what may accuse a recipe

    /// Only a server ASSERTING the page does not exist is allowed to be a
    /// warning, because only a warning accumulates a streak and files an issue.
    @Test func onlyGoneStatusesProduceAWarning() {
        let page = url("https://learn.microsoft.com/deployedge/microsoft-edge-relnotes")
        for code in [404, 410] {
            let complaint = ChangelogLinkSweep.complaint(for: .gone(code), url: page)
            let text = try! #require(complaint)
            #expect(!text.hasPrefix(Finding.machineNotePrefix),
                    "HTTP \(code) is the vendor stating the page is gone — it must accuse")
            #expect(text.contains(page.absoluteString),
                    "the report has to name the dead URL or nobody can fix it")
        }
    }

    /// …and it must still name it AFTER redaction, which is the only form anyone
    /// reads.
    ///
    /// `Finding.init` runs `Redactor.text` over every warning, and one registry
    /// URL trips it: Notion's release-notes page ends in a 32-character hex id,
    /// which is indistinguishable from an opaque license key, so `«redacted»`
    /// replaces it. Asserting on `complaint(for:url:)` alone would have missed
    /// that entirely — it checks the string before the only transformation that
    /// can damage it.
    ///
    /// What must survive is enough to find the page: scheme, host, and the part of
    /// the path a human can search for. The finding also carries the recipe id, so
    /// a redacted tail costs nobody the fix.
    @Test func theDeadURLSurvivesRedaction() {
        let notion = url(
            "https://notion.notion.site/What-s-New-Mac-Windows-5936dabc8dd6497895786c91b9d6f12a")
        let complaint = try! #require(ChangelogLinkSweep.complaint(for: .gone(404), url: notion))
        let published = Finding(
            recipeID: "vendor:notion.id:stable", registry: .vendor,
            bundleID: "notion.id", channel: "stable", status: .ok, version: "4.19.0",
            warnings: [complaint], endpointHost: "notion.notion.site")
        let text = try! #require(published.publicWarnings.first)
        #expect(text.contains("https://notion.notion.site/What-s-New-Mac-Windows"),
                "redaction ate more than the opaque id — the report no longer names the page")
        #expect(text.contains("404"))
    }

    /// A 403 is as consistent with Cloudflare as with a dead page, and a sweep
    /// that files issues for those trains its reader to ignore it.
    ///
    /// Issue #107 reported AnyDesk's changelog as a 403 — measured with `curl`.
    /// Through `URLSession` it answers 200 (verified 2026-08-28), so the wall was
    /// reading the client rather than guarding a dead page, and the real sweep
    /// never sees this case for that URL. The synthetic verdict below is
    /// deliberate: what needs pinning is that an inconclusive status stays silent,
    /// not which vendor happens to produce one this month.
    @Test func aBotWallIsANoteRatherThanAnAccusation() {
        let complaint = ChangelogLinkSweep.complaint(
            for: .inconclusive("answered HTTP 403"),
            url: url("https://vendor.invalid/changelog"))
        let text = try! #require(complaint)
        #expect(text.hasPrefix(Finding.machineNotePrefix))
    }

    /// And the note really does stay silent all the way through — attached to a
    /// finding it must not promote it, or the distinction above is a spelling.
    @Test func aNoteNeverPromotesTheFinding() {
        let finding = Finding(
            recipeID: "vendor:com.example.app:stable", registry: .vendor,
            bundleID: "com.example.app", channel: "stable",
            status: .ok, version: "9.5.4",
            endpointHost: "vendor.invalid", pattern: "([0-9.]+)")
        let note = ChangelogLinkSweep.complaint(
            for: .inconclusive("answered HTTP 403"),
            url: url("https://vendor.invalid/changelog"))!
        #expect(finding.observing(note).status == .ok)
        #expect(finding.observing(note).publicWarnings.isEmpty)
    }

    /// A host that no longer resolves reads as its own thing.
    ///
    /// It stays a note rather than an accusation — DNS fails for local reasons,
    /// and a sweep box behind a broken resolver must not file 87 issues — but
    /// "does not resolve" is the one inconclusive shape a reader can act on,
    /// because retiring the whole docs subdomain is a real way for a vendor to
    /// kill a changelog page.
    @Test func aHostThatDoesNotResolveSaysSo() {
        let text = try! #require(ChangelogLinkSweep.complaint(
            for: .inconclusive("does not resolve — the host itself may be retired"),
            url: url("https://docs.gone.invalid/changelog")))
        #expect(text.hasPrefix(Finding.machineNotePrefix))
        #expect(text.contains("does not resolve"))
    }

    /// A page that answers is not worth a line in the report at all.
    @Test func aLivePageSaysNothing() {
        #expect(ChangelogLinkSweep.complaint(
            for: .alive, url: url("https://tailscale.com/changelog")) == nil)
    }

    /// The bug the first full live run caught, pinned so it cannot come back.
    ///
    /// A HEAD is *supposed* to be a GET without the body, and plenty of hosts do
    /// not implement it that way. `www.workbuddy.ai` and `www.codebuddy.cn`
    /// answer HEAD with 404 and GET with 200 and a full page (measured
    /// 2026-08-28). The first draft of `verdict` retried only on 403/405/400 —
    /// the codes that obviously mean "not that method" — and so reported both
    /// pages as gone, by name, on findings that were otherwise `ok`. Two working
    /// recipes would have been accused on the next nightly sweep.
    ///
    /// The rule that fixes it is the one this test states: **a HEAD may only
    /// confirm a page alive.** Anything else gets re-asked with GET, and the
    /// GET's answer is the authoritative one.
    ///
    /// Driven through a stub protocol rather than the network, so it keeps
    /// meaning something on a machine with no route to either vendor.
    @Test func aHeadOnlyEverConfirmsAPageAlive() async {
        let page = url("https://vendor.invalid/docs/Changelog")

        // The WorkBuddy shape: HEAD 404, GET 200. Must be alive.
        StubProtocol.responses = ["HEAD": 404, "GET": 200]
        #expect(await ChangelogLinkSweep.verdict(for: page, session: StubProtocol.session())
            == .alive)

        // A page that is really gone answers both, and must still be caught —
        // otherwise the fix has simply turned the check off.
        StubProtocol.responses = ["HEAD": 404, "GET": 404]
        #expect(await ChangelogLinkSweep.verdict(for: page, session: StubProtocol.session())
            == .gone(404))

        // And the GET is authoritative in the other direction too: a HEAD that
        // says 200 is believed without a second request, which is what keeps the
        // healthy path at one request per page.
        StubProtocol.responses = ["HEAD": 200, "GET": 404]
        #expect(await ChangelogLinkSweep.verdict(for: page, session: StubProtocol.session())
            == .alive)

        // A bot wall on both verbs stays inconclusive rather than becoming an
        // accusation.
        StubProtocol.responses = ["HEAD": 403, "GET": 403]
        #expect(await ChangelogLinkSweep.verdict(for: page, session: StubProtocol.session())
            == .inconclusive("answered HTTP 403"))
    }

    // MARK: what gets fetched

    /// Several recipes legitimately share one page — Chrome's four channels,
    /// Firefox's trains — and asking one host the same question four times is
    /// four times the rate-limit exposure for no extra signal.
    ///
    /// Derived from the registry rather than asserted as a number, so this keeps
    /// meaning something as recipes come and go: whatever the registry holds, the
    /// sweep must cover all of it and no more. (An earlier draft also asserted
    /// that `pages` has no duplicates, which `pages` guarantees by construction
    /// with a `Set` — true no matter how broken the rest of it was.)
    @Test func everyDeclaredPageIsSweptExactlyOnce() {
        let pages = ChangelogLinkSweep.pages(of: VendorProbeRegistry.recipes)
        let declared = Set(VendorProbeRegistry.recipes.compactMap(\.changelogURL)
            .map(\.absoluteString))
        #expect(Set(pages.map(\.absoluteString)) == declared)
        #expect(pages.count < VendorProbeRegistry.recipes.compactMap(\.changelogURL).count,
                "nothing is being deduplicated — either the registry stopped sharing pages or pages(of:) stopped collapsing them")
    }

    /// A page another check already fetches is not asked a second time: 17 of the
    /// 87 are also a `ChangelogRecipe.source`, which `sweepChangelog` GETs and
    /// parses in the same run. Two checks on one URL can contradict each other in
    /// one report — "parsed 2 entries" and "the page is gone" — and the GET is the
    /// better evidence.
    @Test func pagesTheChangelogSweepAlreadyFetchesAreSkipped() {
        let shared = Set(ChangelogRecipeRegistry.recipes.map(\.source.absoluteString))
        let all = ChangelogLinkSweep.pages(of: VendorProbeRegistry.recipes)
        let trimmed = ChangelogLinkSweep.pages(
            of: VendorProbeRegistry.recipes, alreadyFetched: shared)
        #expect(trimmed.count < all.count, "the two registries no longer overlap at all — re-read whether this exclusion still earns its place")
        #expect(!trimmed.contains { shared.contains($0.absoluteString) })
        // …and nothing else was dropped along the way.
        #expect(Set(all.map(\.absoluteString)).subtracting(shared)
            == Set(trimmed.map(\.absoluteString)))
    }

    /// Chrome is the concrete case the dedupe exists for, and it is worth
    /// pinning: if a future edit gives each channel its own page this test wants
    /// to be re-read rather than to quietly pass.
    @Test func chromesFourChannelsShareOnePage() {
        let chrome = VendorProbeRegistry.recipes
            .filter { $0.bundleID.hasPrefix("com.google.Chrome") }
            .compactMap(\.changelogURL)
        #expect(chrome.count == 4, "Chrome now has \(chrome.count) channels carrying a changelog URL")
        #expect(Set(chrome.map(\.absoluteString)).count == 1)
    }

    /// A version-templated recipe must NOT take its page out of this sweep.
    ///
    /// The exclusion above is sound only for recipes that actually fetch their
    /// `source`. A templated one fetches `resolvedSource(forVersion:)` instead —
    /// `source` is just the fallback — so excluding by `source` would drop a URL
    /// from the link sweep that nothing else ever requests, which is the silent
    /// rot this whole check exists to end. Three registry recipes are templated
    /// AND share a vendor `changelogURL` (WeChat, Longbridge stable and preview),
    /// and on a runner with nothing installed they are `.skipped` and never
    /// fetched at all, so the gap would be permanent.
    ///
    /// Derived from the registries, so it keeps holding as recipes come and go.
    @Test func templatedRecipesDoNotRemoveTheirPageFromTheSweep() {
        let vendorPages = Set(
            VendorProbeRegistry.recipes.compactMap(\.changelogURL).map(\.absoluteString))
        let templatedOverlap = Set(
            ChangelogRecipeRegistry.recipes
                .filter { $0.sourceTemplate != nil && vendorPages.contains($0.source.absoluteString) }
                .map(\.source.absoluteString))
        try! #require(!templatedOverlap.isEmpty,
                      "no templated recipe shares a changelogURL any more — re-read whether this guard still has a case to guard")

        // What `Verify.run` builds: only the recipes that really fetch `source`.
        let excluded = Set(
            ChangelogRecipeRegistry.recipes
                .filter { $0.sourceTemplate == nil }
                .map(\.source.absoluteString))
        #expect(excluded.isDisjoint(with: templatedOverlap))

        let swept = Set(ChangelogLinkSweep.pages(
            of: VendorProbeRegistry.recipes, alreadyFetched: excluded).map(\.absoluteString))
        for page in templatedOverlap {
            #expect(swept.contains(page),
                    "\(page) is fetched by nobody: the changelog sweep resolves a templated URL instead, and the link sweep excluded it")
        }
    }

    // MARK: the Edge recipes this issue was filed about

    /// Microsoft did not retire these — it renamed them, from
    /// `microsoft-edge-relnotes-<channel>` to `microsoft-edge-relnote-<channel>`
    /// (singular). Issue #107 concluded "genuinely gone" after trying three
    /// alternatives that were all *plural*, which is why the fix is one letter
    /// for two of the three.
    @Test func edgeStableAndBetaPointAtThePagesThatExist() {
        func recipe(_ bundleID: String) -> VendorProbeRecipe {
            // `#require`d, not optional-chained: `changelog(x) == nil` would also
            // be satisfied by the recipe having been deleted, so the Dev
            // assertion below could not tell "deliberately has no notes page"
            // from "is gone from the registry".
            try! #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID },
                          "\(bundleID) is no longer in the registry")
        }
        func changelog(_ bundleID: String) -> URL? { recipe(bundleID).changelogURL }
        #expect(changelog("com.microsoft.edgemac")?.absoluteString
            == "https://learn.microsoft.com/deployedge/microsoft-edge-relnote-stable-channel")
        #expect(changelog("com.microsoft.edgemac.Beta")?.absoluteString
            == "https://learn.microsoft.com/deployedge/microsoft-edge-relnote-beta-channel")
        // Dev is the one that really is gone: `deployedge`'s own `toc.json`
        // (2026-08-28) lists release notes for Beta, Stable, Mobile Beta and
        // Mobile Stable and nothing else, and Learn's search API returns no Dev
        // page either. Pointing the button at Beta's or Stable's notes would show
        // a Dev user another train's changes — the same call Thunderbird Daily
        // gets — so this must stay nil rather than drift to a "close enough" page.
        #expect(changelog("com.microsoft.edgemac.Dev") == nil)
    }
}

/// Answers by HTTP method, so the HEAD-vs-GET rule can be tested without a
/// network route to any vendor.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: Int] = [:]

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let code = Self.responses[method] ?? 200
        let response = HTTPURLResponse(
            url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}
