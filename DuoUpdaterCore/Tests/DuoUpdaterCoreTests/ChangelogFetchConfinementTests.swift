import Testing
import Foundation
@testable import DuoUpdaterCore

/// The changelog fetch holds to `ChangelogURLPolicy` the way the web view does:
/// the URL it starts from, and every redirect it is sent on.
///
/// The policy used to gate only what a web view loads (`WorkbenchWindowView`),
/// while `ChangelogService` fetched whatever a recipe, or a link scraped from an
/// index page (`indexLinkPattern`), or a 3xx pointed at. App Transport Security
/// does not close that: the app carries no ATS exception, which leaves loopback
/// `http://` and any `https://` host reachable (measured in the 2026-10-25
/// review), so a redirect to `https://192.168.1.1/` or `http://127.0.0.1:9/`
/// was followed.
@Suite(.serialized)
struct ChangelogFetchConfinementTests {

    // MARK: - the marker

    @Test func onlyAConfinedRequestIsHeldToThePolicy() {
        let plain = URLRequest(url: URL(string: "https://example.com/notes")!)
        let confined = ChangelogURLPolicy.confine(plain)
        let rejected = [
            "http://example.com/notes", "https://192.168.1.10/notes", "https://localhost/notes",
            "https://example.com:8443/notes", "https://user:pw@example.com/notes",
        ].map { URL(string: $0)! }
        for target in rejected {
            #expect(ChangelogURLPolicy.allowsRedirect(of: plain, to: target), "unconfined: \(target)")
            #expect(!ChangelogURLPolicy.allowsRedirect(of: confined, to: target), "confined: \(target)")
        }
        // A redirect that passes the policy is followed, off-site included: vendors
        // do move notes between their own domains, and this is not `SameSite`.
        #expect(ChangelogURLPolicy.allowsRedirect(
            of: confined, to: URL(string: "https://docs.other-domain.example/changelog")))
        #expect(!ChangelogURLPolicy.allowsRedirect(of: confined, to: nil))
    }

    /// Independent of the same-site marker: confining one way must not switch on
    /// the other (`BrewFormulaIconService` uses `SameSite.confine` alone).
    @Test func theMarkersAreIndependent() {
        let plain = URLRequest(url: URL(string: "https://example.com/")!)
        let offSiteOK = URL(string: "https://cdn.other.example/x")!
        #expect(SameSite.allowsRedirect(of: ChangelogURLPolicy.confine(plain), to: offSiteOK))
        #expect(ChangelogURLPolicy.allowsRedirect(of: SameSite.confine(plain), to: URL(string: "http://x.example/")))
    }

    // MARK: - through ChangelogService

    /// Serves canned pages for https://*.example.invalid and records every URL the
    /// session asked it for, including the ones it should never have been asked.
    private final class Pages: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) private static var seen: [String] = []
        nonisolated(unsafe) private static var redirects: [String: String] = [:]
        nonisolated(unsafe) private static var bodies: [String: String] = [:]
        private static let lock = NSLock()

        static func reset(redirects: [String: String] = [:], bodies: [String: String] = [:]) {
            lock.withLock { seen = []; self.redirects = redirects; self.bodies = bodies }
        }
        static var requested: [String] { lock.withLock { seen } }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!
            Self.lock.withLock { Self.seen.append(url.absoluteString) }
            if let location = Self.lock.withLock({ Self.redirects[url.absoluteString] }) {
                let redirect = HTTPURLResponse(
                    url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                    headerFields: ["Location": location, "Content-Length": "0"])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!),
                                    redirectResponse: redirect)
                // When the delegate declines the redirect the session expects the
                // 3xx itself to be the answer, as a network load would deliver it;
                // when it follows, this instance has been stopped and these are
                // ignored.
                client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let page = Self.lock.withLock { Self.bodies[url.absoluteString] }
                ?? "<h2>9.8.7</h2><i>2026-10-01</i><ul><li>Fixed the thing</li></ul></section>"
            let body = Data(page.utf8)
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html;charset=utf-8"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    /// The session the app uses (the redirect delegate included), with the network
    /// replaced by `Pages`.
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Pages.self]
        return URLSession(configuration: configuration,
                          delegate: CrossHostCredentialStripper(loginWalls: []), delegateQueue: nil)
    }

    private func recipe(source: String) -> ChangelogRecipe {
        ChangelogRecipe(
            bundleID: "test.changelog-confinement.\(UUID().uuidString)",
            source: URL(string: source)!,
            entryPattern: #"<h2>(?<version>\d+(?:\.\d+)+)</h2><i>(?<date>[^<]*)</i>(?<body>.*?)</section>"#,
            itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])
    }

    private func load(_ recipe: ChangelogRecipe) async -> Changelog? {
        let session = session()
        defer { session.invalidateAndCancel() }
        return await ChangelogService.loadUncached(recipe, feedPage: nil, session: session)
    }

    @Test func controlAnOrdinaryPageIsFetchedAndParsed() async throws {
        Pages.reset()
        let changelog = try #require(await load(recipe(source: "https://notes.example.invalid/changelog")))
        #expect(changelog.entries.map(\.version) == ["9.8.7"])
        #expect(Pages.requested == ["https://notes.example.invalid/changelog"])
    }

    /// A start URL the policy refuses is not requested at all.
    @Test(arguments: [
        "http://notes.example.invalid/changelog",
        "https://127.0.0.1/changelog",
        "https://localhost/changelog",
        "https://notes.example.invalid:8443/changelog",
        "https://user:pw@notes.example.invalid/changelog",
    ])
    func aStartURLTheWebViewWouldRefuseIsNotFetched(source: String) async {
        Pages.reset()
        let changelog = await load(recipe(source: source))
        #expect(changelog == nil)
        #expect(Pages.requested.isEmpty, "requested: \(Pages.requested)")
    }

    /// A redirect to somewhere the policy refuses is not followed: the 3xx comes
    /// back, no notes load, and the second URL is never asked for.
    @Test(arguments: [
        "http://notes.example.invalid/landing",
        "https://192.168.1.1/landing",
        "https://localhost/landing",
        "https://notes.example.invalid:8443/landing",
    ])
    func aRedirectTheWebViewWouldRefuseIsNotFollowed(target: String) async {
        Pages.reset(redirects: ["https://notes.example.invalid/changelog": target])
        let changelog = await load(recipe(source: "https://notes.example.invalid/changelog"))
        #expect(changelog == nil)
        #expect(Pages.requested == ["https://notes.example.invalid/changelog"], "requested: \(Pages.requested)")
    }

    /// And one it accepts still is, to another domain too.
    @Test func aRedirectThePolicyAcceptsIsFollowed() async throws {
        Pages.reset(redirects: [
            "https://notes.example.invalid/changelog": "https://docs.other.invalid/changelog",
        ])
        let changelog = try #require(await load(recipe(source: "https://notes.example.invalid/changelog")))
        #expect(changelog.entries.map(\.version) == ["9.8.7"])
        #expect(Pages.requested == [
            "https://notes.example.invalid/changelog", "https://docs.other.invalid/changelog",
        ])
    }

    /// The second stage of an index/detail recipe: the link comes out of a page the
    /// vendor served (`indexLinkPattern`), and a link to a refused place is not
    /// fetched.
    @Test(arguments: [
        ("https://notes.example.invalid/detail", true),
        ("http://notes.example.invalid/detail", false),
        ("https://192.168.1.1/detail", false),
        ("https://localhost/detail", false),
    ])
    func aDetailLinkIsFetchedOnlyWhenThePolicyAccepts(link: String, fetched: Bool) async {
        Pages.reset(bodies: ["https://notes.example.invalid/index": #"<a href="\#(link)">latest</a>"#])
        let recipe = ChangelogRecipe(
            bundleID: "test.changelog-confinement.index",
            source: URL(string: "https://notes.example.invalid/index")!,
            entryPattern: #"<h2>(?<version>\d+(?:\.\d+)+)</h2><i>(?<date>[^<]*)</i>(?<body>.*?)</section>"#,
            itemPatterns: [#"<li>(?<item>[^<]+)</li>"#],
            indexLinkPattern: #"href="(?<link>[^"]+)""#)
        let changelog = await load(recipe)
        #expect(Pages.requested.contains(link) == fetched, "requested: \(Pages.requested)")
        #expect((changelog != nil) == fetched)
    }
}
