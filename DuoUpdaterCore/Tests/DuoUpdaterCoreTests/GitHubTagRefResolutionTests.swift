import Testing
import Foundation
@testable import DuoUpdaterCore

/// `GitHubReleaseRule.tagRefPrefix`: a rule that finds its releases by tag ref
/// instead of by position on the `/releases` list page (#947). Cua Driver's
/// nightly train sank off its list page twice, the second time after the page
/// had been deepened, because the vendor's planner held the train while every
/// other train in the monorepo kept publishing (the audit doc has the walk).
/// These pin that such a rule never asks for the list page, orders the tags
/// itself, and walks past a tag that cannot answer.
@Suite(.serialized)
struct GitHubTagRefResolutionTests {

    /// Answers by exact URL string; anything unscripted is a 404, which is
    /// what GitHub answers for a tag with no release behind it.
    private final class ByURLProtocol: URLProtocol, @unchecked Sendable {
        final class Script: @unchecked Sendable {
            private let lock = NSLock()
            private var answers: [String: String] = [:]
            private var requested: [String] = []
            func load(_ table: [String: String]) { lock.lock(); answers = table; requested = []; lock.unlock() }
            func answer(for url: String) -> String? {
                lock.lock(); defer { lock.unlock() }
                requested.append(url)
                return answers[url]
            }
            var urls: [String] { lock.lock(); defer { lock.unlock() }; return requested }
        }
        static let script = Script()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let body = Self.script.answer(for: request.url!.absoluteString)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: body == nil ? 404 : 200,
                httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data((body ?? #"{"message": "Not Found"}"#).utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ByURLProtocol.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// The registry's own nightly rule, so the test runs what users run.
    private static var nightlyRule: GitHubReleaseRule {
        get throws {
            try #require(
                GitHubReleaseRegistry.rules.first {
                    $0.bundleID == "com.trycua.driver" && $0.channel == .nightly
                },
                "com.trycua.driver has no nightly rule any more")
        }
    }

    private static let refsURL =
        "https://api.github.com/repos/trycua/cua/git/matching-refs/tags/nightly-cua-driver-rs-v"
    private static func tagURL(_ tag: String) -> String {
        "https://api.github.com/repos/trycua/cua/releases/tags/\(tag)"
    }

    /// A `matching-refs` body, in the order given. GitHub's real order is lexical.
    private static func refs(_ tags: [String]) -> String {
        "[" + tags.map {
            #"{"ref": "refs/tags/\#($0)", "object": {"type": "commit", "sha": "0"}}"#
        }.joined(separator: ",") + "]"
    }

    /// One release object as `/releases/tags/<tag>` returns it.
    private static func release(_ tag: String, assets: [String]? = nil) -> String {
        let suffix = tag.dropFirst("nightly-cua-driver-rs-v".count)
        let names = assets ?? [
            "cua-driver-rs-\(suffix)-darwin-universal.tar.gz",
            "cua-driver-rs-\(suffix)-darwin-universal-binary.tar.gz",
        ]
        let assetJSON = names.map {
            #"{"name": "\#($0)", "browser_download_url": "https://github.com/trycua/cua/releases/download/\#(tag)/\#($0)", "size": 10}"#
        }.joined(separator: ",")
        return """
        {"tag_name": "\(tag)", "assets": [\(assetJSON)], "prerelease": true, "draft": false,
         "published_at": "2026-09-29T04:57:48Z", "html_url": "https://github.com/trycua/cua/releases/tag/\(tag)"}
        """
    }

    // Real tags from `trycua/cua`, plus one older base whose lexical position
    // (`v0.9…` sorts after `v0.30…`) is the trap a lexical pick falls into.
    private static let newest = "nightly-cua-driver-rs-v0.30.5-nightly.20260929.36522098176"
    private static let second = "nightly-cua-driver-rs-v0.30.3-nightly.20260928.36378326676"
    private static let lexicalRefs = [
        "nightly-cua-driver-rs-v0.19.4-nightly.20260812.31613035038",
        "nightly-cua-driver-rs-v0.30.2-nightly.20260927.36294544935",
        second,
        newest,
        "nightly-cua-driver-rs-v0.9.0-nightly.20260720.30000000000",
    ]

    // MARK: - The #947 shape

    /// The regression itself: the newest nightly is answered from its tag, and
    /// the list page — where it sat below dozens of other trains' releases —
    /// is never requested. Mutations this pins: taking the refs in the order
    /// GitHub returns them (answers 0.9.0 or 0.19.4), and falling through to
    /// the list page (an extra URL, and a miss, since the page is unscripted).
    @Test func theNewestNightlyIsFoundByTagWithoutTheListPage() async throws {
        let rule = try Self.nightlyRule
        ByURLProtocol.script.load([
            Self.refsURL: Self.refs(Self.lexicalRefs),
            Self.tagURL(Self.newest): Self.release(Self.newest),
        ])
        let source = GitHubReleasesSource(rules: [rule], session: Self.session())

        let outcome = await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.failure == nil)
        #expect(outcome.remote?.shortVersion == "0.30.5")
        #expect(outcome.remote?.downloadURL?.absoluteString.hasSuffix(
            "cua-driver-rs-0.30.5-nightly.20260929.36522098176-darwin-universal.tar.gz") == true)
        #expect(ByURLProtocol.script.urls == [Self.refsURL, Self.tagURL(Self.newest)])
    }

    /// A tag pushed before its release is published 404s by tag; the rule
    /// takes the next newest instead of reporting nothing.
    @Test func aTagWithoutAReleaseIsPassedOver() async throws {
        let rule = try Self.nightlyRule
        ByURLProtocol.script.load([
            Self.refsURL: Self.refs(Self.lexicalRefs),
            Self.tagURL(Self.second): Self.release(Self.second),
        ])
        let source = GitHubReleasesSource(rules: [rule], session: Self.session())

        let outcome = await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote?.shortVersion == "0.30.3")
        #expect(ByURLProtocol.script.urls
                == [Self.refsURL, Self.tagURL(Self.newest), Self.tagURL(Self.second)])
    }

    /// A release without the macOS bundle is walked past the same way a list
    /// page walks past it, and the walk stops at the first one that answers.
    @Test func aReleaseWithoutTheMacOSAssetIsWalkedPast() async throws {
        let rule = try Self.nightlyRule
        ByURLProtocol.script.load([
            Self.refsURL: Self.refs(Self.lexicalRefs),
            Self.tagURL(Self.newest): Self.release(Self.newest, assets: ["checksums.txt"]),
            Self.tagURL(Self.second): Self.release(Self.second),
        ])
        let source = GitHubReleasesSource(rules: [rule], session: Self.session())

        let outcome = await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote?.shortVersion == "0.30.3")
        #expect(ByURLProtocol.script.urls
                == [Self.refsURL, Self.tagURL(Self.newest), Self.tagURL(Self.second)])
    }

    /// No tag under the prefix fits the pattern: a version-pattern miss that
    /// names what it saw, never a quiet "up to date".
    @Test func noMatchingTagIsAVersionPatternMiss() async throws {
        let rule = try Self.nightlyRule
        ByURLProtocol.script.load([
            Self.refsURL: Self.refs(["nightly-cua-driver-rs-v1.0.0-preview.1"]),
        ])
        let source = GitHubReleasesSource(rules: [rule], session: Self.session())

        let outcome = await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)

        #expect(outcome.remote == nil)
        guard case .versionPatternNoMatch = outcome.failure else {
            Issue.record("expected versionPatternNoMatch, got \(String(describing: outcome.failure))")
            return
        }
        #expect(outcome.bodySample == "nightly-cua-driver-rs-v1.0.0-preview.1")
        #expect(ByURLProtocol.script.urls == [Self.refsURL])
    }

    // MARK: - Ordering

    /// Numeric, not lexical, and a nightly's date and run id order builds that
    /// share a base — the order the vendor's installer sorts into.
    @Test func tagsAreOrderedNumericallyNewestFirst() throws {
        let rule = try Self.nightlyRule
        let prefix = try #require(rule.tagRefPrefix)
        let ordered = GitHubReleasesSource.newestTagsFirst(
            [
                "nightly-cua-driver-rs-v0.28.3-nightly.20260916.35055871159",
                "nightly-cua-driver-rs-v0.10.0-nightly.20260721.1",
                "nightly-cua-driver-rs-v0.28.3-nightly.20260922.35786783243",
                "nightly-cua-driver-rs-v0.9.1-nightly.20260720.1",
                "nightly-cua-driver-rs-v0.28.3-nightly.20260922.35786783200",
                "cua-driver-rs-v0.34.0",
            ],
            prefix: prefix, pattern: rule.versionPattern)
        #expect(ordered == [
            "nightly-cua-driver-rs-v0.28.3-nightly.20260922.35786783243",
            "nightly-cua-driver-rs-v0.28.3-nightly.20260922.35786783200",
            "nightly-cua-driver-rs-v0.28.3-nightly.20260916.35055871159",
            "nightly-cua-driver-rs-v0.10.0-nightly.20260721.1",
            "nightly-cua-driver-rs-v0.9.1-nightly.20260720.1",
        ])
    }

    // MARK: - Registry invariants

    /// The tag-ref path replaces only the `.newest` list walk. A line-anchored
    /// scope needs the window a list gives, `installedTagPrefix` discovery
    /// reads the list page, and a stable `/releases/latest` rule has its own
    /// endpoint — none of them is what this field changes.
    @Test func tagRefRulesAreWellFormed() {
        let tagRefRules = GitHubReleaseRegistry.rules.filter { $0.tagRefPrefix != nil }
        #expect(!tagRefRules.isEmpty, "no rule uses tagRefPrefix, so this guard checks nothing")
        for rule in tagRefRules {
            let key = "\(rule.bundleID)/\(rule.channel.rawValue)"
            #expect(rule.usePrereleases, "\(key): tagRefPrefix needs usePrereleases")
            #expect(rule.candidateScope == .newest, "\(key): tagRefPrefix needs .newest scope")
            #expect(rule.installedTagPrefix == nil, "\(key): tagRefPrefix and installedTagPrefix don't combine")
            #expect(rule.tagRefPrefix?.isEmpty == false, "\(key): an empty prefix lists every tag in the repo")
        }
    }
}
