import Testing
import Foundation
@testable import DuoUpdaterCore

/// Jan nightly (`jan-nightly.ai.app`, `Recipes/jan-ai-app.swift`): the Tauri feed
/// `delta.jan.ai/nightly/latest.json`, one recipe per architecture.
struct JanNightlyProbeRecipeTests {

    /// `delta.jan.ai/nightly/latest.json` as served on 2026-10-08, trimmed: the
    /// Windows entries are dropped and the minisign signatures shortened. Key
    /// order and the per-platform shape are the vendor's.
    static let body = """
    {
      "version": "0.8.4-5203",
      "notes": "",
      "pub_date": "2026-09-30T20:56:54.516Z",
      "platforms": {
        "linux-x86_64": {
          "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkK",
          "url": "https://delta.jan.ai/nightly/Jan-nightly_0.8.4-5203_amd64.AppImage"
        },
        "darwin-aarch64": {
          "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkK",
          "url": "https://delta.jan.ai/nightly/Jan-nightly_0.8.4-5203.app.tar.gz"
        },
        "darwin-x86_64": {
          "signature": "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkK",
          "url": "https://delta.jan.ai/nightly/Jan-nightly_0.8.4-5203.app.tar.gz"
        }
      }
    }
    """

    static var recipes: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.bundleID == "jan-nightly.ai.app" }
    }

    /// On every host exactly one recipe runs, and it is the one for that host.
    @Test func eachArchitectureRunsExactlyOneRecipe() throws {
        #expect(Self.recipes.count == 2)
        #expect(Self.recipes.allSatisfy { $0.channel == .nightly })
        for arch in HostArch.allCases {
            let running = Self.recipes.filter { $0.runs(onOS: "26.0.0", arch: arch) }
            #expect(running.count == 1, "\(arch): \(running.map(\.recipeID))")
            #expect(running.first?.hostRequirement?.architectures == [arch])
        }
    }

    @Test func readsTheNightlyVersionVerbatim() throws {
        for recipe in Self.recipes {
            #expect(VendorProbeRecipe.extractVersion(from: Self.body, pattern: recipe.versionPattern)
                    == "0.8.4-5203")
            // A stable-shaped value is not a nightly.
            #expect(VendorProbeRecipe.extractVersion(
                from: #"{"version": "0.8.5", "pub_date": "x"}"#, pattern: recipe.versionPattern) == nil)
        }
    }

    /// Each recipe reads its own `darwin-<arch>` entry: with the other entry's URL
    /// removed, the arm64 recipe still resolves and the x86_64 one does not (and
    /// the reverse).
    @Test func eachRecipeReadsOnlyItsOwnPlatformEntry() throws {
        let arm = try #require(Self.recipes.first { $0.hostRequirement?.architectures == [.arm64] })
        let intel = try #require(Self.recipes.first { $0.hostRequirement?.architectures == [.x86_64] })
        func url(_ recipe: VendorProbeRecipe, _ body: String) throws -> String? {
            guard case .bodyPattern(let pattern) = try #require(recipe.install).urlSource else {
                Issue.record("\(recipe.recipeID) is not a bodyPattern install"); return nil
            }
            return VendorProbeRecipe.extractVersion(from: body, pattern: pattern)
        }
        let expected = "https://delta.jan.ai/nightly/Jan-nightly_0.8.4-5203.app.tar.gz"
        #expect(try url(arm, Self.body) == expected)
        #expect(try url(intel, Self.body) == expected)

        let armOnly = Self.body.replacingOccurrences(of: "\"darwin-x86_64\"", with: "\"darwin-x86_64-gone\"")
        let intelOnly = Self.body.replacingOccurrences(of: "\"darwin-aarch64\"", with: "\"darwin-aarch64-gone\"")
        #expect(try url(arm, armOnly) == expected)
        #expect(try url(intel, armOnly) == nil)
        #expect(try url(intel, intelOnly) == expected)
        #expect(try url(arm, intelOnly) == nil)
        // The Linux AppImage beside it is never an install candidate.
        let linuxOnly = intelOnly.replacingOccurrences(of: "\"darwin-x86_64\"", with: "\"darwin-x86_64-gone\"")
        #expect(try url(arm, linuxOnly) == nil && url(intel, linuxOnly) == nil)
    }

    /// Through the probe runtime, against the fixture served locally.
    @Test func probesTheFixtureEndToEnd() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.body, contentType: "application/json")
        defer { server.stop() }
        let source = VendorProbeSource(hostOSVersion: "26.0.0")
        for recipe in Self.recipes {
            let outcome = await source.probeDiagnostic(recipe.with(url: server.url))
            #expect(outcome.failure == nil, "\(recipe.recipeID): \(String(describing: outcome.failure))")
            #expect(outcome.remote?.shortVersion == "0.8.4-5203")
            #expect(outcome.remote?.downloadURL?.absoluteString
                    == "https://delta.jan.ai/nightly/Jan-nightly_0.8.4-5203.app.tar.gz")
            #expect(outcome.remote?.vendorInstallerKind == .tarGz)
            #expect(outcome.remote?.publishedAt != nil)
        }
    }
}
