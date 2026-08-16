import Testing
import Foundation
@testable import DuoUpdaterCore

// MARK: - GIMP

/// Trimmed from the real `https://www.gimp.org/gimp_versions.json`, captured
/// 2026-08-16 (full file is 139419 bytes / 200 OK). Keeps STABLE's `version` and
/// both `macos` dmg entries verbatim, plus a stub `DEVELOPMENT` entry — enough to
/// prove the recipe reads STABLE and never crosses into the dev channel.
private let gimpVersionsFixture = #"""
{
    "STABLE": [
        {
            "version": "3.2.4",
            "date": "2026-04-17",
            "macos": [
                {
                    "date": "2026-04-18",
                    "filename": "gimp-3.2.4-x86_64.dmg",
                    "sha512": "bc337ba0c54a87ceb28b6578213b8a5c504b01af1c21b032dc6f6254a587c3a3e28b5793f0d1bcfc2780b2c6f3d70f5a1e037d63062944ff688ae8ac780409f8",
                    "sha256": "85214a388687718d30169d88b22794d6b0a89849bcc7aa456f4afb83c1326be8",
                    "build-id": "org.gimp.GIMP_official.x86_64",
                    "min-support": "macOS 11 Big Sur"
                },
                {
                    "date": "2026-04-18",
                    "filename": "gimp-3.2.4-arm64.dmg",
                    "sha512": "e6c20b88dbcb41d7830ffcb59c9b89b1a1356ef223546bddb16653eeb3c5f1f475568f2b193f5afd887837ff579c1549c59d4448eb519dac8148671341fa8936",
                    "sha256": "294c016dca7795999129a38b462f80fac3c13cb963e6de9d04eeb5d6e519392b",
                    "build-id": "org.gimp.GIMP_official.arm64",
                    "min-support": "macOS 11 Big Sur"
                }
            ]
        }
    ],
    "DEVELOPMENT": [
        {
            "version": "3.2.0-RC3"
        }
    ]
}
"""#

struct GimpProbeRecipeTests {

    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.gimp.gimp" }
    }

    /// Verified 2026-08-16 against the mounted arm64 dmg: `CFBundleShortVersionString`
    /// AND `CFBundleVersion` both read `3.2.4` — same scheme as the feed, so this is
    /// not a `versionIsBuild` recipe.
    @Test func readsTheStableVersion() throws {
        let recipe = try #require(recipe)
        #expect(!recipe.versionIsBuild)
        #expect(VendorProbeRecipe.extractVersion(
            from: gimpVersionsFixture, pattern: recipe.versionPattern) == "3.2.4")
    }

    /// The JSON has no download URL at all — only the STABLE macos filenames — so
    /// the install URL is rebuilt from the vendor's known host layout
    /// (`download.gimp.org/gimp/v{major.minor}/macos/{filename}`, confirmed live by
    /// HEAD 2026-08-16) via two captures off the same `macos` block.
    @Test func rebuildsTheArm64DownloadURLFromTheFilename() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        guard case .bodyTemplate(let template, let fields) = spec.urlSource else {
            Issue.record("expected a body template"); return
        }
        #expect(fields.count == 2)
        let parts = fields.map { VendorProbeRecipe.extractVersion(from: gimpVersionsFixture, pattern: $0) }
        #expect(parts == ["3.2", "gimp-3.2.4-arm64.dmg"])
        var url = template
        for (index, part) in parts.enumerated() {
            url = url.replacingOccurrences(of: "{\(index)}", with: part ?? "")
        }
        #expect(url == "https://download.gimp.org/gimp/v3.2/macos/gimp-3.2.4-arm64.dmg")
        #expect(spec.kind == .dmg)
    }

    /// GIMP publishes hex sha512/sha256, not the base64 SHA-512 `checksumPattern`
    /// verifies — wiring the hex field would just never match, so it stays unset.
    @Test func carriesNoChecksumBecauseThePublishedHashIsHexNotBase64() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        #expect(spec.checksumPattern == nil)
    }
}

// MARK: - MongoDB Compass

/// Trimmed from the real
/// `https://s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json`,
/// captured 2026-08-16 (full file is 7814 bytes / 200 OK). Keeps `versions[0]`'s
/// `_id` and only the two darwin `platform` entries.
private let compassFixture = #"""
{"versions": [{"_id": "1.49.14", "version": "1.49.14 (Stable)", "platform": [{"arch": "arm64", "os": "darwin", "name": "macOS arm64 (Apple silicon) (11.0+)", "download_link": "https://downloads.mongodb.com/compass/mongodb-compass-1.49.14-darwin-arm64.dmg"}, {"arch": "x64", "os": "darwin", "name": "macOS x64 (Intel) (11+)", "download_link": "https://downloads.mongodb.com/compass/mongodb-compass-1.49.14-darwin-x64.dmg"}]}]}
"""#

struct CompassProbeRecipeTests {

    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.mongodb.compass" }
    }

    /// Verified 2026-08-16 against the mounted arm64 dmg: `CFBundleShortVersionString`
    /// AND `CFBundleVersion` both read `1.49.14`, matching `_id` exactly (not the
    /// decorated `"1.49.14 (Stable)"` sibling field) — same scheme, no `versionIsBuild`.
    @Test func readsTheBareVersionFromID() throws {
        let recipe = try #require(recipe)
        #expect(!recipe.versionIsBuild)
        #expect(VendorProbeRecipe.extractVersion(
            from: compassFixture, pattern: recipe.versionPattern) == "1.49.14")
    }

    /// The arm64/darwin `download_link` must win over the x64 sibling that sits
    /// right after it in the same platform array.
    @Test func installsTheArm64DownloadLinkNotIntel() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        #expect(VendorProbeRecipe.extractVersion(from: compassFixture, pattern: pattern)
            == "https://downloads.mongodb.com/compass/mongodb-compass-1.49.14-darwin-arm64.dmg")
        #expect(spec.kind == .dmg)
    }
}

// MARK: - Meld (dehesselle/meld_macos repack)

/// Trimmed from the real
/// `https://gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases`,
/// captured 2026-08-16 (full file is 24296 bytes / 7 releases / 200 OK). Keeps the
/// first two releases verbatim (newest-first, per the API's own
/// `order_by=released_at&sort=desc` default, confirmed by the response's `Link`
/// header) — enough to prove first-match beats the second entry.
private let meldReleasesFixture = #"""
[{"tag_name": "v3.22.3+105", "released_at": "2025-03-03T20:25:12.000Z", "assets": {"links": [{"id": 6938884, "name": "Meld-3.22.3+105_x86_64.dmg", "url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B105/Meld-3.22.3+105_x86_64.dmg", "direct_asset_url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B105/Meld-3.22.3+105_x86_64.dmg", "link_type": "package"}, {"id": 6938883, "name": "Meld-3.22.3+105_arm64.dmg", "url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B105/Meld-3.22.3+105_arm64.dmg", "direct_asset_url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B105/Meld-3.22.3+105_arm64.dmg", "link_type": "package"}]}}, {"tag_name": "v3.22.3+100", "released_at": "2025-01-19T22:58:30.000Z", "assets": {"links": [{"id": 6595108, "name": "Meld-3.22.3+100_x86_64.dmg", "url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B100/Meld-3.22.3+100_x86_64.dmg", "direct_asset_url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B100/Meld-3.22.3+100_x86_64.dmg", "link_type": "package"}, {"id": 6595107, "name": "Meld-3.22.3+100_arm64.dmg", "url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B100/Meld-3.22.3+100_arm64.dmg", "direct_asset_url": "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos/3.22.3%2B100/Meld-3.22.3+100_arm64.dmg", "link_type": "package"}]}}]
"""#

struct MeldProbeRecipeTests {

    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.gnome.Meld" }
    }

    /// TRAP pinned here: the mounted arm64 dmg reports `CFBundleShortVersionString`
    /// `3.22.3` and `CFBundleVersion` `105` — the tag's two halves map to the
    /// bundle's two DIFFERENT fields. `versionPattern` must capture only the build
    /// integer and drive the comparison via `versionIsBuild`, never the marketing
    /// half alone (three releases in this window share marketing `3.22.3` with
    /// different builds — a marketing-only compare would fold them together and
    /// hide the +100 → +105 update).
    @Test func versionPatternCapturesOnlyTheBuildAndComparesAgainstIt() throws {
        let recipe = try #require(recipe)
        #expect(recipe.versionIsBuild)
        #expect(VendorProbeRecipe.extractVersion(
            from: meldReleasesFixture, pattern: recipe.versionPattern) == "105")
    }

    /// The build alone (`105`) is not what a user should see next to the vendor's
    /// own scheme, so `displayVersionPattern` must recover the full `3.22.3+105`.
    @Test func displayVersionPatternShowsTheFullVendorTag() throws {
        let recipe = try #require(recipe)
        let pattern = try #require(recipe.displayVersionPattern)
        #expect(VendorProbeRecipe.extractVersion(
            from: meldReleasesFixture, pattern: pattern) == "3.22.3+105")
    }

    /// First match must win — the newest release (`+105`) sits first in the feed,
    /// and the older `+100` entry right after it must not leak through.
    @Test func firstMatchIsTheNewestReleaseNotTheSecond() throws {
        let recipe = try #require(recipe)
        #expect(!recipe.selectHighest)
        let build = VendorProbeRecipe.extractVersion(from: meldReleasesFixture, pattern: recipe.versionPattern)
        #expect(build == "105")
        #expect(build != "100")
    }

    /// The install link must be the arm64 dmg's `direct_asset_url`, not the x86_64
    /// sibling that comes first in the same `links` array.
    @Test func installsTheArm64DmgNotX86_64() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        let url = VendorProbeRecipe.extractVersion(from: meldReleasesFixture, pattern: pattern)
        #expect(url == "https://gitlab.com/api/v4/projects/51547804/packages/generic/meld_macos"
            + "/3.22.3%2B105/Meld-3.22.3+105_arm64.dmg")
        #expect(spec.kind == .dmg)
    }

    /// No base64 SHA-512 is published anywhere in this feed (GitLab's
    /// `x-checksum-sha256` response header is hex, and isn't in the body at all).
    @Test func carriesNoChecksum() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        #expect(spec.checksumPattern == nil)
    }
}
