import Foundation
import Testing
@testable import DuoUpdaterCore

// Fixtures are trimmed slices of the REAL responses (fetched 2026-08-26), with
// the asset lists kept in the vendor's own order — linux, macos, windows — so the
// arch/channel anchors are exercised against the ordering they actually face
// rather than a two-asset document where any pattern would look correct.

private let longbridgeStableManifest = #"""
{"version":"0.19.1","created_at":"2026-08-20T10:13:36Z","published_at":"2026-08-20T07:46:53Z","release_notes":{"en":"### Improvements\r\n\r\n- Fixed an issue where the editor could quit unexpectedly.","zh-CN":"### 优化\r\n\r\n- 修复编辑器问题。"},"assets":[{"name":"longbridge-v0.19.1-linux-x86_64.AppImage","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-linux-x86_64.AppImage","sha256":"02723b20e480604b2e9f44137757bc9cb4397bf261eb87c543feeafd2d6fb426"},{"name":"longbridge-v0.19.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-aarch64.dmg","sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa"},{"name":"longbridge-v0.19.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-x86_64.dmg","sha256":"5d3325bd671735b4720e2ac7d232cedf9b4a8abf3953ff2247e17e54d9d134b5"},{"name":"longbridge-v0.19.1-windows-x86_64.exe","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-windows-x86_64.exe","sha256":"1b0c1a1d9c0b2f3e4d5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e"}]}
"""#

// The preview manifest's assets carry NO `sha256` — a real structural difference
// from stable's, preserved here so the fixture cannot flatter the recipe.
private let longbridgePreviewManifest = #"""
{"version":"0.19.0-preview.1","created_at":"2026-08-19T06:25:22Z","published_at":"2026-08-19T09:45:23Z","release_notes":{"en":"### Improvements\r\n\r\n- **Quant**: Added an abbreviation input."},"assets":[{"name":"longbridge-v0.19.0-preview.1-linux-x86_64.AppImage","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-linux-x86_64.AppImage"},{"name":"longbridge-v0.19.0-preview.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-macos-aarch64.dmg"},{"name":"longbridge-v0.19.0-preview.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-macos-x86_64.dmg"},{"name":"longbridge-v0.19.0-preview.1-windows-x86_64.exe","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-windows-x86_64.exe"}]}
"""#

private let longbridgeStableNotes = #"""
<main><div style="position:relative;" class="vp-doc _desktop_release-notes_v0_19_1" data-v-x><div>
<h1 id="v0-19-1" tabindex="-1">v0.19.1 <a class="header-anchor" href="#v0-19-1">​</a></h1>
<p><em>Release Date: 2026-08-20</em></p>
<h3 id="improvements">Improvements <a class="header-anchor">​</a></h3><ul>
<li>Fixed an issue where the editor could quit unexpectedly.</li>
<li>Fixed vertical lists occasionally showing an unnecessary horizontal scrollbar.</li>
</ul><h2 id="downloads">Downloads</h2><ul><li>macOS installer</li></ul>
</div></div></main>
"""#

/// v0.19.0's real shape: `<p><strong>` category labels between `<ul>` blocks,
/// videos after the text they illustrate, and one `<img>` mid-list.
private let longbridgeStableRichNotes = #"""
<main><div style="position:relative;" class="vp-doc _desktop_release-notes_v0_19_0" data-v-x><div>
<h1 id="v0-19-0" tabindex="-1">v0.19.0 <a class="header-anchor" href="#v0-19-0">​</a></h1>
<p><em>Release Date: 2026-08-19</em></p>
<p><strong>Screening &amp; quant</strong></p><ul>
<li>Screener: Added multi-dimensional filters.<video src="https://assets.lbkrs.com/demo.mp4" type="video/mp4">Your browser does not support the video tag.</video></li>
<li>Financials: Added score details.<img width="3584" alt="score" src="https://assets.lbkrs.com/uploads/Score.png"></li>
<li>Watchlist: Added list-width controls.</li>
</ul><h2 id="downloads">Downloads</h2><ul><li>macOS installer</li></ul>
</div></div></main>
"""#

/// The preview page's `<h1>` carries the `-preview.N` suffix and a VPBadge span.
private let longbridgePreviewNotes = #"""
<main><div style="position:relative;" class="vp-doc _desktop_release-notes_preview_v0_19_0-preview_1" data-v-x><div>
<h1 id="v0-19-0-preview-1" tabindex="-1">v0.19.0-preview.1 <span class="VPBadge warning"><!--[-->preview<!--]--></span> <a class="header-anchor" href="#v0-19-0-preview-1">​</a></h1>
<p><em>Release Date: 2026-08-19</em></p>
<h3 id="improvements">Improvements <a class="header-anchor">​</a></h3><ul>
<li><strong>Quant</strong>: Added an abbreviation input to the indicator settings panel.</li>
<li>Fixed the take-profit/stop-loss P/L ratio steppers dropping the decimal places.</li>
</ul><h2 id="downloads">Downloads</h2><ul><li>macOS installer</li></ul>
</div></div></main>
"""#

/// The ordering the live pages do NOT currently use: illustration first, change
/// line after it. Longbridge puts media at the end of every bullet today, so this
/// is the shape a vendor restyle would introduce — and the one an item pattern
/// that treats `<img>` as a hard stop silently eats.
private let longbridgeMediaFirstNotes = #"""
<main><div style="position:relative;" class="vp-doc _desktop_release-notes_v0_20_0" data-v-x><div>
<h1 id="v0-20-0" tabindex="-1">v0.20.0 <a class="header-anchor" href="#v0-20-0">​</a></h1>
<p><em>Release Date: 2026-09-01</em></p>
<h3 id="improvements">Improvements <a class="header-anchor">​</a></h3><ul>
<li><img width="1200" alt="chart" src="https://assets.lbkrs.com/uploads/Chart.png">Charts gained a new drawing tool.</li>
<li>Watchlist sorting is now stable.</li>
</ul><h2 id="downloads">Downloads</h2><ul><li>macOS installer</li></ul>
</div></div></main>
"""#

/// Both release-notes INDEX pages: a heading and nothing else. Stable's lists 48
/// version links in the real page, but neither index carries a `Release Date:`
/// block, which is the property the no-version fallback depends on.
private let longbridgeIndexPage = #"""
<main><div style="position:relative;" class="vp-doc _desktop_release-notes_" data-v-x><div>
<h1 id="release-notes" tabindex="-1">Release Notes <a class="header-anchor" href="#release-notes">​</a></h1>
</div></div></main>
"""#

@Suite struct LongbridgeIntegrationTests {

    /// Everything Longbridge in the vendor registry, keyed by channel. Derived
    /// from the registry so a channel added later is covered — or fails loudly
    /// for want of a fixture — instead of quietly escaping these assertions.
    private static let probes: [ReleaseChannel: VendorProbeRecipe] = Dictionary(
        uniqueKeysWithValues: VendorProbeRegistry.recipes
            .filter { $0.bundleID.hasPrefix("com.longbridge.app.desktop") }
            .map { ($0.channel, $0) })

    private static let changelogs: [ReleaseChannel: ChangelogRecipe] = Dictionary(
        uniqueKeysWithValues: ChangelogRecipeRegistry.recipes
            .filter { $0.bundleID.hasPrefix("com.longbridge.app.desktop") }
            .compactMap { recipe in recipe.channel.map { ($0, recipe) } })

    /// channel → (bundle id, manifest body, the version that body declares).
    private static let manifests: [ReleaseChannel: (String, String, String)] = [
        .stable: ("com.longbridge.app.desktop", longbridgeStableManifest, "0.19.1"),
        .preview: ("com.longbridge.app.desktop.preview", longbridgePreviewManifest,
                   "0.19.0-preview.1"),
    ]

    private static let notes: [ReleaseChannel: (String, String)] = [
        .stable: (longbridgeStableNotes, "0.19.1"),
        .preview: (longbridgePreviewNotes, "0.19.0-preview.1"),
    ]

    // MARK: - Registry coverage

    @Test func everyRegisteredChannelHasAFixture() {
        #expect(!Self.probes.isEmpty)
        for channel in Self.probes.keys {
            #expect(Self.manifests[channel] != nil,
                    "vendor probe for channel \(channel.rawValue) has no manifest fixture")
        }
        for channel in Self.changelogs.keys {
            #expect(Self.notes[channel] != nil,
                    "changelog recipe for channel \(channel.rawValue) has no notes fixture")
        }
        // Both registries must agree on which channels exist, or one of them is
        // serving a channel the other silently drops.
        #expect(Set(Self.probes.keys) == Set(Self.changelogs.keys))
    }

    // MARK: - Vendor probe

    @Test(arguments: [ReleaseChannel.stable, .preview])
    func probeReadsItsOwnChannelsMarketingVersion(channel: ReleaseChannel) throws {
        let recipe = try #require(Self.probes[channel])
        let (bundleID, body, expected) = try #require(Self.manifests[channel])

        #expect(recipe.bundleID == bundleID)
        #expect(recipe.versionIsBuild == false)
        #expect(VendorProbeRecipe.extractVersion(
            from: body, pattern: recipe.versionPattern) == expected)
    }

    @Test(arguments: [ReleaseChannel.stable, .preview])
    func installerSelectsTheAppleSiliconDMGOfItsOwnChannel(channel: ReleaseChannel) throws {
        let recipe = try #require(Self.probes[channel])
        let (_, body, version) = try #require(Self.manifests[channel])
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("Longbridge installer must resolve from the manifest body")
            return
        }
        let url = try #require(VendorProbeRecipe.extractVersion(from: body, pattern: pattern))
        #expect(url.hasSuffix("longbridge-v\(version)-macos-aarch64.dmg"))
        // The vendor lists linux first and x86_64 right after aarch64, so a
        // first-match-any-dmg pattern would pick the wrong file on both axes.
        #expect(!url.contains("x86_64"))
        #expect(!url.contains("linux"))
        #expect(spec.kind == .dmg)
    }

    /// The failure a copied-from-stable recipe makes: patterns that still match,
    /// against the other train's document. Both directions, both fields.
    @Test func theTwoChannelsPatternsCannotMatchEachOthersManifest() throws {
        let stable = try #require(Self.probes[.stable])
        let preview = try #require(Self.probes[.preview])

        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifest, pattern: stable.versionPattern) == nil,
            "the stable version pattern must not read a preview manifest")
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeStableManifest, pattern: preview.versionPattern) == nil,
            "the preview version pattern must not read a stable manifest")

        for (own, other, label) in [
            (stable, longbridgePreviewManifest, "stable installer vs preview manifest"),
            (preview, longbridgeStableManifest, "preview installer vs stable manifest"),
        ] {
            guard case .bodyPattern(let pattern) = try #require(own.install).urlSource else {
                Issue.record("expected a bodyPattern installer")
                return
            }
            #expect(VendorProbeRecipe.extractVersion(
                from: other, pattern: pattern) == nil, "\(label) must not resolve")
        }
    }

    @Test func thePreviewChannelRegistersAnArtifactProof() throws {
        let key = ChannelProofKey("com.longbridge.app.desktop.preview", .preview)
        let proof = try #require(ChannelProofRegistry.proofs[key])
        guard case .artifact(let pattern) = proof else {
            Issue.record("expected a URL-anchored artifact proof")
            return
        }
        let preview = try #require(Self.probes[.preview])
        guard case .bodyPattern(let installPattern) =
                try #require(preview.install).urlSource else { return }
        let url = try #require(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifest, pattern: installPattern))
        #expect(url.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil,
                "the resolved preview installer must satisfy its own channel proof")
    }

    /// `com.longbridge.app.desktop.preview` must resolve to `.preview`, or the
    /// source refuses the recipe and Preview installs silently go unchecked.
    @Test func thePreviewBundleIDDetectsAsThePreviewChannel() {
        #expect(ReleaseChannel.detect(
            name: "Longbridge Preview",
            bundleID: "com.longbridge.app.desktop.preview",
            keystoneChannel: nil, version: "0.19.0-preview.1") == .preview)
        #expect(ReleaseChannel.detect(
            name: "Longbridge", bundleID: "com.longbridge.app.desktop",
            keystoneChannel: nil, version: "0.19.1") == .stable)
    }

    /// The `-preview.N` suffix has to order correctly, or Preview users get a
    /// permanent phantom update (or never get a real one).
    @Test func previewVersionsCompareWithoutPhantomUpdates() {
        #expect(!VersionComparator.isNewer("0.19.0-preview.1", than: "0.19.0-preview.1"))
        #expect(VersionComparator.isNewer("0.19.0-preview.2", than: "0.19.0-preview.1"))
        #expect(VersionComparator.isNewer("0.19.1-preview.0", than: "0.19.0-preview.1"))
        #expect(VersionComparator.isNewer("0.20.0-preview.0", than: "0.19.0-preview.9"))
        // A finished release outranks its own pre-releases.
        #expect(VersionComparator.isNewer("0.19.0", than: "0.19.0-preview.1"))
    }

    // MARK: - Changelog

    @Test(arguments: [ReleaseChannel.stable, .preview])
    func changelogReadsTheExactVersionPage(channel: ReleaseChannel) throws {
        let recipe = try #require(Self.changelogs[channel])
        let (page, expected) = try #require(Self.notes[channel])

        #expect(recipe.structuredFormat == nil)
        #expect(recipe.mode == .html)
        #expect(recipe.resolvedSource(forVersion: expected).absoluteString
            .hasSuffix("v\(expected)"))

        let entry = try #require(
            ChangelogExtractor.extract(from: page, using: recipe)?.entries.first)
        #expect(entry.version == expected)
        #expect(entry.date != nil)
        #expect(!entry.items.isEmpty)
        // The Downloads section sits past the entry boundary, so installer links
        // can never arrive as change lines.
        #expect(entry.items.allSatisfy { !$0.contains("installer") })
    }

    /// Why the preview recipe needs its own version group, stated as a fact
    /// rather than a hope: stable's group applied to a preview page does NOT
    /// fail — it matches and stops at `0.19.0`, which would label a preview build
    /// with a stable version number it does not have. The separation that makes
    /// this unreachable is the bundle id, so assert the registry's routing too;
    /// if a future edit ever collapsed the two onto one bundle id, this is the
    /// test that would notice.
    @Test func theStablePatternWouldMisreadAPreviewPageSoRoutingMustKeepThemApart()
        throws {
        let stable = try #require(Self.changelogs[.stable])
        let truncated = ChangelogExtractor.extract(
            from: longbridgePreviewNotes, using: stable)?.entries.first
        #expect(truncated?.version == "0.19.0",
                "documents the trap the preview recipe's anchored group avoids")

        let preview = try #require(Self.changelogs[.preview])
        #expect(ChangelogExtractor.extract(
            from: longbridgeStableNotes, using: preview) == nil,
            "the preview recipe must not match a stable page")
        #expect(ChangelogExtractor.extract(
            from: longbridgePreviewNotes, using: preview)?
            .entries.first?.version == "0.19.0-preview.1")

        // Routing: each bundle id resolves to its own recipe, never the other's.
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop.preview", channel: .preview)?
            .bundleID == "com.longbridge.app.desktop.preview")
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop", channel: .stable)?
            .bundleID == "com.longbridge.app.desktop")
    }

    /// The no-version fallback. `source` must be an index that yields NOTHING, so
    /// the UI embeds the vendor page instead of presenting one pinned release's
    /// notes as if they described the installed build.
    @Test(arguments: [ReleaseChannel.stable, .preview])
    func theUntemplatedSourceIsAnIndexThatParsesNothing(channel: ReleaseChannel) throws {
        let recipe = try #require(Self.changelogs[channel])
        #expect(recipe.sourceTemplate != nil)
        // No version supplied → the bare `source`, which must not be a version page.
        let fallback = recipe.resolvedSource(forVersion: nil)
        #expect(fallback == recipe.source)
        #expect(fallback.absoluteString.range(of: #"/v[0-9]"#, options: .regularExpression) == nil,
                "the fallback source is pinned to a version page: \(fallback)")
        #expect(ChangelogExtractor.extract(from: longbridgeIndexPage, using: recipe) == nil)
    }

    @Test func richNotesKeepImagesInDocumentOrderAndDropVideoFallbackText() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let entry = try #require(ChangelogExtractor.extract(
            from: longbridgeStableRichNotes, using: recipe)?.entries.first)
        #expect(entry.version == "0.19.0")
        #expect(entry.items == [
            "Screening & quant",
            "Screener: Added multi-dimensional filters.",
            "Financials: Added score details.",
            "Watchlist: Added list-width controls.",
        ])
        #expect(entry.items.allSatisfy { !$0.contains("does not support") })
        #expect(entry.content == [
            .note("Screening & quant"),
            .note("Screener: Added multi-dimensional filters."),
            .note("Financials: Added score details."),
            .image(try #require(URL(string: "https://assets.lbkrs.com/uploads/Score.png"))),
            .note("Watchlist: Added list-width controls."),
        ])
    }

    /// A change line must survive its own illustration appearing BEFORE it.
    ///
    /// `<img>` is a void tag carrying no text, `stripTags` removes it anyway, and
    /// `imagePattern` collects images from the whole body independently of item
    /// boundaries — so treating `<img` as an item terminator never added anything
    /// and could only truncate. When the image came first the captured item was
    /// empty, `minItemLength` discarded it, and scanning resumed at the `<img>`,
    /// past the point where the bullet's text lived: the whole line vanished
    /// rather than merely losing its tail.
    @Test func aChangeLineSurvivesAnIllustrationPlacedBeforeIt() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let entry = try #require(ChangelogExtractor.extract(
            from: longbridgeMediaFirstNotes, using: recipe)?.entries.first)
        #expect(entry.items == [
            "Charts gained a new drawing tool.",
            "Watchlist sorting is now stable.",
        ])
        // The image is still collected. It renders AFTER its own line rather than
        // before it, even though the markup puts it first: `ChangelogExtractor`
        // interleaves on each match's START offset, and an item's match starts at
        // its `<li>` tag, which precedes the `<img>` nested inside it. So a bullet's
        // note always sorts ahead of an image belonging to that same bullet. That
        // is a property of the extractor, not of this recipe, and it reads fine —
        // pinned here so the ordering is a decision on record rather than a
        // surprise the next person re-derives.
        #expect(entry.content == [
            .note("Charts gained a new drawing tool."),
            .image(try #require(URL(string: "https://assets.lbkrs.com/uploads/Chart.png"))),
            .note("Watchlist sorting is now stable."),
        ])
    }

    @Test func changelogCatalogProvidesAWebFallbackForStable() {
        #expect(ChangelogCatalog.url(forBundleID: "com.longbridge.app.desktop")?
            .absoluteString == "https://longbridge.com/desktop/release-notes/")
    }
}
