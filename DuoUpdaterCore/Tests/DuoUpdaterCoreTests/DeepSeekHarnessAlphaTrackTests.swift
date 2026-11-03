import Foundation
import Testing

@testable import DuoUpdaterCore

/// DeepSeek Harness's `-alpha.N` train — `com.deepseek.dsh`, the 0.2.x desktop
/// client, which runs that train and the feed's `-rc.N`/plain train behind ONE
/// bundle id, one Team (`NAN929V4UM`) and one display name.
///
/// Nothing on disk distinguishes them: an alpha build's own `app-update.yml`
/// says `channel: nightly` too (read off the real 2026-11-03 `0.2.2-alpha.3`
/// DMG, 268,883,910 B). The version string is the whole local signal, which is
/// why `ReleaseChannel.detect` carries a bundle-id-scoped rule for it and the
/// probe beside it is channel-gated to `.alpha`.
///
/// The atom slice below is trimmed from the real feed
/// (`github.com/deepseek-ai/deepseek-harness/releases.atom`, fetched 2026-11-03)
/// and keeps its awkward property: `0.2.1-rc.5` (published 2026-10-30) sits
/// ABOVE `0.2.2-alpha.3` (published later, 2026-11-03) in publish order only —
/// the feed is newest-first, not newest-version-first.
private let deepSeekHarnessAtom = #"""
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Release notes from deepseek-harness</title>
  <entry>
    <title>v0.2.1-rc.5</title>
    <updated>2026-10-30T02:12:26Z</updated>
    <content type="html">&lt;p&gt;Full Changelog: &lt;a href="https://github.com/deepseek-ai/deepseek-harness/compare/dsh-v0.2.1-rc.4...dsh-v0.2.1-rc.5"&gt;dsh-v0.2.1-rc.4...dsh-v0.2.1-rc.5&lt;/a&gt;&lt;/p&gt;</content>
  </entry>
  <entry>
    <title>v0.2.2-alpha.3</title>
    <updated>2026-11-03T07:56:48Z</updated>
    <content type="html">&lt;p&gt;Full Changelog: &lt;a href="https://github.com/deepseek-ai/deepseek-harness/compare/dsh-v0.2.2-alpha.2...dsh-v0.2.2-alpha.3"&gt;dsh-v0.2.2-alpha.2...dsh-v0.2.2-alpha.3&lt;/a&gt;&lt;/p&gt;</content>
  </entry>
  <entry>
    <title>v0.2.2-alpha.2</title>
    <updated>2026-10-28T02:50:54Z</updated>
  </entry>
</feed>
"""#

private let deepSeekHarnessVersionPattern =
    #"<title>v([0-9]+(?:\.[0-9]+)+(?:-(?:alpha|rc)\.[0-9]+)?)</title>"#

@Suite struct DeepSeekHarnessAlphaTrackTests {

    private static let bundleID = "com.deepseek.dsh"

    private func detect(_ version: String, bundleID: String = Self.bundleID) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "DeepSeek Harness", bundleID: bundleID, keystoneChannel: nil,
            version: version, bundleFileName: "DeepSeek Harness.app")
    }

    private var alphaProbe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first {
            $0.bundleID == Self.bundleID && $0.channel == .alpha
        }
    }

    // MARK: - Detection

    @Test func theAlphaBuildReadsAsAlpha() {
        #expect(detect("0.2.2-alpha.3") == .alpha)
        // The number is not load-bearing: the vendor has shipped `-alpha.1`
        // through `-alpha.5` on this line, and a two-digit counter must read the
        // same way (the pattern takes one or more digits).
        #expect(detect("0.2.1-alpha.5") == .alpha)
        #expect(detect("0.2.2-alpha.10") == .alpha)
    }

    /// The feed's train must keep reading stable: `ElectronManifestSource` answers
    /// it from the bundle's own `app-update.yml`, and an `.alpha` reading here
    /// would shadow that with the probe (channel gate) and take the copy off the
    /// vendor's updater.
    @Test func theFeedTrainStaysStable() {
        for version in ["0.2.1-rc.5", "0.2.1-rc.1", "0.2.1", "0.2.0", "0.1.7"] {
            #expect(detect(version) == .stable, "\(version)")
        }
    }

    /// `-alpha` without a counter is not this train's shape; it stays stable
    /// rather than being guessed at.
    @Test func unnumberedOrMangledAlphaTailsAreNotClaimed() {
        for version in ["0.2.2-alpha", "0.2.2-alpha.beta", "alpha.3", "", "0.2.2-alpha.3+sha"] {
            #expect(detect(version) == .stable, "\(version)")
        }
    }

    /// Scoped on purpose: widening step 4's word table would re-label every app
    /// whose version ends `-alpha.N`, and the ones with no `.alpha` recipe would
    /// drop out of the update list entirely.
    @Test func theRuleIsScopedToThisBundleID() {
        #expect(detect("0.2.2-alpha.3", bundleID: "com.example.not-deepseek") == .stable)
    }

    // MARK: - Ordering

    /// The probe resolves the highest version in the feed, so the graduation
    /// order has to hold: alpha → rc → plain, and either prerelease above the
    /// feed's older line.
    @Test func theTrainOrdersAlphaThenReleaseCandidateThenPlain() {
        #expect(VersionComparator.isNewer("0.2.2-alpha.3", than: "0.2.2-alpha.2"))
        #expect(VersionComparator.isNewer("0.2.2-rc.1", than: "0.2.2-alpha.3"))
        #expect(VersionComparator.isNewer("0.2.2", than: "0.2.2-rc.1"))
        #expect(VersionComparator.isNewer("0.2.2-alpha.3", than: "0.2.1-rc.5"))
    }

    // MARK: - Probe

    @Test func theAlphaProbeIsChannelGated() throws {
        let recipe = try #require(alphaProbe, "DeepSeek Harness must have an alpha probe")
        // Channel gating is what keeps this off a stable/rc copy: the two trains
        // share the bundle id.
        #expect(recipe.channel == .alpha)
        #expect(recipe.bundleID == Self.bundleID)
        // The atom feed, not the REST API: no token, no GitHub API budget spent on
        // every check.
        #expect(recipe.url.absoluteString == "https://github.com/deepseek-ai/deepseek-harness/releases.atom")
        #expect(recipe.selectHighest, "the feed is newest-first, not newest-version-first")
    }

    @Test func theAtomFeedResolvesTheNewestBuildNotTheFirstEntry() throws {
        let recipe = try #require(alphaProbe)

        // First match is the feed's first entry — the trap `selectHighest` exists
        // for, pinned so the flag cannot be dropped without a failure.
        #expect(VendorProbeRecipe.extractVersion(
            from: deepSeekHarnessAtom, pattern: recipe.versionPattern) == "0.2.1-rc.5")
        #expect(VendorProbeRecipe.highestVersion(
            from: deepSeekHarnessAtom, pattern: recipe.versionPattern) == "0.2.2-alpha.3")
    }

    @Test func oneClickDownloadsTheVendorsVersionedDMG() throws {
        let recipe = try #require(alphaProbe)
        let spec = try #require(recipe.install, "the alpha train is one-click or it is not wired")
        #expect(spec.kind == .dmg)
        guard case let .versionTemplate(template) = spec.urlSource else {
            Issue.record("the alpha install must be a `.versionTemplate`, got \(spec.urlSource)")
            return
        }
        #expect(template == "https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-{version}-mac-arm64.dmg")

        // Filled with the version the probe resolved — the URL the app downloads is
        // built from the string that was compared.
        let url = template.replacingOccurrences(of: "{version}", with: "0.2.2-alpha.3")
        #expect(url == "https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-0.2.2-alpha.3-mac-arm64.dmg")
    }

    /// No `entryStartPattern`: the pattern is pinned to the feed's `<title>`, so
    /// the body's compare links cannot contribute a version.
    @Test func theVersionPatternOnlyMatchesReleaseTitles() throws {
        let recipe = try #require(alphaProbe)
        #expect(recipe.entryStartPattern == nil)
        // A compare link rendered as markup (rather than escaped text) still is not
        // a `<title>`.
        let markup = #"<a>dsh-v9.9.9-alpha.9</a><title>v0.2.2-alpha.3</title>"#
        #expect(VendorProbeRecipe.highestVersion(
            from: markup, pattern: recipe.versionPattern) == "0.2.2-alpha.3")
    }

    // MARK: - Changelog

    @Test func theAlphaChangelogIsTheOneAlphaInstallsReach() throws {
        let alpha = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID, channel: .alpha),
            "an alpha install must get the alpha recipe")
        #expect(alpha.channel == .alpha)
        #expect(alpha.source.host == "api.github.com")

        // The feed train's recipe must stay FIRST in the file: a `.stable` copy
        // reaches it through the registry's fallback steps, which take the group's
        // first recipe.
        let stable = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID, channel: .stable))
        #expect(stable.channel == .nightly)
        #expect(stable.recipeID != alpha.recipeID)
    }
}

/// The vendor writes release notes for builds it never packaged (`0.2.2-alpha.2`
/// and `0.2.1-alpha.5` have bodies and no DMG). `selectsHighestPublishedBuild`
/// is the answer: confirm the artifact, walk down, offer what exists.
///
/// Driven through the real `probeOutcome` against a local stub, with the
/// registry's own recipe copied onto per-test hosts, so the extraction the app
/// runs (`selectHighest`, the version pattern) is the production one.
@Suite struct DeepSeekHarnessPublishedBuildTests {

    private final class ArtifactServer: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var responses: [String: (status: Int, body: String)] = [:]

        static func serve(_ url: String, status: Int = 200, body: String = "") {
            lock.lock(); defer { lock.unlock() }
            responses[url] = (status, body)
        }

        private static func response(_ url: URL) -> (status: Int, body: String)? {
            lock.lock(); defer { lock.unlock() }
            return responses[url.absoluteString]
                ?? responses["https://\(url.host ?? "")\(url.path)"]
        }

        static func session() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ArtifactServer.self]
            return URLSession(configuration: configuration)
        }

        static func reset() {
            lock.lock(); defer { lock.unlock() }
            responses.removeAll()
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            // Not served == the vendor never published it, which is a 404 rather
            // than a connection failure: the production code tells the two apart.
            let answer = Self.response(url) ?? (status: 404, body: "")
            let response = HTTPURLResponse(
                url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if request.httpMethod != "HEAD", !answer.body.isEmpty {
                client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// Per-test host, so concurrently running tests cannot see each other's
    /// served documents: the stub's table is static, `reset()` is not enough.
    private static func feedURL(_ host: String) -> URL {
        URL(string: "https://feed.\(host).alpha.invalid/releases.atom")!
    }

    private static func artifactTemplate(_ host: String) -> String {
        "https://cdn.\(host).alpha.invalid/bin/deepseek-harness-{version}-mac-arm64.dmg"
    }

    /// Three alphas, newest first. `alpha.4` is the build the vendor wrote about
    /// but never packed in the "lags by one build" case.
    private static let atom = """
        <feed><entry><title>v0.2.2-alpha.4</title></entry>\
        <entry><title>v0.2.2-alpha.3</title></entry>\
        <entry><title>v0.2.2-alpha.2</title></entry></feed>
        """

    private static func artifactURL(_ version: String, host: String) -> String {
        artifactTemplate(host).replacingOccurrences(of: "{version}", with: version)
    }

    private static func probe(
        _ published: Set<String>, transient: Set<String> = [], host: String
    ) async throws -> ProbeOutcome {
        let registered = try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.deepseek.dsh" && $0.channel == .alpha
        })
        ArtifactServer.serve(feedURL(host).absoluteString, body: atom)
        for version in published {
            ArtifactServer.serve(artifactURL(version, host: host))
        }
        for version in transient {
            ArtifactServer.serve(artifactURL(version, host: host), status: 503)
        }
        let recipe = VendorProbeRecipe(
            bundleID: registered.bundleID,
            url: feedURL(host),
            mode: registered.mode,
            versionPattern: registered.versionPattern,
            selectHighest: true,
            selectsHighestPublishedBuild: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(artifactTemplate(host)), kind: .dmg),
            channel: .alpha)
        return await VendorProbeSource(recipes: [], session: ArtifactServer.session())
            .probeOutcome(recipe)
    }

    @Test func theVersionsHelperListsHighestFirstWithoutDuplicates() {
        // The atom repeats a release in its compare link; only the title is read
        // by the pattern, but a feed that named one release twice must not make
        // the walk ask about it twice.
        let body = """
            <entry><title>v0.2.2-alpha.2</title><x>v0.2.2-alpha.2</x></entry>\
            <entry><title>v0.2.2-alpha.4</title></entry>
            """
        let versions = VendorProbeRecipe.versions(
            in: body, pattern: #"<title>v([0-9]+(?:\.[0-9]+)+(?:-(?:alpha|rc)\.[0-9]+)?)</title>"#)
        #expect(versions == ["0.2.2-alpha.4", "0.2.2-alpha.2"])
    }

    /// The newest build is unpacked: offer the one below it, not a 404.
    @Test func anUnpackedNewestBuildIsSkippedForTheNewestPublishedOne() async throws {
        let outcome = try await Self.probe(["0.2.2-alpha.3"], host: "unpacked")
        #expect(outcome.failure == nil)
        #expect(outcome.remote?.displayVersion == "0.2.2-alpha.3")
        #expect(outcome.remote?.vendorInstallerKind == .dmg)
        #expect(outcome.remote?.downloadURL?.absoluteString == Self.artifactURL("0.2.2-alpha.3", host: "unpacked"))
        #expect(outcome.warnings.isEmpty)
    }

    /// The newest build IS packed: no walk, no warning.
    @Test func theNewestPublishedBuildIsOfferedWhenItIsTheHighest() async throws {
        let outcome = try await Self.probe(["0.2.2-alpha.4"], host: "packed")
        #expect(outcome.remote?.displayVersion == "0.2.2-alpha.4")
        #expect(outcome.remote?.vendorInstallerKind == .dmg)
        #expect(outcome.remote?.downloadURL?.absoluteString == Self.artifactURL("0.2.2-alpha.4", host: "packed"))
        #expect(outcome.warnings.isEmpty)
    }

    /// Nothing in the walk answers. The version still reads — the row can show
    /// what the vendor wrote — but no Update button points at a 404.
    @Test func noPublishedBuildAtAllLeavesDetectionAndDropsOneClick() async throws {
        let outcome = try await Self.probe([], host: "empty")
        #expect(outcome.failure == nil)
        #expect(outcome.remote?.displayVersion == "0.2.2-alpha.4")
        #expect(outcome.remote?.vendorInstallerKind == nil, "one-click must be off")
        #expect(outcome.warnings.contains { if case .installURLNotFound = $0 { true } else { false } },
                "expected installURLNotFound, got \(outcome.warnings)")
    }

    /// The bound: a vendor that has not packed its last four builds must not turn
    /// a periodic check into a crawl.
    @Test func theWalkStopsAtItsBound() async throws {
        let outcome = try await Self.probe(["0.2.2-alpha.2"], host: "bounded")
        // alpha.4, alpha.3, alpha.2 -- the third candidate is inside the bound.
        #expect(outcome.remote?.displayVersion == "0.2.2-alpha.2")
        #expect(VendorProbeSource.publishedWalkLimit == 3)
    }
}


extension DeepSeekHarnessPublishedBuildTests {

    /// A 5xx is an outage, not a verdict about that build. Stepping over it would
    /// offer an older build with no sign the newest went unchecked — so the walk
    /// stops, keeps the version it read, and turns one-click off for the round.
    @Test func aTransientHighestCandidateStopsTheWalk() async throws {
        let outcome = try await Self.probe(
            ["0.2.2-alpha.3"], transient: ["0.2.2-alpha.4"], host: "transient1")
        #expect(outcome.remote?.displayVersion == "0.2.2-alpha.4")
        #expect(outcome.remote?.vendorInstallerKind == nil, "one-click must be off for the round")
        #expect(outcome.warnings.contains { warning in
            if case .installURLTransient = warning { true } else { false }
        }, "expected installURLTransient, got \(outcome.warnings)")
    }

    /// The relabel this rule exists to prevent: with a 503 on the newest build and
    /// a miss on the older one, the round must report an OUTAGE. A walk that kept
    /// its last result would call it a deleted artifact and file against the
    /// recipe instead of the vendor.
    @Test func anOutageIsNotRelabelledByALaterMiss() async throws {
        let outcome = try await Self.probe(
            [], transient: ["0.2.2-alpha.4"], host: "transient2")
        #expect(outcome.remote?.displayVersion == "0.2.2-alpha.4")
        #expect(outcome.remote?.vendorInstallerKind == nil)
        #expect(outcome.warnings.contains { warning in
            if case .installURLTransient = warning { true } else { false }
        }, "expected installURLTransient, got \(outcome.warnings)")
        #expect(!outcome.warnings.contains { warning in
            if case .installURLNotFound = warning { true } else { false }
        }, "an outage must not be reported as a deleted artifact")
    }
}
