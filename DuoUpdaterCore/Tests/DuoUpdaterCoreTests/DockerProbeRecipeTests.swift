import Testing
import Foundation
@testable import DuoUpdaterCore

/// Trimmed from the real `https://desktop.docker.com/mac/main/arm64/appcast.xml`,
/// captured 2026-08-17 (full file carries 13 deltas per item). Everything that
/// matters is preserved verbatim: the channel `<link>` pointing at a THIRD build,
/// the 4.86.0 item listed BEFORE the newer 4.87.0 one, one `.delta` enclosure
/// inside `<sparkle:deltas>`, and the original attribute order.
private let dockerAppcastFixture = """
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:d4w="http://www.docker.com/docker-for-windows">
  <channel>
    <title>Docker for Mac</title>
    <link>https://desktop.docker.com/mac/main/arm64/229452/Docker.dmg</link>
    <item>
      <title>Version 4.86.0 (236216)</title>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <pubDate>2026-08-10T09:13:06Z</pubDate>
      <description></description>
      <enclosure url="https://desktop.docker.com/mac/main/arm64/236216/Docker.dmg" sparkle:version="236216" sparkle:shortVersionString="4.86.0" length="573976729" type="application/octet-stream" d4w:url="" previousBuild="235549"></enclosure>
      <sparkle:deltas>
        <enclosure url="https://desktop.docker.com/mac/main/arm64/236216/Docker-234817.delta" sparkle:version="236216" sparkle:shortVersionString="4.86.0" sparkle:deltaFrom="234817" length="100289824" type="application/octet-stream"></enclosure>
      </sparkle:deltas>
      <visibility>100</visibility>
    </item>
    <item>
      <title>Version 4.87.0 (236836)</title>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <pubDate>2026-08-17T08:42:58Z</pubDate>
      <description></description>
      <enclosure url="https://desktop.docker.com/mac/main/arm64/236836/Docker.dmg" sparkle:version="236836" sparkle:shortVersionString="4.87.0" length="582196078" type="application/octet-stream" d4w:url="" previousBuild="236216"></enclosure>
      <sparkle:deltas>
        <enclosure url="https://desktop.docker.com/mac/main/arm64/236836/Docker-236216.delta" sparkle:version="236836" sparkle:shortVersionString="4.87.0" sparkle:deltaFrom="236216" length="87115679" type="application/octet-stream"></enclosure>
      </sparkle:deltas>
      <visibility>100</visibility>
    </item>
  </channel>
</rss>
"""

@Suite("Docker vendor probe")
struct DockerProbeRecipeTests {
    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.docker.docker" }
    }

    /// `selectHighest` is what makes the reported version right despite the order.
    @Test func reportsTheHighestVersionNotTheFirstListed() throws {
        let recipe = try #require(recipe)
        #expect(recipe.selectHighest)
        #expect(VendorProbeRecipe.highestVersion(
            from: dockerAppcastFixture, pattern: recipe.versionPattern) == "4.87.0")
    }

    /// The bug this file exists for: the download used to be chosen by position
    /// while the version was chosen by comparison, and this feed does not list the
    /// newest release first. Pinned here so the asymmetry can't come back unnoticed.
    @Test func theFirstDockerDmgInTheFeedIsNotTheNewestOne() throws {
        let recipe = try #require(recipe)
        guard case .bodyPatternHighestVersioned(let pattern) = try #require(recipe.install).urlSource
        else { Issue.record("expected a version-paired body pattern"); return }
        // Same regex, taken positionally the way `bodyPattern` would: the 4.86.0
        // image. That is exactly what got downloaded and installed over itself.
        #expect(VendorProbeRecipe.extractVersion(from: dockerAppcastFixture, pattern: pattern)
            != "https://desktop.docker.com/mac/main/arm64/236836/Docker.dmg")
    }

    /// What must actually be downloaded: the full image belonging to the version
    /// that won the comparison — not the older item's, not the channel `<link>`'s
    /// third build, and never a `.delta` (which is also an `<enclosure>` here).
    @Test func installsTheDmgBelongingToTheReportedVersion() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        guard case .bodyPatternHighestVersioned(let pattern) = spec.urlSource
        else { Issue.record("expected a version-paired body pattern"); return }
        let picked = VendorProbeRecipe.highestVersionedURL(
            from: dockerAppcastFixture, pattern: pattern)
        #expect(picked == "https://desktop.docker.com/mac/main/arm64/236836/Docker.dmg")
        #expect(spec.kind == .dmg)
        let url = try #require(picked)
        #expect(!url.contains(".delta"))
        #expect(!url.contains("229452"))
    }

    /// A pattern that captures only the URL must yield nothing rather than quietly
    /// falling back to first-match — that fallback is the whole failure mode.
    @Test func aPatternWithoutAVersionGroupSelectsNothing() {
        #expect(VendorProbeRecipe.highestVersionedURL(
            from: dockerAppcastFixture,
            pattern: #"<enclosure[^>]*url="(https://desktop\.docker\.com/[^"]+/Docker\.dmg)""#) == nil)
    }
}
