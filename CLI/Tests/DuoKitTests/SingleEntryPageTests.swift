import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// The collapse check against a page that legitimately holds one entry (#821).
///
/// Chrome's Stable label page shows one desktop post whenever the vendor's latest
/// posts are for other platforms. Judged on the count alone that read as
/// "COLLAPSED (3 → 1)", and because a collapsed count is never recorded, every
/// sweep after it compared against the same 3 and warned again. The sweep now
/// asks the page whether an entry swallowed another
/// (`Finding.entrySwallowsAnother`), and only a page that says no is let off.
@Suite struct SingleEntryPageTests {

    private func changelog(entries: Int, swallows: Bool?) -> Finding {
        Finding(
            recipeID: "changelog:com.example.app:-", registry: .changelog,
            bundleID: "com.example.app", channel: "-", status: .ok, version: "4.8.0",
            endpointHost: "example.invalid", entryCount: entries,
            entrySwallowsAnother: swallows)
    }

    /// Mutation: drop `finding.entrySwallowsAnother != false` from
    /// `Baseline.reconcile` — the warning comes back on every sweep.
    @Test func aPageThatHoldsOneEntryIsNotFlagged() {
        var baseline = Baseline()
        let id = "changelog:com.example.app:-"
        _ = baseline.reconcile(changelog(entries: 3, swallows: nil))

        #expect(baseline.reconcile(changelog(entries: 1, swallows: false)).isEmpty)
        #expect(baseline.reconcile(changelog(entries: 1, swallows: false)).isEmpty)
        #expect(baseline.streak(id) == 0)
        // The 1 is still not recorded: the next sweep where the page grows back
        // and its terminator breaks in the same edit has to be judged against 3.
        #expect(baseline.entries[id]?.lastGoodEntryCount == 3)
        #expect(baseline.reconcile(changelog(entries: 1, swallows: true))
            .contains { $0.contains("COLLAPSED") && $0.contains("3 → 1") })
    }

    /// The purpose of the check, kept: a page whose single entry swallowed the
    /// rest still warns, and still builds the streak that files an issue.
    ///
    /// Mutation: `!= false` → `== false` in `Baseline.reconcile`.
    @Test func aCollapsedPageStillWarns() {
        var baseline = Baseline()
        let id = "changelog:com.example.app:-"
        _ = baseline.reconcile(changelog(entries: 20, swallows: nil))
        #expect(baseline.reconcile(changelog(entries: 1, swallows: true))
            .contains { $0.contains("COLLAPSED") })
        #expect(baseline.reconcile(changelog(entries: 1, swallows: true))
            .contains { $0.contains("COLLAPSED") })
        #expect(baseline.isReportable(id))
    }

    /// Through `sweepChangelog`'s real success path: the flag is read off the
    /// page the entries came from, and only when there is one entry.
    ///
    /// Mutation: `entrySwallowsAnother: nil` in `sweepChangelog` — both single
    /// pages read nil, and the legit one warns on the count again.
    @Test func theSweepAsksThePage() async throws {
        func recipe(_ name: String) -> ChangelogRecipe {
            ChangelogRecipe(
                bundleID: "com.example.zz-swallow-\(name)",
                source: URL(string: "https://swallow.invalid/\(name)/")!,
                entryPattern: #"<h2>(?<version>[0-9.]+)</h2>(?<body>.*?)(?=<hr class="sep">|\z)"#,
                itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])
        }
        let collapsed = recipe("collapsed"), single = recipe("single"), healthy = recipe("healthy")
        var options = VerifyOptions()
        options.perHostDelay = .zero
        let findings = await Verify.sweepChangelog(
            [collapsed, single, healthy], options: options, versions: [:],
            versionSources: [], session: SwallowPageStub.session)
        func finding(_ recipe: ChangelogRecipe) throws -> Finding {
            try #require(findings.first { $0.recipeID == recipe.recipeID })
        }

        let swallowed = try finding(collapsed)
        #expect(swallowed.entryCount == 1, "\(String(describing: swallowed.failureDetail))")
        #expect(swallowed.entrySwallowsAnother == true)

        let one = try finding(single)
        #expect(one.entryCount == 1, "\(String(describing: one.failureDetail))")
        #expect(one.entrySwallowsAnother == false)

        let many = try finding(healthy)
        #expect(many.entryCount == 3, "\(String(describing: many.failureDetail))")
        #expect(many.entrySwallowsAnother == nil, "only asked of a single entry")
    }
}

/// Serves three changelog shapes by path: `/collapsed/` three releases whose
/// separator no longer matches the recipe, `/single/` one release, `/healthy/`
/// three releases separated the way the recipe expects.
private final class SwallowPageStub: URLProtocol, @unchecked Sendable {
    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SwallowPageStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "swallow.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        func entries(_ versions: [String], separator: String) -> String {
            versions.map { "<h2>\($0)</h2><ul><li>Fixed a crash in \($0).</li></ul>" }
                .joined(separator: separator)
        }
        let content: String
        switch url.pathComponents.dropFirst().first {
        case "collapsed": content = entries(["3.0", "2.0", "1.0"], separator: #"<hr class="divider">"#)
        case "single": content = entries(["3.0"], separator: "") + #"<hr class="sep"><footer>©</footer>"#
        default: content = entries(["3.0", "2.0", "1.0"], separator: #"<hr class="sep">"#)
        }
        let body = "<html><body>\(content)</body></html>"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
