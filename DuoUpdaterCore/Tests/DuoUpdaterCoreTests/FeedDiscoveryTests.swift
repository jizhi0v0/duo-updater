import Testing
import Foundation
@testable import DuoUpdaterCore

// The gates in `FeedDiscovery.decide` are the only thing standing between a
// discovered address and a silently wrong update verdict, so every case below is
// built from numbers MEASURED off a real bundle and its real feed on 2026-08-31
// — not from invented shapes. Where a case names an app, those two strings are
// what that app and that feed actually said on the day.

private func probe(
    id: String = "com.example.app",
    marketing: String?, build: String?,
    candidate: String? = "https://example.invalid/appcast.xml",
    declared: String? = nil,
    sparkle: Bool = true
) -> FeedDiscovery.BundleProbe {
    let candidates = candidate.map {
        [FeedDiscovery.Candidate(raw: $0, url: URL(string: $0)!, origin: .binaryStrings)]
    } ?? []
    return FeedDiscovery.BundleProbe(
        bundleID: id,
        installed: VersionSide(marketing: marketing, build: build),
        declaredFeed: declared.flatMap(URL.init(string:)),
        candidates: candidates,
        shipsSparkle: sparkle)
}

private func item(
    short: String?, version: String?, channel: String? = nil
) -> SparkleAppcastItem {
    SparkleAppcastItem(shortVersionString: short, version: version, channel: channel)
}

// MARK: - the adopt path

@Test func adoptsWhenBothVersionStringsAgreeAndTheFeedHasADefaultChannel() {
    // Docker Desktop 4.88.1: bundle `4.88.1`/`237512`, the feed's single item
    // `sparkle:shortVersionString 4.88.1` / `sparkle:version 237512`, untagged.
    let verdict = FeedDiscovery.decide(
        probe(marketing: "4.88.1", build: "237512"),
        feedItems: [item(short: "4.88.1", version: "237512")])
    #expect(verdict == .adopt(URL(string: "https://example.invalid/appcast.xml")!))
}

@Test func aBundleThatNamesItsOwnFeedIsNotAProposal() {
    // Bartender, ImageOptim and Vivaldi Snapshot all declare a `SUFeedURL` equal
    // to the address we had hand-written a recipe for; `SparkleAppcastSource`
    // already resolves them, so there is nothing here to add.
    let declared = "https://imageoptim.com/appcast.xml"
    let verdict = FeedDiscovery.decide(
        probe(marketing: "1.9.3", build: "1.9.3", declared: declared),
        feedItems: [item(short: "1.9.3", version: "1.9.3")])
    #expect(verdict == .declared(URL(string: declared)!))
}

/// The one declared feed that is NOT an answer. Before `SparkleFeedCatalog`
/// could supersede an address, `.declared` meant "the Info.plist names it and
/// `SparkleAppcastSource` already resolves this app" — two claims that moved
/// together. For a superseded bundle the first is true and the second is false,
/// and `decide` has to say so: reporting `.declared` here would tell the reader
/// the app is covered by the very address production refuses to use.
@Test func aBundleWhoseDeclaredFeedIsSupersededSaysSoRatherThanClaimingCoverage() throws {
    let entry = try #require(SparkleFeedCatalog.supersededFeeds["com.readdle.pdfexpert-mac"])
    let verdict = FeedDiscovery.decide(
        probe(id: "com.readdle.PDFExpert-Mac", marketing: "3.13.2", build: "1172",
              declared: entry.declared.absoluteString),
        feedItems: [item(short: "3.13.2", version: "1172")])
    #expect(verdict == .superseded(declared: entry.declared, live: entry.live))

    // And a bundle naming any other address is untouched — the case above is not
    // "this bundle id", it is "this address".
    let elsewhere = "https://downloads.pdfexpert.com/pem4/release/appcast.xml"
    #expect(FeedDiscovery.decide(
        probe(id: "com.readdle.PDFExpert-Mac", marketing: "3.13.2", build: "1172",
              declared: elsewhere),
        feedItems: [item(short: "3.13.2", version: "1172")])
        == .declared(URL(string: elsewhere)!))
}

// MARK: - the version-namespace gates

@Test func braveStyleChromiumPrefixedMarketingIsRefused() {
    // Brave Browser Beta 195.92, read off the real arm64 dmg: the bundle reports
    // `152.1.95.92` where its feed says `1.95.92.0`. Adopting compares 152
    // against 1 marketing-first and answers "up to date" forever.
    let verdict = FeedDiscovery.decide(
        probe(marketing: "152.1.95.92", build: "195.92"),
        feedItems: [item(short: "1.95.92.0", version: "195.92")])
    #expect(verdict == .review(.marketingNamespaceMismatch,
                               URL(string: "https://example.invalid/appcast.xml")!))
}

@Test func weChatStyleExtraComponentIsRefused() {
    // The same gate from the other side, and the reason it is an equality test
    // and not an ordering one: WeChat's bundle says `4.1.13`, its feed says
    // `4.1.13.11`, which compares as permanently NEWER — a phantom update that
    // never clears. (The hand-written recipe truncates to three components on
    // purpose; nothing generic would.)
    let verdict = FeedDiscovery.decide(
        probe(marketing: "4.1.13", build: "269579"),
        feedItems: [item(short: "4.1.13.11", version: "269579")])
    #expect(verdict == .review(.marketingNamespaceMismatch,
                               URL(string: "https://example.invalid/appcast.xml")!))
}

@Test func aFeedWithNoMarketingStringCannotProveAgreement() {
    // VLC: every item carries `sparkle:version` (`3.0.23`) and no
    // `sparkle:shortVersionString` at all. Build-to-build comparison happens to
    // be right for VLC, but nothing in the feed shows that, so it goes to a
    // person rather than being assumed.
    let verdict = FeedDiscovery.decide(
        probe(marketing: "3.0.23", build: "3.0.23"),
        feedItems: [item(short: nil, version: "3.0.23")])
    #expect(verdict == .review(.marketingUncomparable,
                               URL(string: "https://example.invalid/appcast.xml")!))
}

@Test func aFeedThatDoesNotKnowTheInstalledBuildIsNotThisAppsFeed() {
    let verdict = FeedDiscovery.decide(
        probe(marketing: "2.0.0", build: "200"),
        feedItems: [item(short: "1.0.0", version: "100")])
    #expect(verdict == .review(.installedBuildNotInFeed,
                               URL(string: "https://example.invalid/appcast.xml")!))
}

@Test func theBuildIsMatchedAcrossEveryItemNotJustTheFirst() {
    // Mirrors the two-pass rule `SparkleAppcastSource.channel(ofInstalled:in:)`
    // documents: a prerelease usually keeps the release's marketing string, so
    // stopping at the first item that looks close reads the wrong one.
    let verdict = FeedDiscovery.decide(
        probe(marketing: "1.6.0", build: "1083"),
        feedItems: [
            item(short: "1.6.0", version: "1090"),
            item(short: "1.6.0", version: "1083"),
        ])
    #expect(verdict == .adopt(URL(string: "https://example.invalid/appcast.xml")!))
}

@Test func equivalentBuildSpellingsStillIdentifyTheInstalledFeedItem() {
    let expected = FeedDiscovery.Verdict.adopt(
        URL(string: "https://example.invalid/appcast.xml")!)

    #expect(FeedDiscovery.decide(
        probe(marketing: "1.2.3", build: "1.2.3"),
        feedItems: [item(short: "1.2.3", version: "v1.2.3")]) == expected,
        "a conventional version prefix does not change build identity")

    #expect(FeedDiscovery.decide(
        probe(marketing: "1.0", build: "1.0"),
        feedItems: [item(short: "1.0", version: "1.0.0")]) == expected,
        "missing trailing zero components do not change build identity")
}

@Test func anExactBuildSpellingBeatsAnEarlierEquivalentSpelling() {
    let verdict = FeedDiscovery.decide(
        probe(marketing: "1.0", build: "1.0"),
        feedItems: [
            item(short: "unrelated", version: "1.0.0"),
            item(short: "1.0", version: "1.0"),
        ])

    #expect(verdict == .adopt(
        URL(string: "https://example.invalid/appcast.xml")!))
}

// MARK: - the channel gate

@Test func aFeedWhereEveryItemIsChannelTaggedWouldStarveAStableInstall() {
    // OrbStack's appcast: 3 `stable`, 3 `beta`, 1 `canary`, none untagged.
    // `allowedChannels` always permits the untagged channel and derives nothing
    // else for a stable user, so adopting this feed as-is matches zero items.
    let verdict = FeedDiscovery.decide(
        probe(marketing: "2.2.3", build: "20963"),
        feedItems: [
            item(short: "2.2.3", version: "20963", channel: "stable"),
            item(short: "2.2.3", version: "20963", channel: "beta"),
        ])
    #expect(verdict == .review(.everyItemChannelTagged,
                               URL(string: "https://example.invalid/appcast.xml")!))
}

@Test func oneUntaggedItemIsEnoughToClearTheChannelGate() {
    let verdict = FeedDiscovery.decide(
        probe(marketing: "2.2.3", build: "20963"),
        feedItems: [
            item(short: "2.2.3", version: "20963"),
            item(short: "2.3.0", version: "21000", channel: "beta"),
        ])
    #expect(verdict == .adopt(URL(string: "https://example.invalid/appcast.xml")!))
}

// MARK: - the channel gate, on a declared feed

/// No `ChannelBinding` case can match this id. Asserted in each test rather than
/// assumed: the day someone binds it, these stop measuring the "no binding" half.
private let unboundID = "com.duoupdater.test.zzfixture.unbound"
private let declaredFeed = "https://zzfixture.example.test/appcast.xml"

@Test func aDeclaredFeedWithNoDefaultChannelAndNoBindingIsNotCoverage() {
    // CodeEdit 0.3.6, 2026-09-12: bundle `0.3.6`/`47`; its declared feed's ONE
    // item is `0.3.6`/`47` tagged `dev`. The installed build IS in the feed — the
    // state a discovery run normally sees, and the only one in which the app
    // still resolves. Mutation: delete the declared-feed gate in `decide` →
    // `.declared`, red.
    #expect(!ChannelBinding.hasResolver(bundleID: unboundID))
    let verdict = FeedDiscovery.decide(
        probe(id: unboundID, marketing: "0.3.6", build: "47",
              candidate: nil, declared: declaredFeed),
        feedItems: [item(short: "0.3.6", version: "47", channel: "dev")])
    #expect(verdict == .declaredNeedsBinding(URL(string: declaredFeed)!))
}

@Test func aBoundAppsAllTaggedDeclaredFeedIsStillDeclared() throws {
    // Synthetic feed shape; the id is real because the branch under test is
    // "a binding exists". BetterDisplay is the route `NEEDS BINDING` points at —
    // a resolver naming the tags outright — and once one exists, repeating the
    // warning would make it permanent noise. Mutation: drop the `hasResolver`
    // clause → `.declaredNeedsBinding`, red.
    let id = BetterDisplayChannel.bundleID
    try #require(ChannelBinding.hasResolver(bundleID: id))
    let verdict = FeedDiscovery.decide(
        probe(id: id, marketing: "1.0", build: "1", candidate: nil, declared: declaredFeed),
        feedItems: [item(short: "1.0", version: "1", channel: "dev")])
    #expect(verdict == .declared(URL(string: declaredFeed)!))
}

@Test func oneUntaggedItemKeepsADeclaredFeedDeclared() {
    // Mutation: fire on "some item is tagged" instead of "no item is untagged"
    // → `.declaredNeedsBinding`, red.
    #expect(!ChannelBinding.hasResolver(bundleID: unboundID))
    let verdict = FeedDiscovery.decide(
        probe(id: unboundID, marketing: "2.2.3", build: "20963",
              candidate: nil, declared: declaredFeed),
        feedItems: [
            item(short: "2.2.3", version: "20963"),
            item(short: "2.3.0", version: "21000", channel: "beta"),
        ])
    #expect(verdict == .declared(URL(string: declaredFeed)!))
}

@Test func aDeclaredFeedThatDidNotAnswerIsNotReadAsAllTagged() {
    // "No untagged item" is vacuously true of zero items. Mutation: drop the
    // `!feedItems.isEmpty` guard → every offline run flags every declared app, red.
    #expect(!ChannelBinding.hasResolver(bundleID: unboundID))
    let verdict = FeedDiscovery.decide(
        probe(id: unboundID, marketing: "0.3.6", build: "47",
              candidate: nil, declared: declaredFeed),
        feedItems: [])
    #expect(verdict == .declared(URL(string: declaredFeed)!))
}

// MARK: - the address gates

@Test func aTemplatedLiteralIsNeverAnAddress() throws {
    // OrbStack's real literal. Note this must be judged on the RAW string:
    // `URL` escapes the `%s` to `%25s`, after which it no longer reads as a
    // template at all.
    let raw = "https://api-updates.orbstack.dev/%s/appcast.xml?bucket=%d"
    #expect(FeedDiscovery.isTemplated(raw))
    #expect(!FeedDiscovery.isTemplated(URL(string: raw)!.absoluteString))

    let verdict = FeedDiscovery.decide(
        probe(marketing: "2.2.3", build: "20963", candidate: raw),
        feedItems: [])
    #expect(verdict == .review(.templatedAddress, URL(string: raw)!))
}

@Test func aPartiallyAppliedTemplateIsAlsoRefused() {
    // The other half of OrbStack's string table: the scan stopped exactly where
    // the substituted bucket number would have gone.
    #expect(FeedDiscovery.isTemplated("https://api-updates.orbstack.dev/arm64/appcast.xml?bucket="))
    #expect(FeedDiscovery.isTemplated("https://updates.devmate.com/%@.xml"))
    #expect(!FeedDiscovery.isTemplated("https://imageoptim.com/appcast.xml"))
}

@Test func oneTemplatedFragmentDisqualifiesTheWholeBundle() {
    // Go binaries pack their strings with no terminator, so one templated address
    // shows up as several overrun fragments. Reporting that as "several
    // candidates, pick one" would invite adopting a fragment.
    let raws = [
        "https://api-updates.orbstack.dev/arm64/appcast.xml?bucket=",
        "https://api-updates.orbstack.dev/%s/appcast.xml?bucket=%dssh:",
    ]
    let candidates = raws.map {
        FeedDiscovery.Candidate(raw: $0, url: URL(string: $0)!, origin: .binaryStrings)
    }
    let p = FeedDiscovery.BundleProbe(
        bundleID: "dev.kdrag0n.MacVirt",
        installed: VersionSide(marketing: "2.2.3", build: "20963"),
        declaredFeed: nil, candidates: candidates, shipsSparkle: true)
    #expect(FeedDiscovery.decide(p, feedItems: []) == .review(.templatedAddress, candidates[0].url))
}

@Test func severalDistinctAddressesAreAJudgementNotAGuess() {
    // Measured on this machine: Ghostty ships `release` and `tip`, Tailscale
    // `stable`/`unstable`/`release-candidate`, VLC one feed per architecture.
    // Which one is right is a statement about the user's channel or hardware.
    let raws = [
        "https://update.videolan.org/vlc/sparkle/vlc-arm64.xml",
        "https://update.videolan.org/vlc/sparkle/vlc-intel64.xml",
    ]
    let candidates = raws.map {
        FeedDiscovery.Candidate(raw: $0, url: URL(string: $0)!, origin: .binaryStrings)
    }
    let p = FeedDiscovery.BundleProbe(
        bundleID: "org.videolan.vlc",
        installed: VersionSide(marketing: "3.0.23", build: "3.0.23"),
        declaredFeed: nil, candidates: candidates, shipsSparkle: true)
    #expect(FeedDiscovery.decide(p, feedItems: []) == .review(.ambiguousCandidates, nil))
}

@Test func aBundleWithNoRecognisedUpdaterIsNotACoverageGap() {
    // Docker Desktop publishes a valid Sparkle appcast but embeds no Sparkle —
    // its own updater reads it. "No candidate" there would report a hole that
    // isn't one.
    let verdict = FeedDiscovery.decide(
        probe(marketing: "4.88.1", build: "237512", candidate: nil, sparkle: false),
        feedItems: [])
    #expect(verdict == .noKnownUpdater)
}

// MARK: - literal extraction

@Test func onlyAppcastShapedLiteralsBecomeCandidates() {
    #expect(FeedDiscovery.looksLikeAppcast("https://example.com/appcast.xml"))
    #expect(FeedDiscovery.looksLikeAppcast("https://tableplus.com/osx/version.xml"))
    #expect(!FeedDiscovery.looksLikeAppcast("https://example.com/support"))
    // Chromium embeds these in every bundle it ships; without the exclusion every
    // Electron app reads as "ambiguous candidates".
    #expect(!FeedDiscovery.looksLikeAppcast("https://www.gstatic.com/cryptauthvault/v0/cert.xml"))
}

@Test func literalsAreCutAtTheFirstByteAUrlCannotHold() {
    let blob = Data("\0\0https://example.com/appcast.xml\0trailing".utf8)
    #expect(FeedDiscovery.httpsLiterals(in: blob) == ["https://example.com/appcast.xml"])
}

// MARK: - electron-builder

// `app-update.yml` bodies below are the real files out of the installed bundles
// on 2026-08-31, byte for byte — including Notion's single-quoted url, which is
// the only quoting electron-builder emits.

@Test func readsTheGenericProviderConfigurationElectronBuilderWrites() throws {
    let cfg = try #require(ElectronUpdateConfig.parse("""
        provider: generic
        url: 'https://desktop-release.notion-static.com'
        channel: latest
        updaterCacheDirName: notion-updater
        """))
    #expect(cfg.provider == "generic")
    #expect(cfg.url == "https://desktop-release.notion-static.com")
    #expect(cfg.channel == "latest")
    #expect(cfg.manifestURL
        == URL(string: "https://desktop-release.notion-static.com/latest-mac.yml"))
}

@Test func anAbsentChannelMeansLatest() throws {
    // Canva's config names no channel at all.
    let cfg = try #require(ElectronUpdateConfig.parse("""
        provider: generic
        url: https://desktop-release.canva.com
        useMultipleRangeRequest: false
        updaterCacheDirName: canva-updater
        """))
    #expect(cfg.channel == "latest")
    #expect(cfg.manifestURL == URL(string: "https://desktop-release.canva.com/latest-mac.yml"))
}

@Test func providersThatStateNoAddressYieldNoManifestURL() throws {
    // Termius (s3) and OpenCode (github). Termius is the reason this refuses to
    // construct one: its bucket does not resolve, while the address that answers
    // is a host the config never mentions.
    let s3 = try #require(ElectronUpdateConfig.parse("""
        provider: s3
        bucket: termius.desktop.autoupdate
        region: us-east-1
        endpoint: https://s3.amazonaws.com
        acl: private
        """))
    #expect(s3.manifestURL == nil)

    let github = try #require(ElectronUpdateConfig.parse("""
        owner: anomalyco
        repo: opencode
        provider: github
        channel: latest
        """))
    #expect(github.owner == "anomalyco")
    #expect(github.manifestURL == nil)
}

@Test func theManifestVersionIsTheTopLevelOneNotAnythingNestedUnderFiles() {
    // The shape that makes a line-oriented read safe: `url:` appears again inside
    // `files:`, indented, meaning something else entirely — so only a top-level
    // `version:` is read, and only the first one.
    let body = """
        version: 7.31.3
        files:
          - url: Notion-7.31.3.zip
            sha512: L6T9s98yf6==
            size: 126113061
        path: Notion-7.31.3.zip
        releaseDate: '2026-08-27T01:59:39.485Z'
        """
    #expect(ElectronManifest.parse(body)?.version == "7.31.3")
    #expect(ElectronManifest.parse("files:\n  - url: x.zip\n")?.version == nil)
}

@Test func adoptsAnElectronManifestThatNamesTheInstalledVersion() {
    // Canva 1.124.1 — and note the outcome this reproduces: the hand-written
    // recipe for Canva reads this exact address.
    let manifest = URL(string: "https://desktop-release.canva.com/latest-mac.yml")!
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "1.124.1"),
        manifest: manifest, body: "version: 1.124.1\n")
    #expect(verdict == .adopt(manifest))
}

@Test func anAdjacentManifestDoesNotChangeTheDeclaredTrack() {
    // Notion's `channel: latest` build reads this file even when the vendor also
    // publishes `arm64-mac.yml`. The adjacent file belongs to builds whose own
    // config says `channel: arm64`; its existence is not an architecture signal.
    let manifest = URL(string: "https://desktop-release.notion-static.com/latest-mac.yml")!
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "7.31.3"),
        manifest: manifest, body: "version: 7.31.3\n")
    #expect(verdict == .adopt(manifest))
}

@Test func aBundleThatNamesItsArchitectureHasAlreadyAnsweredTheArchQuestion() {
    // Typeless ships `channel: arm64`, so the manifest it resolves to IS the
    // arm64 one. Probing for an `arm64-mac.yml` sibling there compares the file
    // against itself, and reading that as a split blocks a bundle that told us
    // exactly what it wanted.
    let cfg = ElectronUpdateConfig.parse("""
        provider: generic
        channel: arm64
        url: https://typeless-static.com/desktop-release/
        """)
    let manifest = try! #require(cfg?.manifestURL)
    #expect(manifest
        == URL(string: "https://typeless-static.com/desktop-release/arm64-mac.yml"))
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "2.4.0"),
        manifest: manifest, body: "version: 2.4.0\n")
    #expect(verdict == .adopt(manifest))
}

@Test func anEmptyUrlIsNotAnAddress() {
    // QQ ships `provider: generic` with `url: ''`. An empty value must not become
    // a relative URL that then gets fetched against nothing.
    let cfg = ElectronUpdateConfig.parse("provider: generic\nurl: \'\'\n")
    #expect(cfg?.url == nil)
    #expect(cfg?.manifestURL == nil)
}

@Test func aManifestNamingAnotherVersionGoesToAPerson() {
    // Electron carries one version string, so this single test does what two
    // gates do on the Sparkle side. It also fires while an update is merely
    // pending — which is exactly why it is a review and not a rejection.
    let manifest = URL(string: "https://example.invalid/latest-mac.yml")!
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "1.0.0"),
        manifest: manifest, body: "version: 2.0.0\n")
    #expect(verdict == .review(.electronVersionMismatch, manifest))
}

@Test func anAddressThatDoesNotAnswerIsALeadNotAManifest() {
    let manifest = URL(string: "https://example.invalid/latest-mac.yml")!
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "1.0.0"),
        manifest: manifest, body: nil)
    #expect(verdict == .review(.electronManifestUnreachable, manifest))
}

@Test func sparkleWinsABundleThatSomehowCarriesBoth() {
    // The family choice is not cosmetic: it picks which set of gates runs. Sparkle
    // wins because it is the family a shipping source can resolve today.
    let both = FeedDiscovery.BundleProbe(
        bundleID: "com.example.app",
        installed: VersionSide(marketing: "1.0", build: "1"),
        declaredFeed: nil, candidates: [], shipsSparkle: true,
        electron: ElectronUpdateConfig(
            provider: "generic", url: "https://example.invalid",
            owner: nil, repo: nil, channel: "latest"))
    #expect(both.family == .sparkle)
}

private func electronProbe(marketing: String) -> FeedDiscovery.BundleProbe {
    FeedDiscovery.BundleProbe(
        bundleID: "com.example.app",
        installed: VersionSide(marketing: marketing, build: nil),
        declaredFeed: nil, candidates: [], shipsSparkle: false,
        electron: ElectronUpdateConfig(
            provider: "generic", url: "https://example.invalid",
            owner: nil, repo: nil, channel: "latest"))
}

/// A CDN that holds a stale edge copy of every address and only goes to origin for
/// a request that carries a query — Kimi's manifest host, 2026-09-11. Stateless,
/// so it is safe under the parallel runner.
private final class EdgeCopyProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let body = url.query == nil ? "version: 3.2.5\n" : "version: 3.2.7\n"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func discoveryReadsTheManifestPastACDNsEdgeCopy() async throws {
    // A bare fetch reads the 3.2.5 edge copy and reports `electronVersionMismatch`
    // against a 3.2.7 bundle whose own updater reads the manifest fine.
    let fm = FileManager.default
    let bundle = fm.temporaryDirectory
        .appendingPathComponent("ZZFixture-EdgeCopy-\(UUID().uuidString).app")
    defer { try? fm.removeItem(at: bundle) }
    let resources = bundle.appendingPathComponent("Contents/Resources")
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": "com.duoupdater.test.zzfixture.edgecopy",
        "CFBundleShortVersionString": "3.2.7",
        "CFBundleVersion": "3.2.7",
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
    try "provider: generic\nurl: https://kimi-img.example.test/app/upgrade/\n"
        .write(to: resources.appendingPathComponent("app-update.yml"),
               atomically: true, encoding: .utf8)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EdgeCopyProtocol.self]
    let finding = await FeedDiscovery.examine(
        bundleAt: bundle, session: URLSession(configuration: configuration))

    // Adopted, and against the bare address: the verdict names what a person would
    // propose, never the one-off query it was fetched with.
    #expect(finding.verdict
        == .adopt(URL(string: "https://kimi-img.example.test/app/upgrade/latest-mac.yml")!))
}

/// CodeEdit's declared feed as it read on 2026-09-12, trimmed to the fields the
/// gate reads: one item, tagged `dev`.
private final class DevOnlyFeedProtocol: URLProtocol, @unchecked Sendable {
    static let body = """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <title>CodeEdit</title>
            <item>
              <title>0.3.6</title>
              <sparkle:channel>dev</sparkle:channel>
              <sparkle:version>47</sparkle:version>
              <sparkle:shortVersionString>0.3.6</sparkle:shortVersionString>
              <enclosure url="https://zzfixture.example.test/CodeEdit.dmg" length="1" type="application/octet-stream"/>
            </item>
          </channel>
        </rss>
        """
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func discoveryFetchesADeclaredFeedToAskTheChannelQuestion() async throws {
    // The defect was not in `decide`: `examine` never fetched a declared feed, so
    // the declared branch only ever saw zero items and the `decide` tests above
    // could all pass while the tool still printed `declared` for CodeEdit.
    // Mutation: put back the `declaredFeed == nil` condition on the fetch →
    // `.declared`, red.
    #expect(!ChannelBinding.hasResolver(bundleID: unboundID))
    let fm = FileManager.default
    let bundle = fm.temporaryDirectory
        .appendingPathComponent("ZZFixture-DeclaredDevOnly-\(UUID().uuidString).app")
    defer { try? fm.removeItem(at: bundle) }
    let contents = bundle.appendingPathComponent("Contents")
    try fm.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": unboundID,
        "CFBundleShortVersionString": "0.3.6",
        "CFBundleVersion": "47",
        "SUFeedURL": declaredFeed,
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DevOnlyFeedProtocol.self]
    let finding = await FeedDiscovery.examine(
        bundleAt: bundle, session: URLSession(configuration: configuration))
    #expect(finding.verdict == .declaredNeedsBinding(URL(string: declaredFeed)!))
}
