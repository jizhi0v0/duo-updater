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
        manifest: manifest, body: "version: 1.124.1\n", hasArchSibling: false)
    #expect(verdict == .adopt(manifest))
}

@Test func anArchSplitManifestIsNotThisMacsManifest() {
    // Notion publishes `latest-mac.yml` AND `arm64-mac.yml`, and its config names
    // neither — so which one this Mac wants is unanswered, and taking the default
    // could hand an arm64 Mac an Intel download (which is exactly what Typeless's
    // `latest-mac.yml` is).
    let manifest = URL(string: "https://desktop-release.notion-static.com/latest-mac.yml")!
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "7.31.3"),
        manifest: manifest, body: "version: 7.31.3\n", hasArchSibling: true)
    #expect(verdict == .review(.electronArchSplitManifest, manifest))
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
    #expect(FeedDiscovery.isArchSpecific(manifest))
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "2.4.0"),
        manifest: manifest, body: "version: 2.4.0\n", hasArchSibling: true)
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
        manifest: manifest, body: "version: 2.0.0\n", hasArchSibling: false)
    #expect(verdict == .review(.electronVersionMismatch, manifest))
}

@Test func anAddressThatDoesNotAnswerIsALeadNotAManifest() {
    let manifest = URL(string: "https://example.invalid/latest-mac.yml")!
    let verdict = FeedDiscovery.decideElectron(
        electronProbe(marketing: "1.0.0"),
        manifest: manifest, body: nil, hasArchSibling: false)
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
