import Foundation
import Testing

@testable import DuoUpdaterCore

/// storytold's seven "-craft" apps (`Recipes/ai-storyteller-*.swift`).
///
/// The anchors on both patterns are the release-candidate guard: PhotoCraft's
/// v0.1.1-rc.4 / rc.5 were published with `prerelease: false`, so
/// `/releases/latest` can answer an rc, and the rc's Info.plist carries the bare
/// X.Y.Z. These pin the tag and asset shapes from the real release listings, then
/// replay an un-flagged rc through the source end to end.
@Suite struct StorytoldCraftGitHubRuleTests {

    static let apps = [
        "designcraft", "effectcraft", "filmcraft", "lightcraft",
        "pdfcraft", "photocraft", "vectorcraft",
    ]

    private static func rule(_ app: String) -> GitHubReleaseRule? {
        GitHubReleaseRegistry.rules.first { $0.bundleID == "ai.storyteller.\(app)" }
    }

    @Test(arguments: apps)
    func ruleReadsTheBareTagAndTheAppDmgOnly(_ app: String) throws {
        let rule = try #require(Self.rule(app), "no GitHubReleaseRule for ai.storyteller.\(app)")
        #expect(rule.owner == "storytold" && rule.repo == app)
        #expect(rule.channel == .stable && !rule.usePrereleases)
        #expect(rule.installerKind == .dmg)
        let pattern = try #require(rule.installAssetPattern)
        func extract(_ tag: String) -> String? {
            VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern)
        }
        func matches(_ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }

        #expect(extract("v0.3.1") == "0.3.1")
        #expect(extract("v0.1.1-rc.5") == nil)
        #expect(extract("v0.2.0-rc.1") == nil)

        #expect(matches("\(app)-0.3.1-macos-universal.dmg"))
        // The rest of a real release listing.
        #expect(!matches("\(app)-0.1.1-rc.5-macos-universal.dmg"))
        #expect(!matches("\(app)-cli-0.3.1-macos-universal.zip"))
        #expect(!matches("\(app)-web-0.3.1.zip"))
        #expect(!matches("\(app)-0.3.1-linux-aarch64.tar.gz"))
        #expect(!matches("\(app)-0.3.1-windows-x64-portable.zip"))
        #expect(!matches("SHA256SUMS.txt"))
    }

    // MARK: - An un-flagged rc as `/releases/latest`

    /// Newest first, as `(tag, assetNames)`, every one `prerelease: false` — the
    /// shape PhotoCraft really published.
    private static let releases: [(String, [String])] = [
        ("v0.2.1-rc.1", ["photocraft-0.2.1-rc.1-macos-universal.dmg",
                         "photocraft-cli-0.2.1-rc.1-macos-universal.zip"]),
        ("v0.2.0", ["photocraft-0.2.0-macos-universal.dmg",
                    "photocraft-cli-0.2.0-macos-universal.zip"]),
        ("v0.1.1", ["photocraft-0.1.1-macos-universal.dmg"]),
    ]

    final class StubReleases: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            let all = StorytoldCraftGitHubRuleTests.releases
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
                "https://github.com/storytold/photocraft/releases/download/\(release.0)/\($0)",\
                "size":1000}
                """
            }
            return """
            "tag_name":"\(release.0)","name":"PhotoCraft \(release.0)","draft":false,\
            "prerelease":false,"published_at":"2026-10-05T00:00:00Z",\
            "html_url":"https://github.com/storytold/photocraft/releases/tag/\(release.0)",\
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

    /// The dmg pattern is what produces the right answer: the rc's dmg doesn't
    /// match, so the source leaves `/releases/latest` for the list and walks past
    /// it. The tag anchor is the backstop. Mutations (each run): default tag
    /// pattern alone → still 0.2.0; `[0-9].*` for the dmg's version alone → no
    /// answer at all (the rc's tag is refused and there is no walk); both → the
    /// rc is offered as 0.2.1.
    @Test func anUnflaggedReleaseCandidateIsWalkedPast() async throws {
        let rule = try #require(Self.rule("photocraft"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubReleases.self]
        let source = GitHubReleasesSource(
            rules: [rule], session: URLSession(configuration: config))
        let outcome = await source.resolveDiagnostic(
            rule, preferring: .arm64, allowingIntelTranslation: false)
        #expect(outcome.failure == nil)
        #expect(outcome.remote?.shortVersion == "0.2.0")
        #expect(outcome.remote?.downloadURL?.lastPathComponent
                == "photocraft-0.2.0-macos-universal.dmg")
    }

    // MARK: - PrintCraft became PdfCraft (#1087)

    /// The rename moved the repo, the asset names and the bundle id at once. The
    /// rule reads the new repo and takes the new dmg only — an old-name dmg is the
    /// old id, which gate 4 never lets replace a PdfCraft copy.
    /// Mutation: point the rule back at `printcraft` (repo or dmg) → red.
    @Test func pdfCraftReadsTheRenamedRepoAndDmg() throws {
        let rule = try #require(Self.rule("pdfcraft"))
        #expect(rule.slug == "storytold/pdfcraft")
        let pattern = try #require(rule.installAssetPattern)
        func matches(_ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }
        // v0.4.0's real macOS assets.
        #expect(matches("pdfcraft-0.4.0-macos-universal.dmg"))
        #expect(!matches("pdfcraft-cli-0.4.0-macos-universal.zip"))
        // v0.2.1's, under the old name.
        #expect(!matches("printcraft-0.2.1-macos-universal.dmg"))
        #expect(!matches("printcraft-cli-0.2.1-macos-universal.zip"))
        // Nothing is keyed by the old id any more: a PrintCraft copy gets here
        // through `BundleIDMigration`.
        #expect(Self.rule("printcraft") == nil)
    }

    /// v0.4.0 above v0.2.1, as the renamed repo lists them.
    final class StubPdfCraft: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requested: [String] = []
        static let releases: [(String, [String])] = [
            ("v0.4.0", ["pdfcraft-0.4.0-macos-universal.dmg",
                        "pdfcraft-cli-0.4.0-macos-universal.zip"]),
            ("v0.2.1", ["printcraft-0.2.1-macos-universal.dmg",
                        "printcraft-cli-0.2.1-macos-universal.zip"]),
        ]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url?.absoluteString ?? ""
            Self.requested.append(url)
            let body = url.contains("/releases/latest")
                ? "{\(Self.fields(Self.releases[0]))}"
                : "[\(Self.releases.map { "{\(Self.fields($0))}" }.joined(separator: ","))]"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        private static func fields(_ release: (String, [String])) -> String {
            let assets = release.1.map {
                """
                {"name":"\($0)","browser_download_url":\
                "https://github.com/storytold/pdfcraft/releases/download/\(release.0)/\($0)",\
                "size":1000}
                """
            }
            return """
            "tag_name":"\(release.0)","name":"\(release.0)","draft":false,\
            "prerelease":false,"published_at":"2026-10-08T00:00:00Z",\
            "html_url":"https://github.com/storytold/pdfcraft/releases/tag/\(release.0)",\
            "body":"notes","assets":[\(assets.joined(separator: ","))]
            """
        }

        override func stopLoading() {}
    }

    private static func installed(_ id: String, _ version: String) -> InstalledApp {
        InstalledApp(
            name: "PrintCraft", bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-PrintCraft.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    /// A PrintCraft 0.2.1 copy, still `ai.storyteller.printcraft`, is offered
    /// PdfCraft 0.4.0's dmg by the production source, asking the new slug — not
    /// the old one, whose redirect drops the token. A copy on the old id at or
    /// past the migration's bound is not the rename and gets nothing.
    /// Mutation: drop the PrintCraft entry from `BundleIDMigration.all`, or look
    /// rules up by `app.bundleID` again → the first expectation fails.
    @Test func anOldPrintCraftCopyIsOfferedPdfCraft() async throws {
        let rule = try #require(Self.rule("pdfcraft"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubPdfCraft.self]
        let source = GitHubReleasesSource(rules: [rule], session: URLSession(configuration: config))

        StubPdfCraft.requested = []
        let remote = try await source.latestVersion(for: Self.installed("ai.storyteller.printcraft", "0.2.1"))
        #expect(remote?.shortVersion == "0.4.0")
        #expect(remote?.downloadURL?.lastPathComponent == "pdfcraft-0.4.0-macos-universal.dmg")
        #expect(!StubPdfCraft.requested.isEmpty)
        #expect(StubPdfCraft.requested.allSatisfy { $0.contains("/repos/storytold/pdfcraft/") },
                "\(StubPdfCraft.requested)")

        #expect(try await source.latestVersion(
            for: Self.installed("ai.storyteller.printcraft", "0.4.0")) == nil)
        #expect(try await source.latestVersion(
            for: Self.installed("ai.storyteller.pdfcraft", "0.4.0"))?.shortVersion == "0.4.0")
    }
}
