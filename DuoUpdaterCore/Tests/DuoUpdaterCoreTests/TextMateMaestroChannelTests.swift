import Foundation
import Testing
@testable import DuoUpdaterCore

/// A GitHub list per repo, served from `ReleaseListStub.releases`, newest
/// first; `/releases/latest` is the first non-prerelease, `/releases/tags/<t>`
/// that release. Keyed by repo, because the two suites below run in parallel.
private final class ReleaseListStub: URLProtocol, @unchecked Sendable {
    struct Release { let tag: String; let prerelease: Bool; let assets: [String] }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lists: [String: [Release]] = [:]
    static func set(_ releases: [Release], for repo: String) {
        lock.lock(); defer { lock.unlock() }
        lists[repo] = releases
    }
    static func list(_ repo: String) -> [Release] {
        lock.lock(); defer { lock.unlock() }
        return lists[repo] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func json(_ r: Release, repo: String) -> String {
        let assets = r.assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/\#(repo)/releases/download/\#(r.tag)/\#($0)","size":1000}"#
        }
        return """
        {"tag_name":"\(r.tag)","draft":false,"prerelease":\(r.prerelease),\
        "published_at":"2026-10-21T00:00:00Z",\
        "html_url":"https://github.com/\(repo)/releases/tag/\(r.tag)",\
        "body":"- Notes for \(r.tag)","assets":[\(assets.joined(separator: ","))]}
        """
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let parts = path.split(separator: "/").map(String.init)  // repos, owner, repo, releases, …
        let repo = parts.count >= 3 ? "\(parts[1])/\(parts[2])" : ""
        let releases = Self.list(repo)
        let base = "/repos/\(repo)/releases"
        var status = 200
        var body = #"{"message":"Not Found"}"#
        if path == base + "/latest", let r = releases.first(where: { !$0.prerelease }) {
            body = Self.json(r, repo: repo)
        } else if path == base {
            body = "[" + releases.map { Self.json($0, repo: repo) }.joined(separator: ",") + "]"
        } else if path.hasPrefix(base + "/tags/"),
                  let r = releases.first(where: { base + "/tags/" + $0.tag == path }) {
            body = Self.json(r, repo: repo)
        } else {
            status = 404
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func offer(
    bundleID: String, name: String, repo: String, version: String, channel: ReleaseChannel,
    releases: [ReleaseListStub.Release]
) async throws -> RemoteVersion? {
    ReleaseListStub.set(releases, for: repo)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ReleaseListStub.self]
    let source = GitHubReleasesSource(
        rules: GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID },
        session: URLSession(configuration: config))
    let app = InstalledApp(
        name: name, bundleID: bundleID, shortVersion: version, buildVersion: version,
        path: URL(fileURLWithPath: "/Applications/ZZFixture-\(name).app"),
        isMASApp: false, sparkleFeedURL: nil,
        releaseChannel: channel, channelIsAuthoritative: true)
    return try await source.latestVersion(for: app)
}

/// The proof holds on the beta rule as written and fails when any one of the
/// named fields takes the stable rule's value.
private func expectProofAnchorsEachField(_ bundleID: String) throws {
    let proof = try #require(ChannelProofRegistry.githubProofs[ChannelProofKey(bundleID, .beta)])
    guard case .recipeAnchor(let pattern, let fields) = proof else {
        Issue.record("expected a recipe anchor"); return
    }
    let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    let beta = try #require(rules.first { $0.channel == .beta })
    let stable = try #require(rules.first { $0.channel == .stable })
    func failure(
        usePrereleases: Bool, versionPattern: String, candidateScope: GitHubCandidateScope
    ) -> String? {
        RecipeSanity.recipeAnchorFailure(
            pattern: pattern, fields: fields, channel: .beta,
            subject: GitHubReleaseRule(
                bundleID: beta.bundleID, owner: beta.owner, repo: beta.repo,
                usePrereleases: usePrereleases, versionPattern: versionPattern,
                candidateScope: candidateScope,
                installAssetPattern: beta.installAssetPattern, installerKind: beta.installerKind,
                channel: .beta))
    }
    let scope = beta.candidateScope
    #expect(failure(usePrereleases: true, versionPattern: beta.versionPattern, candidateScope: scope) == nil)
    #expect(failure(usePrereleases: false, versionPattern: beta.versionPattern, candidateScope: scope) != nil)
    if fields.contains("versionPattern") {
        #expect(failure(usePrereleases: true, versionPattern: stable.versionPattern, candidateScope: scope) != nil)
    }
    if fields.contains("candidateScope") {
        #expect(failure(usePrereleases: true, versionPattern: beta.versionPattern, candidateScope: .newest) != nil)
    }
}

// MARK: - TextMate

/// `TextMateChannel`: `SoftwareUpdateChannel` picks the rule; the beta rule
/// offers the newest release of either kind. The list's top is real
/// (`textmate/textmate`, 2026-11-11: v2.0.23 stable over the v2.0.20–22
/// prereleases, v2.0.13 a prerelease with no asset); `v2.0.24` is made up.
@Suite(.serialized) struct TextMateChannelTests {
    private static let id = TextMateChannel.bundleID
    private static func r(_ v: String, pre: Bool, asset: Bool = true) -> ReleaseListStub.Release {
        .init(tag: "v\(v)", prerelease: pre, assets: asset ? ["TextMate_\(v).tbz"] : [])
    }
    private static let today = [
        r("2.0.23", pre: false), r("2.0.22", pre: true), r("2.0.21", pre: true), r("2.0.20", pre: true),
    ]

    @Test func onlyBetaOptsIn() {
        #expect(TextMateChannel.resolve(channelPref: "beta").channel == .beta)
        #expect(TextMateChannel.resolve(channelPref: "release").channel == .stable)
        #expect(TextMateChannel.resolve(channelPref: nil).channel == .stable)
        #expect(TextMateChannel.resolve(channelPref: "nightly").channel == .stable)
        #expect(TextMateChannel.resolve(channelPref: "Beta").channel == .stable)
        #expect(ChannelBinding.hasResolver(bundleID: Self.id))
        #expect(ChannelBinding.boundBundleIDs.contains(Self.id.lowercased()))
    }

    /// Today both tracks answer 2.0.23, as the vendor's own endpoints do.
    @Test func todayBothTracksAnswerTheSameRelease() async throws {
        let beta = try #require(try await offer(
            bundleID: Self.id, name: "TextMate", repo: "textmate/textmate",
            version: "2.0.22", channel: .beta, releases: Self.today))
        #expect(beta.shortVersion == "2.0.23")
        #expect(beta.vendorInstallerKind == .tarGz)
        let stable = try #require(try await offer(
            bundleID: Self.id, name: "TextMate", repo: "textmate/textmate",
            version: "2.0.22", channel: .stable, releases: Self.today))
        #expect(stable.shortVersion == "2.0.23")
    }

    /// A newer prerelease reaches a beta copy and never a release copy; one
    /// with no asset is walked past.
    @Test func aNewerPrereleaseReachesOnlyTheBetaTrack() async throws {
        let list = [Self.r("2.0.25", pre: true, asset: false), Self.r("2.0.24", pre: true)] + Self.today
        let beta = try #require(try await offer(
            bundleID: Self.id, name: "TextMate", repo: "textmate/textmate",
            version: "2.0.23", channel: .beta, releases: list))
        #expect(beta.shortVersion == "2.0.24")
        #expect(beta.downloadURL?.lastPathComponent == "TextMate_2.0.24.tbz")
        let stable = try #require(try await offer(
            bundleID: Self.id, name: "TextMate", repo: "textmate/textmate",
            version: "2.0.23", channel: .stable, releases: list))
        #expect(stable.shortVersion == "2.0.23")
    }

    @Test func theProofAnchorsTheListRead() throws {
        try expectProofAnchorsEachField(Self.id)
    }
}

// MARK: - Maestro

/// `MaestroChannel`: `enableBetaUpdates` in `maestro-settings.json` picks the
/// rule; the RC rule offers the highest version of either kind, as the app's
/// own check does (it sorts by version). The list is real (`RunMaestro/Maestro`,
/// 2026-11-11: v1.1.0-RC published between v1.0.0 and v1.0.1).
@Suite(.serialized) struct MaestroChannelTests {
    private static let id = MaestroChannel.bundleID
    private static func r(_ v: String, pre: Bool) -> ReleaseListStub.Release {
        .init(tag: "v\(v)", prerelease: pre, assets: [
            "maestro-\(v)-arm64-mac.zip", "maestro-\(v)-x64-mac.zip", "maestro-\(v)-arm64-mac.dmg",
        ])
    }
    private static let today = [
        r("1.0.2", pre: false), r("1.0.1", pre: false), r("1.1.0-RC", pre: true), r("1.0.0", pre: false),
    ]

    private func resolve(_ json: String?) -> ReleaseChannel {
        MaestroChannel.resolve(settings: json.map { Data($0.utf8) }).channel
    }

    /// The real file had 81 keys; these are the two values its toggle wrote.
    @Test func onlyJSONTrueOptsIn() {
        #expect(resolve(#"{"updatesPromptSeen":false,"enableBetaUpdates":true}"#) == .beta)
        #expect(resolve(#"{"updatesPromptSeen":false,"enableBetaUpdates":false}"#) == .stable)
        #expect(resolve("{}") == .stable)
        #expect(resolve(nil) == .stable)
        #expect(resolve(#"{"enableBetaUpdates":1}"#) == .stable)
        #expect(resolve(#"{"enableBetaUpdates":"true"}"#) == .stable)
        #expect(resolve("[true]") == .stable)
        #expect(ChannelBinding.hasResolver(bundleID: Self.id))
        #expect(ChannelBinding.boundBundleIDs.contains(Self.id.lowercased()))
    }

    @Test func aCustomSyncPathMovesTheSettingsFile() {
        let userData = URL(fileURLWithPath: "/Users/u/Library/Application Support/maestro", isDirectory: true)
        func at(_ bootstrap: String?) -> String? {
            MaestroChannel.settingsFileURL(userData: userData, bootstrap: bootstrap.map { Data($0.utf8) })?.path
        }
        #expect(at(nil) == "/Users/u/Library/Application Support/maestro/maestro-settings.json")
        #expect(at("{}") == "/Users/u/Library/Application Support/maestro/maestro-settings.json")
        #expect(at(#"{"customSyncPath":""}"#) == "/Users/u/Library/Application Support/maestro/maestro-settings.json")
        #expect(at(#"{"customSyncPath":"/Users/u/Dropbox/Maestro"}"#) == "/Users/u/Dropbox/Maestro/maestro-settings.json")
        // Relative: no answer, so stable.
        #expect(at(#"{"customSyncPath":"Dropbox/Maestro"}"#) == nil)
        #expect(MaestroChannel.userDataDirectoryURL.path.hasSuffix("/Library/Application Support/maestro"))
    }

    @Test func anRCSitsBetweenItsNeighbours() {
        #expect(VersionComparator.isNewer("1.1.0-RC", than: "1.0.2"))
        #expect(VersionComparator.isNewer("1.1.0", than: "1.1.0-RC"))
    }

    /// The app sorts by version and offers the first, so an RC-on copy on
    /// 1.0.2 is offered 1.1.0-RC although 1.0.2 was published after it.
    /// Mutation: `.newest` → 1.0.2, "up to date".
    @Test func anRCOnCopyIsOfferedTheHighestVersionNotTheFirstRow() async throws {
        for installed in ["1.0.0", "1.0.1", "1.0.2"] {
            let remote = try #require(try await offer(
                bundleID: Self.id, name: "Maestro", repo: "RunMaestro/Maestro",
                version: installed, channel: .beta, releases: Self.today))
            #expect(remote.shortVersion == "1.1.0-RC", "\(installed)")
            #expect(remote.downloadURL?.lastPathComponent == "maestro-1.1.0-RC-arm64-mac.zip")
            #expect(remote.vendorInstallerKind == .zip)
        }
        // RCs off: the stable rule, which never sees the RC.
        let stable = try #require(try await offer(
            bundleID: Self.id, name: "Maestro", repo: "RunMaestro/Maestro",
            version: "1.0.1", channel: .stable, releases: Self.today))
        #expect(stable.shortVersion == "1.0.2")
    }

    /// An RC copy is up to date on its own RC, and is offered the final release
    /// once it ships.
    @Test func anRCCopyIsOfferedItsFinalRelease() async throws {
        let rc = try #require(try await offer(
            bundleID: Self.id, name: "Maestro", repo: "RunMaestro/Maestro",
            version: "1.1.0-RC", channel: .beta, releases: Self.today))
        #expect(rc.shortVersion == "1.1.0-RC")
        let final = try #require(try await offer(
            bundleID: Self.id, name: "Maestro", repo: "RunMaestro/Maestro",
            version: "1.1.0-RC", channel: .beta, releases: [Self.r("1.1.0", pre: false)] + Self.today))
        #expect(final.shortVersion == "1.1.0")
    }

    /// `v0.16.16-RC` carries a stray stable zip beside its RC zip; the offer
    /// is read off the file the install takes, so the two agree.
    @Test func theOfferNamesTheFileThatInstalls() async throws {
        let stray = ReleaseListStub.Release(tag: "v0.16.16-RC", prerelease: true, assets: [
            "maestro-0.16.16-arm64-mac.zip", "maestro-0.16.16-RC-arm64-mac.zip",
            "maestro-0.16.16-RC-x64-mac.zip", "maestro-0.16.16-x64-mac.zip",
        ])
        let remote = try #require(try await offer(
            bundleID: Self.id, name: "Maestro", repo: "RunMaestro/Maestro",
            version: "0.16.15-RC", channel: .beta, releases: [stray]))
        let file = try #require(remote.downloadURL?.lastPathComponent)
        #expect(file == "maestro-\(remote.shortVersion ?? "")-arm64-mac.zip")
    }

    @Test func theHighestVersionSortKeepsListOrderForTies() {
        func rel(_ tag: String) -> GitHubReleasesSource.Release {
            GitHubReleasesSource.Release(
                tag: tag, body: nil, htmlURL: nil, publishedAt: nil, assets: [],
                isPrerelease: false, isDraft: false, hasExplicitReleaseState: true)
        }
        let sorted = GitHubReleasesSource.byVersionDescending(
            [rel("v1.0.2"), rel("nightly"), rel("v1.1.0-RC"), rel("v1.0.0"), rel("edge")],
            pattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-(?:RC|rc))?)$"#)
        #expect(sorted.map(\.tag) == ["v1.1.0-RC", "v1.0.2", "v1.0.0", "nightly", "edge"])
    }

    @Test func theProofAnchorsEveryPartOfTheRequest() throws {
        try expectProofAnchorsEachField(Self.id)
    }
}
