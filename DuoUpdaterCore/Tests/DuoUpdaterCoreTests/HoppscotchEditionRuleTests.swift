import Foundation
import Testing

@testable import DuoUpdaterCore

/// Hoppscotch's two editions under one id (`Recipes/io-hoppscotch-desktop.swift`):
/// the SelfHost rule answers for a copy whose executable names the SelfHost
/// feed, the Cloud rule for every other copy, and each copy's one-click takes
/// its own edition's dmg only.
///
/// The releases replay `v26.6.1-0`, which shipped SelfHost assets only, as
/// `/releases/latest`, over a release with both editions.
@Suite struct HoppscotchEditionRuleTests {
    static let id = "io.hoppscotch.desktop"
    static let cloudFeed = "hoppscotch-cloud-desktop.json"
    static let selfHostFeed = "hoppscotch-selfhost-desktop.json"

    /// Newest first, as `(tag, assetNames)`.
    static let releases: [(String, [String])] = [
        ("v26.6.1-0", [
            "Hoppscotch_SelfHost_mac_aarch64.dmg", "Hoppscotch_SelfHost_mac_x64.dmg",
            "Hoppscotch_SelfHost_mac_aarch64.tar.gz"]),
        ("v26.6.0-0", [
            "Hoppscotch_mac_aarch64.dmg", "Hoppscotch_mac_x64.dmg",
            "Hoppscotch_SelfHost_mac_aarch64.dmg", "Hoppscotch_SelfHost_mac_x64.dmg",
            "Hoppscotch_mac_aarch64.tar.gz"]),
    ]

    final class StubReleases: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            let all = HoppscotchEditionRuleTests.releases
            if url.contains("/releases/latest") {
                respond(Data("{\(Self.fields(all[0]))}".utf8))
                return
            }
            let perPage = URLComponents(string: url)?.queryItems?
                .first { $0.name == "per_page" }?.value.flatMap(Int.init) ?? all.count
            let page = all.prefix(perPage).map { "{\(Self.fields($0))}" }
            respond(Data("[\(page.joined(separator: ","))]".utf8))
        }

        private static func fields(_ release: (String, [String])) -> String {
            let assets = release.1.map {
                """
                {"name":"\($0)","browser_download_url":\
                "https://example.invalid/hoppscotch/releases/download/\(release.0)/\($0)",\
                "size":1000}
                """
            }
            return """
            "tag_name":"\(release.0)","name":"\(release.0)","draft":false,\
            "prerelease":false,"published_at":"2026-07-15T00:00:00Z",\
            "html_url":"https://example.invalid/hoppscotch/releases/tag/\(release.0)",\
            "body":"notes","assets":[\(assets.joined(separator: ","))]
            """
        }

        private func respond(_ data: Data) {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static var registryRules: [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == id }
    }

    private func source(_ rules: [GitHubReleaseRule] = registryRules) -> GitHubReleasesSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleases.self]
        return GitHubReleasesSource(rules: rules, session: URLSession(configuration: config))
    }

    /// A made-up bundle whose executable holds `literal` between filler, as the
    /// real ones hold their feed URL; no executable at all when nil.
    private func copy(_ version: String, literal: String?) throws -> InstalledApp {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoppscotch-edition-\(UUID().uuidString)/Hoppscotch.app")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": "hoppscotch-desktop",
                               "CFBundleIdentifier": Self.id,
                               "CFBundleShortVersionString": version],
            format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        if let literal {
            try (Data(repeating: 0xAB, count: 4096)
                 + Data("https://releases.example.invalid/\(literal)".utf8)
                 + Data(repeating: 0xCD, count: 4096))
                .write(to: macOS.appendingPathComponent("hoppscotch-desktop"))
        }
        return InstalledApp(
            name: "Hoppscotch", bundleID: Self.id, shortVersion: version, buildVersion: version,
            path: bundle, isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    private func canAutoInstall(_ app: InstalledApp, _ remote: RemoteVersion?) -> Bool {
        let result = UpdateResult(
            app: app, remote: remote,
            status: .updateAvailable(latest: remote?.shortVersion ?? "?"))
        return UpdatePolicy.canAutoInstall(
            result,
            settings: UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning),
            environment: InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:]))
    }

    @Test func eachCopySelectsItsEditionsRule() throws {
        let rules = Self.registryRules
        #expect(rules.count == 2)
        func variant(_ literal: String?) throws -> String? {
            try #require(GitHubReleasesSource.rule(
                forEditionOf: try copy("26.6.0", literal: literal), among: rules)).variant
        }
        #expect(try variant(Self.selfHostFeed) == "selfhost")
        #expect(try variant(Self.cloudFeed) == nil)
        // Neither literal (the x64 builds), and no executable: the Cloud rule.
        #expect(try variant("ch-cloud ch-selfh") == nil)
        #expect(try variant(nil) == nil)
        // Declaration order does not decide it.
        #expect(GitHubReleasesSource.rule(
            forEditionOf: try copy("26.6.0", literal: Self.selfHostFeed), among: rules.reversed())?.variant
            == "selfhost")
        #expect(GitHubReleasesSource.rule(
            forEditionOf: try copy("26.6.0", literal: Self.cloudFeed), among: rules.reversed())?.variant
            == nil)
    }

    /// The gap this closes: a SelfHost copy on 26.6.0 sees the SelfHost-only
    /// 26.6.1, with a SelfHost dmg, and may one-click it.
    ///
    /// Mutation (run): selection back to `candidates.first(where:)` on channel
    /// → this answers 26.6.0 from the Cloud dmg, red.
    @Test func aSelfHostCopySeesASelfHostOnlyRelease() async throws {
        let app = try copy("26.6.0", literal: Self.selfHostFeed)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "26.6.1")
        let asset = try #require(remote.downloadURL?.lastPathComponent)
        #expect(asset.hasPrefix("Hoppscotch_SelfHost_mac_") && asset.hasSuffix(".dmg"))
        #expect(canAutoInstall(app, remote))
    }

    /// A Cloud copy passes over the SelfHost-only release, as before, and
    /// gets the Cloud dmg.
    @Test func aCloudCopyIsUnaffectedByASelfHostOnlyRelease() async throws {
        let app = try copy("26.5.0", literal: Self.cloudFeed)
        let remote = try #require(try await source().latestVersion(for: app))
        #expect(remote.shortVersion == "26.6.0")
        let asset = try #require(remote.downloadURL?.lastPathComponent)
        #expect(asset.hasPrefix("Hoppscotch_mac_") && asset.hasSuffix(".dmg"))
        #expect(canAutoInstall(app, remote))
    }

    /// A copy with neither literal, or whose executable cannot be read, gets
    /// exactly what the Cloud rule alone (the registry before the SelfHost
    /// rule) gives it, and no one-click.
    @Test func aCopyWithNeitherMarkerBehavesAsBefore() async throws {
        let cloudOnly = Self.registryRules.filter { $0.installedExecutableMarker == nil }
        #expect(cloudOnly.count == 1)
        for literal in ["ch-cloud ch-selfh", nil] as [String?] {
            let app = try copy("26.5.0", literal: literal)
            let now = try #require(try await source().latestVersion(for: app))
            let before = try #require(try await source(cloudOnly).latestVersion(for: app))
            #expect(now.shortVersion == before.shortVersion)
            #expect(now.downloadURL == before.downloadURL)
            #expect(now.shortVersion == "26.6.0")
            #expect(!canAutoInstall(app, now))
        }
    }

    /// No offer crosses editions: each copy is refused the other edition's dmg
    /// as resolved by the source itself.
    @Test func noOneClickAcrossEditions() async throws {
        let selfHost = try copy("26.5.0", literal: Self.selfHostFeed)
        let cloud = try copy("26.5.0", literal: Self.cloudFeed)
        let selfHostOffer = try #require(try await source().latestVersion(for: selfHost))
        let cloudOffer = try #require(try await source().latestVersion(for: cloud))
        #expect(selfHostOffer.downloadURL != cloudOffer.downloadURL)
        #expect(canAutoInstall(selfHost, selfHostOffer))
        #expect(canAutoInstall(cloud, cloudOffer))
        #expect(!canAutoInstall(selfHost, cloudOffer))
        #expect(!canAutoInstall(cloud, selfHostOffer))
    }

    /// The installer reads the downloaded app before any swap: a package
    /// offered as SelfHost whose binary is Cloud is refused for its edition.
    /// The positive control carries the right marker, gets past that check,
    /// and is then refused by the signature gate (the fixtures are unsigned)
    /// — so the refusal above is the edition check's and nothing earlier's.
    ///
    /// Mutation (run): the 3c loop in `VendorInstaller.verifiedBundle` removed
    /// → the mismatched package is refused by the signature gate instead, red.
    @Test func theInstallerRefusesAPackageOfTheOtherEdition() async throws {
        let installed = try copy("26.5.0", literal: Self.selfHostFeed)
        let remote = RemoteVersion(
            shortVersion: "26.6.1", version: nil,
            downloadURL: URL(string: "https://example.invalid/download/Hoppscotch_SelfHost_mac_aarch64.dmg"),
            sourceName: "GitHub", vendorInstallerKind: .dmg)
        let result = UpdateResult(app: installed, remote: remote, status: .updateAvailable(latest: "26.6.1"))
        func apply(_ literal: String) async -> Error? {
            do {
                let package = try copy("26.6.1", literal: literal).path
                let download = DownloadedUpdate(
                    archiveURL: package, bytesDownloaded: 0,
                    workDir: package.deletingLastPathComponent())
                try await VendorInstaller().apply(
                    result, download: download, digestOnlyAllowed: false, onStage: { _ in })
                return nil
            } catch {
                return error
            }
        }
        let wrong = await apply(Self.cloudFeed)
        guard case VendorInstaller.InstallError.packageEditionMismatch? = wrong else {
            Issue.record("expected packageEditionMismatch, got \(String(describing: wrong))")
            return
        }
        let right = await apply(Self.selfHostFeed)
        #expect(right != nil, "an unsigned fixture must not install")
        if case VendorInstaller.InstallError.packageEditionMismatch? = right {
            Issue.record("the right edition was refused for its edition")
        }
    }

    /// A marked rule is stable, found by no installed tag, and has an
    /// unmarked sibling on its channel for the copies matching no marker;
    /// its bundle id has no tag-discovered rule, whose fallbacks pick by
    /// channel alone.
    @Test func editionMarkedRulesAreWellFormed() {
        let rules = GitHubReleaseRegistry.rules
        let marked = rules.filter { $0.installedExecutableMarker != nil }
        #expect(!marked.isEmpty)
        for rule in marked {
            let siblings = rules.filter { $0.bundleID == rule.bundleID }
            #expect(rule.channel == .stable, "\(rule.recipeID)")
            #expect(rule.installedTagPrefix == nil, "\(rule.recipeID)")
            #expect(rule.installedExecutableMarker?.isEmpty == false, "\(rule.recipeID)")
            #expect(siblings.contains { $0.channel == rule.channel && $0.installedExecutableMarker == nil },
                    "\(rule.recipeID)")
            #expect(!siblings.contains { $0.installedTagPrefix != nil }, "\(rule.recipeID)")
            #expect(rule.variant != nil, "\(rule.recipeID)")
        }
    }

    @Test func theNewFieldsSurviveCoding() throws {
        let rule = GitHubReleaseRule(
            bundleID: "zz.fixture", owner: "o", repo: "r",
            installAssetPattern: "^A\\.dmg$", installerKind: .dmg, variant: "e",
            installedExecutableMarker: "edition-e.json")
        let decodedRule = try JSONDecoder().decode(
            GitHubReleaseRule.self, from: try JSONEncoder().encode(rule))
        #expect(decodedRule.installedExecutableMarker == "edition-e.json")
        #expect(decodedRule.variant == "e")
        let plain = try JSONDecoder().decode(
            GitHubReleaseRule.self,
            from: try JSONEncoder().encode(GitHubReleaseRule(bundleID: "zz.fixture", owner: "o", repo: "r")))
        #expect(plain.installedExecutableMarker == nil)

        let gate = OneClickGate(
            bundleID: "zz.fixture", requirement: .executableContains(marker: "edition-e.json"),
            reason: "r", offering: "^GitHub:A\\.dmg$")
        let decodedGate = try JSONDecoder().decode(OneClickGate.self, from: try JSONEncoder().encode(gate))
        #expect(decodedGate.offering == "^GitHub:A\\.dmg$")
        let unscoped = try JSONDecoder().decode(
            OneClickGate.self,
            from: try JSONEncoder().encode(OneClickGate(
                bundleID: "zz.fixture", requirement: .installedVersion(pattern: "x"), reason: "r")))
        #expect(unscoped.offering == nil)
        // Every registered gate and rule round-trips its new field.
        for gate in OneClickGateRegistry.gates {
            let back = try JSONDecoder().decode(OneClickGate.self, from: try JSONEncoder().encode(gate))
            #expect(back.offering == gate.offering)
        }
        for rule in GitHubReleaseRegistry.rules {
            let back = try JSONDecoder().decode(GitHubReleaseRule.self, from: try JSONEncoder().encode(rule))
            #expect(back.installedExecutableMarker == rule.installedExecutableMarker)
        }
    }
}
