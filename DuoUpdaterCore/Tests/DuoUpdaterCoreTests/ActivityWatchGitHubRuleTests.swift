import Foundation
import Testing

@testable import DuoUpdaterCore

/// ActivityWatch ships two products in every release under ONE bundle id, one
/// version and one Team: the classic Python/Qt app (what the Homebrew cask
/// installs) and the experimental Tauri rewrite. The classic rule is unmarked and
/// installs `activitywatch-v….dmg`; the marked rule answers Tauri copies
/// (executable `aw-tauri`, the only local difference) and is detection-only.
@Suite struct ActivityWatchGitHubRuleTests {
    private static let id = "net.activitywatch.ActivityWatch"
    private static let tauriMarker = "tauri"

    private static var registryRules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == id }
    }

    private func source() -> GitHubReleasesSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return GitHubReleasesSource(
            rules: Self.registryRules, session: URLSession(configuration: config))
    }

    /// A fixture bundle whose main executable holds `literal` (or no executable
    /// at all when nil), as the real bundles hold their own runtime names.
    private func copy(_ version: String, literal: String?) throws -> InstalledApp {
        let bundle = TestScratch.directory("activitywatch-edition")
            .appendingPathComponent("ActivityWatch.app")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": "aw-fixture",
                               "CFBundleIdentifier": Self.id,
                               "CFBundleShortVersionString": version],
            format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        if let literal {
            try (Data(repeating: 0xAB, count: 4096)
                 + Data(literal.utf8)
                 + Data(repeating: 0xCD, count: 4096))
                .write(to: macOS.appendingPathComponent("aw-fixture"))
        }
        return InstalledApp(
            name: "ActivityWatch", bundleID: Self.id, shortVersion: version,
            buildVersion: version, path: bundle, isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// Two rules, one of them marked; the marked one has no install spec.
    @Test func twoEditionsOneBundleID() {
        let rules = Self.registryRules
        #expect(rules.count == 2)
        #expect(rules.filter { $0.installedExecutableMarker == nil }.count == 1)
        let marked = rules.filter { $0.installedExecutableMarker == Self.tauriMarker }
        #expect(marked.count == 1)
        #expect(marked.first?.installAssetPattern == nil)
        #expect(marked.first?.variant == "tauri")
    }

    /// Mutation: drop the marker from the Tauri rule → the Tauri fixture selects
    /// the classic rule and gets a classic dmg, red.
    @Test func eachCopySelectsItsEditionsRule() async throws {
        let tauri = try copy("0.14.1", literal: "https://activitywatch.net/tauri-fixture")
        let classic = try copy("0.14.1", literal: "https://activitywatch.net/classic-fixture")
        let tauriRule = try #require(try await GitHubReleasesSource.rule(
            forEditionOf: tauri, among: Self.registryRules))
        let classicRule = try #require(try await GitHubReleasesSource.rule(
            forEditionOf: classic, among: Self.registryRules))
        #expect(tauriRule.installedExecutableMarker == Self.tauriMarker)
        #expect(classicRule.installedExecutableMarker == nil)
        #expect(tauriRule.installAssetPattern == nil)
        #expect(classicRule.installAssetPattern != nil)
    }

    /// The classic copy is offered the classic dmg; the Tauri copy is offered the
    /// version (detection) but no one-click, because its own rule carries no
    /// install spec. No gate guards the classic package: the classic plist says
    /// `CFBundleExecutable = MacOS/aw-qt`, so an executable-marker gate fails
    /// closed on it and the classic copy would lose its one-click (measured in
    /// the VM as route `manual`).
    @Test func theClassicPackageIsNeverOfferedToATauriCopy() async throws {
        let classic = try copy("0.14.0", literal: "classic")
        let tauri = try copy("0.14.0", literal: "tauri")
        let classicRemote = try #require(try await source().latestVersion(for: classic))
        let tauriRemote = try #require(try await source().latestVersion(for: tauri))
        #expect(classicRemote.shortVersion == "0.14.1")
        #expect(classicRemote.downloadURL?.lastPathComponent
                == "activitywatch-v0.14.1-macos-arm64.dmg")
        #expect(Self.canAutoInstall(classic, classicRemote))
        #expect(tauriRemote.shortVersion == "0.14.1")
        #expect(tauriRemote.vendorInstallerKind == nil)
        #expect(!Self.canAutoInstall(tauri, tauriRemote))
    }

    /// The prerelease tags are `0.14.0b8` — the `b<N>` line no stable tag has —
    /// so the anchored pattern never offers one. Mutation: loosen the pattern to
    /// `^v([0-9]+...)` unanchored → it reads 0.14.0 out of the tag.
    @Test func theBSuffixIsNotAVersion() throws {
        let pattern = try #require(Self.registryRules.first?.versionPattern)
        #expect(VendorProbeRecipe.extractVersion(from: "v0.14.0b8", pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v0.14.1", pattern: pattern) == "0.14.1")
    }

    private static func canAutoInstall(_ app: InstalledApp, _ remote: RemoteVersion?) -> Bool {
        let result = UpdateResult(
            app: app, remote: remote,
            status: .updateAvailable(latest: remote?.shortVersion ?? "?"))
        return UpdatePolicy.canAutoInstall(
            result,
            settings: UpdateSettings(appStoreUpdateStrategy: .full,
                                     vendorInstallPolicy: .deferWhenRunning),
            environment: InstallEnvironment(
                isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:]))
    }

    /// `/releases/latest` answers v0.14.1 with both editions' arm64 dmgs (and the
    /// Intel ones), as the real release does.
    final class Stub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let base = "https://example.invalid/activitywatch/releases/download/v0.14.1/"
            let assets = [
                "activitywatch-v0.14.1-macos-arm64.dmg",
                "activitywatch-v0.14.1-macos-x86_64.dmg",
                "activitywatch-tauri-v0.14.1-macos-arm64.dmg",
                "activitywatch-tauri-v0.14.1-macos-x86_64.dmg",
            ].map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v0.14.1","name":"v0.14.1","draft":false,"prerelease":false,\
            "published_at":"2026-10-10T19:18:45Z",\
            "html_url":"https://example.invalid/activitywatch/releases/tag/v0.14.1",\
            "body":"notes","assets":[\(assets.joined(separator: ","))]}
            """
            let body = request.url?.absoluteString.contains("/releases/latest") == true
                ? release : "[\(release)]"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
