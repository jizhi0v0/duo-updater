import Foundation
import Testing

@testable import DuoUpdaterCore

/// OpenChamber's `v2-preview` test builds, told apart from stable by the
/// `-preview.<N>` tail on their version — `ReleaseChannel.detect` step 4 — and
/// offered the stable release, as the build's own updater offers it.
///
/// The inputs are each package's own Info.plist values: the preview build and
/// stable share `dev.openchamber.desktop`, the name "OpenChamber" and the Team,
/// and `CFBundleShortVersionString` = `CFBundleVersion` on both
/// (`2.0.0-preview.8`; `2.1.0`, `2.1.1`).
@Suite(.serialized) struct OpenChamberChannelTests {

    private static let bundleID = "dev.openchamber.desktop"

    private func detect(_ version: String) -> ReleaseChannel {
        ReleaseChannel.detect(
            name: "OpenChamber", bundleID: Self.bundleID, keystoneChannel: nil,
            version: version, bundleFileName: "OpenChamber")
    }

    @Test func thePreviewBuildReadsAsPreview() {
        #expect(detect("2.0.0-preview.8") == .preview)
    }

    @Test func theStableBuildsStayStable() {
        #expect(detect("2.1.0") == .stable)
        #expect(detect("2.1.1") == .stable)
    }

    /// The rule is a version shape, not an OpenChamber rule, so the shapes next
    /// to it are what keep it from reading build metadata as a channel. The whole
    /// string has to end at the counter, and the word has to be exactly `preview`.
    @Test func lookAlikesStayStable() {
        for version in [
            "2.0.0-preview",            // no counter
            "2.0.0-preview.8+9fba129",  // build metadata after the counter
            "2.0.0-preview.8.1",        // more than one counter
            "2.0.0-preview.x",          // non-numeric counter
            "2.0.0-previews.8",         // a different word
            "2.0.0-preview8",           // counter not dot-separated
            "preview.8",                // no numeric prefix
            "2.0.0.preview.8",          // no dash before the word
        ] {
            #expect(ReleaseChannel.detect(
                name: "App", bundleID: nil, keystoneChannel: nil, version: version) == .stable,
                "\(version)")
        }
    }

    // MARK: what each copy is offered

    /// The two GitHub rules, as registered.
    private static var rules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    }

    private func rule(_ channel: ReleaseChannel) throws -> GitHubReleaseRule {
        try #require(Self.rules.first { $0.channel == channel })
    }

    private func source(_ rules: [GitHubReleaseRule] = OpenChamberChannelTests.rules)
        -> GitHubReleasesSource
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenChamberGitHubFixture.self]
        return GitHubReleasesSource(rules: rules, session: URLSession(configuration: configuration))
    }

    /// The copy as scanned: its channel from the production detector.
    private func app(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "OpenChamber", bundleID: Self.bundleID,
            shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/OpenChamber.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil,
            releaseChannel: detect(version))
    }

    @Test func theRegistryHasAStableAndAPreviewRule() {
        #expect(Self.rules.map(\.channel) == [.stable, .preview])
    }

    /// What the preview build's own updater does: the newest stable release,
    /// installable, read from `/releases/latest` and nothing else.
    @Test func aPreviewCopyIsOfferedTheStableRelease() async throws {
        OpenChamberGitHubFixture.reset(latestHasMacAsset: true)
        let remote = try #require(try await source().latestVersion(for: app("2.0.0-preview.8")))

        #expect(remote.displayVersion == "2.1.1")
        #expect(remote.releaseChannel == .preview)
        #expect(remote.vendorInstallerKind == .dmg)
        let url = try #require(remote.downloadURL?.absoluteString)
        #expect(url.contains("/releases/download/v2.1.1/OpenChamber-2.1.1-mac-"), "\(url)")
        #expect(OpenChamberGitHubFixture.paths() == ["/repos/openchamber/openchamber/releases/latest"])
        #expect(RecipeSanity.crossChannelArtifact(rule: try rule(.preview), remote: remote) == nil)

        // One-click, through the same GitHub branch a stable copy takes.
        #expect(remote.requiresManualInstaller == false)
        let result = UpdateResult(
            app: app("2.0.0-preview.8"), remote: remote,
            status: .updateAvailable(latest: "2.1.1"))
        #expect(UpdatePolicy.canAutoInstall(
            result,
            settings: UpdateSettings(
                appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning,
                declinedElevationKeys: []),
            environment: InstallEnvironment(
                isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:],
                elevationRequiredPaths: [], runningBundleIDs: [])))
    }

    /// The stable copy resolves through the stable rule exactly as with that
    /// rule alone: same answer, same one request.
    @Test func aStableCopyResolvesAsBefore() async throws {
        OpenChamberGitHubFixture.reset(latestHasMacAsset: true)
        let both = try #require(try await source().latestVersion(for: app("2.1.1")))
        let bothPaths = OpenChamberGitHubFixture.paths()

        OpenChamberGitHubFixture.reset(latestHasMacAsset: true)
        let alone = try #require(
            try await source([try rule(.stable)]).latestVersion(for: app("2.1.1")))

        #expect(both.releaseChannel == .stable)
        #expect(both.displayVersion == "2.1.1")
        #expect(both.displayVersion == alone.displayVersion)
        #expect(both.downloadURL == alone.downloadURL)
        #expect(both.vendorInstallerKind == alone.vendorInstallerKind)
        #expect(bothPaths == OpenChamberGitHubFixture.paths())
        #expect(bothPaths == ["/repos/openchamber/openchamber/releases/latest"])
    }

    /// The `v2-preview` prerelease is never offered, by either rule, even when
    /// the newest stable lacks its macOS asset and the source falls back to the
    /// whole list, where the prerelease sits on top.
    @Test func thePreviewPrereleaseIsNeverOffered() async throws {
        for version in ["2.0.0-preview.8", "2.1.1", "2.0.4"] {
            OpenChamberGitHubFixture.reset(latestHasMacAsset: false)
            let remote = try #require(try await source().latestVersion(for: app(version)))
            #expect(remote.displayVersion == "2.1.0", "\(version)")
            let url = remote.downloadURL?.absoluteString ?? ""
            #expect(url.contains("/download/v2.1.0/"), "\(version): \(url)")
            #expect(OpenChamberGitHubFixture.paths()
                .contains("/repos/openchamber/openchamber/releases"), "\(version)")
        }
        // Each field on its own refuses the prerelease, on both rules.
        for rule in Self.rules {
            #expect(!rule.usePrereleases)
            #expect(VendorProbeRecipe.extractVersion(
                from: "v2-preview", pattern: rule.versionPattern) == nil)
            #expect(VendorProbeRecipe.extractVersion(
                from: "v2.0.0-preview.8", pattern: rule.versionPattern) == nil)
            let pattern = try #require(rule.installAssetPattern)
            for name in ["OpenChamber-2.0.0-preview.8-mac-arm64.dmg",
                         "OpenChamber-2.0.0-preview.8-mac-x64.dmg"] {
                #expect(name.range(of: pattern, options: .regularExpression) == nil, "\(name)")
            }
        }
    }

    /// The proof is green on the rule as registered and fails on each way of
    /// letting the prerelease in.
    @Test func thePreviewProofFailsWhenTheRuleCanTakeThePrerelease() throws {
        let preview = try rule(.preview)
        let remote = RemoteVersion(
            shortVersion: "2.1.1", version: nil,
            downloadURL: URL(string:
                "https://github.com/openchamber/openchamber/releases/download/v2.1.1/OpenChamber-2.1.1-mac-arm64.dmg"),
            sourceName: "GitHub", vendorInstallerKind: .dmg, releaseChannel: .preview)
        #expect(RecipeSanity.crossChannelArtifact(rule: preview, remote: remote) == nil)

        func loosened(
            usePrereleases: Bool = false,
            versionPattern: String? = nil,
            installAssetPattern: String? = nil
        ) -> GitHubReleaseRule {
            GitHubReleaseRule(
                bundleID: preview.bundleID, owner: "openchamber", repo: "openchamber",
                usePrereleases: usePrereleases,
                versionPattern: versionPattern ?? preview.versionPattern,
                installAssetPattern: installAssetPattern ?? preview.installAssetPattern,
                installerKind: .dmg,
                channel: .preview)
        }
        for broken in [
            loosened(usePrereleases: true),
            loosened(versionPattern: #"^v([0-9]+(?:\.[0-9]+)+(?:-preview\.[0-9]+)?)$"#),
            loosened(versionPattern: #"^v(.+)$"#),
            loosened(installAssetPattern: #"^OpenChamber-.+-mac-(?:arm64|x64)\.dmg$"#),
        ] {
            #expect(RecipeSanity.crossChannelArtifact(rule: broken, remote: remote) != nil,
                    "\(broken.usePrereleases) \(broken.versionPattern) \(broken.installAssetPattern ?? "")")
        }
    }
}

/// Serves the shape of the real repository: `/releases/latest` is v2.1.1, and
/// the list holds the `v2-preview` prerelease (assets `2.0.0-preview.8`) above
/// the stable releases. `latestHasMacAsset: false` strips v2.1.1's macOS dmgs,
/// which sends the source to the list.
private final class OpenChamberGitHubFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requested: [String] = []
    nonisolated(unsafe) private static var latestHasMacAsset = true

    static func reset(latestHasMacAsset: Bool) {
        lock.withLock {
            requested = []
            Self.latestHasMacAsset = latestHasMacAsset
        }
    }

    static func paths() -> [String] { lock.withLock { requested } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let withMac = Self.lock.withLock { () -> Bool in
            Self.requested.append(path)
            return Self.latestHasMacAsset
        }
        let latest = Self.release(tag: "v2.1.1", version: "2.1.1", prerelease: false, mac: withMac)
        let status: Int
        let body: String
        switch path {
        case "/repos/openchamber/openchamber/releases/latest":
            status = 200
            body = latest
        case "/repos/openchamber/openchamber/releases":
            status = 200
            body = "[" + [
                Self.release(tag: "v2-preview", version: "2.0.0-preview.8", prerelease: true),
                latest,
                Self.release(tag: "v2.1.0", version: "2.1.0", prerelease: false),
                Self.release(tag: "v2.0.4", version: "2.0.4", prerelease: false),
            ].joined(separator: ",") + "]"
        default:
            status = 404
            body = #"{"message":"Not Found"}"#
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func release(
        tag: String, version: String, prerelease: Bool, mac: Bool = true
    ) -> String {
        let base = "https://github.com/openchamber/openchamber/releases/download/\(tag)/"
        var names = [
            "OpenChamber-\(version)-win-x64.exe", "OpenChamber-\(version)-linux-x86_64.AppImage",
        ]
        if mac {
            names += ["OpenChamber-\(version)-mac-arm64.dmg", "OpenChamber-\(version)-mac-x64.dmg"]
        }
        let assets = names.map { name in
            "{\"name\":\"\(name)\",\"browser_download_url\":\"\(base)\(name)\",\"size\":254975125}"
        }.joined(separator: ",")
        return """
        {
          "tag_name":"\(tag)",
          "prerelease":\(prerelease),
          "draft":false,
          "published_at":"2026-10-01T00:00:00Z",
          "html_url":"https://github.com/openchamber/openchamber/releases/tag/\(tag)",
          "body":"* notes",
          "assets":[\(assets)]
        }
        """
    }
}
