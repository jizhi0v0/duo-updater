import Testing
import Foundation
@testable import DuoUpdaterCore

/// Petex (`ad.neko.petex`, `iebb/petex`) is detection-only on purpose, and both
/// halves of that decision are easy to undo by accident — so both are pinned
/// here against the real strings the vendor publishes.
///
/// See `docs/app-audits/ad-neko-petex.md` for the measurements.
@Suite struct PetexGitHubRuleTests {

    /// The rule as it ships. Every test starts from this rather than from a
    /// locally built one: a lookup that stops finding it (bundle id typo'd,
    /// family unregistered, vendor renamed again) has to fail loudly instead of
    /// leaving the suite green while it exercises a rule nobody runs.
    private static var rule: GitHubReleaseRule {
        get throws {
            try #require(
                GitHubReleaseRegistry.rules.first { $0.bundleID == "ad.neko.petex" },
                "ad.neko.petex is no longer in GitHubReleaseRegistry")
        }
    }

    /// The macOS artifact is ad-hoc, linker-signed, with no Team Identifier and
    /// no sealed resources (`build.yml` sets `CSC_IDENTITY_AUTO_DISCOVERY:
    /// 'false'`). `SignatureVerifier`'s gate 2 and gate 3 would each refuse the
    /// swap by themselves, so an install spec copied over from a sibling
    /// Electron recipe could only ever produce an Update button that fails.
    @Test func petexStaysDetectionOnly() throws {
        let rule = try Self.rule
        #expect(rule.installAssetPattern == nil,
                "Petex ships an unsigned build — an install pattern here can only fail the Team-ID gate")
        #expect(rule.installerKind == nil)
    }

    /// The three tags published as of 2026-09-16, and what the source must read
    /// out of each. `extractVersion` is the same call `GitHubReleasesSource`
    /// makes on every release it walks.
    @Test(arguments: [("v1.0.10", "1.0.10"), ("v1.0.9", "1.0.9"), ("v1.0.7", "1.0.7")])
    func realTagsResolveToTheirVersion(tag: String, expected: String) throws {
        let rule = try Self.rule
        #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern)
                == expected)
    }

    /// The mutation the anchors exist for: relax `versionPattern` to the
    /// registry default (`v?([0-9]+(?:\.[0-9]+)+)`, unanchored at both ends) and
    /// a prerelease-shaped tag reads as a plain stable version that was never
    /// published. Petex's patch component is a commit height, so every tag looks
    /// like an ordinary release and nothing else in the string would give the
    /// suffix away — and `GitHubReleasesSource`'s own prerelease filters cannot
    /// catch it either, because they read GitHub's `prerelease` flag and this
    /// vendor's publish script never sets it (`gh release edit --draft=false
    /// --latest` on every push). The anchors are the only gate.
    @Test func aPrereleaseShapedTagIsRejected() throws {
        let rule = try Self.rule
        #expect(VendorProbeRecipe.extractVersion(from: "v1.0.11-beta.1", pattern: rule.versionPattern)
                == nil)
        // The failure this guards against, spelled out: the default pattern does
        // accept it, and hands back a version the vendor never shipped.
        #expect(VendorProbeRecipe.extractVersion(
            from: "v1.0.11-beta.1", pattern: #"v?([0-9]+(?:\.[0-9]+)+)"#) == "1.0.11")
    }

    /// Why this family carries no `ChangelogRecipe`. Petex's releases are cut by
    /// `gh release create --generate-notes` on a repository with no pull
    /// requests, so GitHub generates a body with no "What's Changed" section at
    /// all — one boilerplate line. The parser's prose pass skips exactly that
    /// line, so the body yields no entry, and a `.gitHubReleases` recipe over
    /// this repo would fetch a page of releases to produce nothing.
    ///
    /// Verbatim v1.0.10 body, fetched 2026-09-16.
    @Test func theRealReleaseBodyYieldsNoEntry() {
        let body = "**Full Changelog**: https://github.com/iebb/petex/compare/v1.0.9...v1.0.10"

        #expect(GitHubMarkdownParser.parse(body: body, version: "1.0.10", date: nil) == nil)
    }
}
