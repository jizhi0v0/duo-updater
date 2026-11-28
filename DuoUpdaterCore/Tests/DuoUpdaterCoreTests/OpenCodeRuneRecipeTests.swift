import Foundation
import Testing
@testable import DuoUpdaterCore

struct OpenCodeRuneRecipeTests {
    private static let bundleID = "anomaly.opencode-rune"
    private static let digest = "09e4240a3c3ee25b99d0e6c5b916dfb382cc6f59836718d735a6de8551920a9e"
    private static let artifact = "/release/opencode/files/\(digest)/OpenCode-Rune-0.0.0-dev-503-macos-arm64.dmg"

    // Vendor dev.json trimmed to the two arm64 artifacts. The targets precede
    // the release metadata to exercise key-order independence. The ZIP and DMG
    // carry separate digests.
    private static let manifest = #"""
    {
      "schema": 1,
      "app": "opencode",
      "artifact": "desktop-rune",
      "channel": "dev",
      "sequence": 70,
      "published_at": "2026-11-28T07:02:35Z",
      "release": {
        "targets": {
          "macos-arm64": {
            "url": "/release/opencode/files/1841c2d4b265fd5ecd6121a498eab608fbe334b751fb97fcd84c936fe5343baf/OpenCode-Rune-0.0.0-dev-503-macos-arm64.zip",
            "sha256": "1841c2d4b265fd5ecd6121a498eab608fbe334b751fb97fcd84c936fe5343baf"
          },
          "macos-arm64-dmg": {
            "url": "\#(artifact)",
            "size": 195703231,
            "sha256": "\#(digest)"
          }
        },
        "rollout_percent": 100,
        "version": "0.0.0-dev-503"
      }
    }
    """#

    @Test func devBundleGetsTheArmDMGAndItsOwnDigest() async throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == Self.bundleID })
        let channel = ReleaseChannel.detect(
            name: "OpenCode (Rune)", bundleID: Self.bundleID,
            keystoneChannel: nil, version: "0.0.0-dev-502")
        #expect(channel == recipe.channel)
        #expect(channel == .dev)
        #expect(recipe.matchesInstalled(version: "0.0.0-dev-502"))
        #expect(!recipe.matchesInstalled(version: "0.0.0-pr-502"))

        let result = try await probe(recipe, body: Self.manifest)
        let remote = try #require(result.remote)
        #expect(remote.shortVersion == "0.0.0-dev-503")
        #expect(VersionComparator.isNewer(try #require(remote.shortVersion), than: "0.0.0-dev-502"))
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(remote.downloadURL?.absoluteString == "https://anoma.ly" + Self.artifact)
        #expect(remote.expectedSHA256 == Self.digest)
        #expect(remote.requiresExactPackageVersion)
        #expect(result.warnings.isEmpty)
    }

    @Test func partialRolloutAndMissingDMGDigestDoNotOfferInPlaceInstall() async throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == Self.bundleID })
        let partial = Self.manifest.replacingOccurrences(of: #""rollout_percent": 100"#, with: #""rollout_percent": 25"#)
        let deferred = try await probe(recipe, body: partial)
        #expect(deferred.remote == nil)
        guard case .notApplicable = deferred.failure else {
            Issue.record("The reordered manifest describes a partial rollout")
            return
        }

        let withoutDigest = Self.manifest.replacingOccurrences(
            of: #""sha256": "\#(Self.digest)""#, with: #""sha256": null"#)
        let missingDigest = try await probe(recipe, body: withoutDigest)
        #expect(missingDigest.remote?.shortVersion == "0.0.0-dev-503")
        #expect(missingDigest.remote?.vendorInstallerKind == nil)
    }

    @Test(arguments: [
        (digest: String(repeating: "a", count: 64), version: "0.0.0-dev-501"),
        (digest: String(repeating: "b", count: 64), version: "0.0.0-dev-503"),
    ])
    func theInstallPathMustNameTheReleaseAndItsDigest(stale: (digest: String, version: String)) async throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == Self.bundleID })
        let invalidPath = "/release/opencode/files/\(stale.digest)/OpenCode-Rune-\(stale.version)-macos-arm64.dmg"
        let stalePath = Self.manifest.replacingOccurrences(of: Self.artifact, with: invalidPath)
        let body = stale.version == "0.0.0-dev-503"
            ? stalePath
            : stalePath.replacingOccurrences(of: Self.digest, with: stale.digest)
        let result = try await probe(recipe, body: body)
        #expect(result.remote?.shortVersion == "0.0.0-dev-503")
        #expect(result.remote?.vendorInstallerKind == nil)
        #expect(result.remote?.expectedSHA256 == nil)
    }

    @Test func publishedDevNotesAreGroupedByRelease() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID, channel: .dev))
        // The first row matches GitHub's ordinary-release dev mirror. The
        // second represents a differently tagged release in the same repo.
        let response = #"""
        [
          {
            "tag_name": "v0.0.0-dev-503", "prerelease": false, "draft": false,
            "published_at": "2026-11-28T07:17:15Z",
            "body": "## What's Changed\n* fix(browser-engine): gate initial remote HTTP(S) navigations until sign-in cookie copy settles (UP-151) by @Hona in https://github.com/anomalyco/opencode-rune/pull/1479"
          },
          {"tag_name":"v0.0.0-test-40","prerelease":false,"draft":false,"body":"## Different train\n* Do not show"}
        ]
        """#
        let log = try #require(ChangelogService.parse(recipe, body: response))
        #expect(log.entries.map(\.version) == ["0.0.0-dev-503"])
        let entry = try #require(log.entries.first)
        #expect(entry.date == "2026-11-28")
        #expect(entry.items.count == 1)
        #expect(entry.items.first?.contains("gate initial remote HTTP(S) navigations") == true)
    }

    private func probe(_ recipe: VendorProbeRecipe, body: String) async throws -> ProbeOutcome {
        let server = try RecipeVerificationTests.StubServer(body: body)
        defer { server.stop() }
        return await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
    }
}
