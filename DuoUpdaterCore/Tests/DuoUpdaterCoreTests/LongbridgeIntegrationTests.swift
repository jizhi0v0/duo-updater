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

// The preview manifest captured here (0.19.0-preview.1) carried NO `sha256` — a
// real structural difference from stable's at the time, preserved so the fixture
// cannot flatter the recipe.
private let longbridgePreviewManifest = #"""
{"version":"0.19.0-preview.1","created_at":"2026-08-19T06:25:22Z","published_at":"2026-08-19T09:45:23Z","release_notes":{"en":"### Improvements\r\n\r\n- **Quant**: Added an abbreviation input."},"assets":[{"name":"longbridge-v0.19.0-preview.1-linux-x86_64.AppImage","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-linux-x86_64.AppImage"},{"name":"longbridge-v0.19.0-preview.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-macos-aarch64.dmg"},{"name":"longbridge-v0.19.0-preview.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-macos-x86_64.dmg"},{"name":"longbridge-v0.19.0-preview.1-windows-x86_64.exe","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v0.19.0-preview.1-windows-x86_64.exe"}]}
"""#

/// `preview/latest.json` as served 2026-10-07 (1.0.0-preview.1), trimmed to the
/// linux deb and the two macOS dmgs: by then preview assets carried `sha256` too.
/// The aarch64 dmg downloaded that day hashed to its `sha256`.
private let longbridgePreviewManifestWithDigests = #"""
{"version":"1.0.0-preview.1","created_at":"2026-09-07T11:39:49Z","published_at":"2026-09-08T02:05:26Z","release_notes":{"en":"### New Features\r\n- Added a HoverCard on the attached-order switch."},"assets":[{"name":"longbridge-v1.0.0-preview.1-linux-x86_64.deb","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-linux-x86_64.deb","sha256":"90727a40b9c7a0b21ea422460fdf67a40eff37711f14cd7aaa2584c16815ac5a"},{"name":"longbridge-v1.0.0-preview.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-macos-aarch64.dmg","sha256":"4c9aa9992675af7787756c83dda048beb0adb2bb0abefcaec53944572331bd02"},{"name":"longbridge-v1.0.0-preview.1-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-macos-x86_64.dmg","sha256":"5ceca5c26a8ca522516975a8133911ad454dfa1a0f51578db84086d6caa78798"}]}
"""#

/// `preview/latest.json` as served 2026-11-10 (1.2.0-preview.0), trimmed to four
/// assets. File names now carry the build's git hash (`-g86ccd38`), and the
/// manifest lists a second build (`-gbd8ecd3`) with no macOS assets. The aarch64
/// dmg downloaded that day hashed to its `sha256`.
private let longbridgePreviewManifestWithBuildHash = #"""
{"version":"1.2.0-preview.0","created_at":"2026-11-09T12:13:05Z","published_at":"2026-11-09T10:21:17Z","assets":[{"name":"longbridge-v1.2.0-preview.0-g86ccd38-linux-x86_64.deb","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.2.0-preview.0-g86ccd38-linux-x86_64.deb","sha256":"901d7cce61821a2d2a5bba3f27d2fde41db5565f5ceb480c40341c83c6df4495"},{"name":"longbridge-v1.2.0-preview.0-g86ccd38-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.2.0-preview.0-g86ccd38-macos-aarch64.dmg","sha256":"ff841bd9847ea824511ecb4b50fc1d4dc2ab65283c030f14b9495c1586048225"},{"name":"longbridge-v1.2.0-preview.0-g86ccd38-macos-x86_64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.2.0-preview.0-g86ccd38-macos-x86_64.dmg","sha256":"04137a228b84a17c3e08862664a336fe6690d94616bd5b1502df5ed4c3e5bdc5"},{"name":"longbridge-v1.2.0-preview.0-gbd8ecd3-windows-x86_64.exe","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.2.0-preview.0-gbd8ecd3-windows-x86_64.exe","sha256":"d966fa38c79b06c9a35f1bd0fa99458cbca0f23cd9c78e004f8d0f915197d7ff"}]}
"""#

// The 2026-11-18 staged rollout, trimmed to the two arm64 assets.
private let longbridgeRolloutManifest = #"""
{
  "gray": {
    "version": "1.2.0",
    "assets": [{
      "url": "https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v1.2.0-g7595e75-macos-aarch64.dmg",
      "sha256": "0b389c7249467c2db06844b124d51b187cc26aeb65edce3612953e0ef55f5a9a"
    }],
    "device_ratio": "1/10"
  },
  "version": "1.1.2",
  "published_at": "2026-11-10T11:15:55Z",
  "assets": [{
    "url": "https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v1.1.2-macos-aarch64.dmg",
    "sha256": "5d11818c6d87ffafaad1a56f9e24ddd547520575ebb90c6706c429c2183df622"
  }]
}
"""#

/// Official English RSS (2026-11-18), trimmed to five items in feed order.
/// LongbridgeAI shares a version number with Pro but its notes belong to a
/// different product.
private let longbridgeStableRSS = #"""
<rss version="2.0"><channel>
<item><title>Longbridge Pro 1.2.0 · Community, Message Center, and watchlist import and export</title><link>https://longbridge.com/en/changelog/longbridge-pro/v1.2#v1.2.0</link><guid isPermaLink="true">https://longbridge.com/en/changelog/longbridge-pro/v1.2#v1.2.0</guid><description>Adds Community and a Message Center, watchlist import and export as CSV / Excel, and Related ETFs in Stock Detail.</description><pubDate>Wed, 18 Nov 2026 00:00:00 GMT</pubDate></item>
<item><title>LongbridgeAI 1.8.0 · Follow each scheduled task&apos;s latest results</title><link>https://longbridge.com/en/changelog/longbridge-ai/v1.8#v1.8.0</link><guid isPermaLink="true">https://longbridge.com/en/changelog/longbridge-ai/v1.8#v1.8.0</guid><description>Each scheduled task takes one row in the conversation list with its unread count, and the web version can switch to Japanese.</description><pubDate>Fri, 13 Nov 2026 00:00:00 GMT</pubDate></item>
<item><title>Longbridge Pro 1.1.2 · Fixes for take-profit / stop-loss lines and voice input</title><link>https://longbridge.com/en/changelog/longbridge-pro/v1.1#v1.1.2</link><guid isPermaLink="true">https://longbridge.com/en/changelog/longbridge-pro/v1.1#v1.1.2</guid><description>Fixes take-profit / stop-loss lines disappearing from the chart and LongbridgeAI voice input recognition, and improves stability on Windows.</description><pubDate>Tue, 10 Nov 2026 00:00:00 GMT</pubDate></item>
<item><title>LongbridgeAI 1.2.0 · Start chatting, no login required</title><link>https://longbridge.com/en/changelog/longbridge-ai/v1.2#v1.2.0</link><guid isPermaLink="true">https://longbridge.com/en/changelog/longbridge-ai/v1.2#v1.2.0</guid><description>Ask the AI right away without signing up. Build your Agent with Gemini 3.7 Flash or DeepSeek-V4</description><pubDate>Mon, 24 Aug 2026 07:57:48 GMT</pubDate></item>
<item><title>Longbridge Pro 0.19.1 · Fixes for editor crashes and stray scrollbars</title><link>https://longbridge.com/en/changelog/longbridge-pro/v0.19#v0.19.1</link><guid isPermaLink="true">https://longbridge.com/en/changelog/longbridge-pro/v0.19#v0.19.1</guid><description>Fixed an issue where the editor could quit unexpectedly in c</description><pubDate>Thu, 20 Aug 2026 00:00:00 GMT</pubDate></item>
</channel></rss>
"""#

/// Preview's manifest `preview/latest.json` as served 2026-10-14, trimmed to the
/// keys the decoder reads. Only the newest preview build is in it.
private let longbridgePreviewManifestNotes = #"""
{"version":"1.0.0-preview.3","published_at":"2026-10-09T07:20:12Z","release_notes":{"en":"### New Features\r\n\r\n- **LongbridgeAI**: Redesigned the reasoning process, making the AI's progress easy to follow and keeping answers focused.\r\n- **Stock Details**: Added a hot topic card to the pinned board, showing trending discussions about the stock and linking straight to the topic page.\r\n- **Trade**: Added Touch ID unlock for trading on macOS — verify your trade password with just a fingerprint.\r\n- **Account**: Added account switching, so you can switch to any previously signed-in account from the avatar menu without logging out and back in.\r\n- **Chart**: Added \"Signals & Catalysts\" to the K-line chart, marking trading signals and catalyst events on the chart; open one to see the details or ask AI to analyze it, helping you quickly understand what drives a move.\r\n- **Custom Layout**: Added undo, so accidentally removed widgets or a messed-up layout can be restored at any time; tabs can be exported to a file and imported on another device, making layouts easy to share and migrate.\r\n- **Announcements**: New announcements are also sent to the system notification center while the app is in the background, so important notices are not missed.\r\n\r\n### Improvements\r\n\r\n- Added display settings to the heatmap for customizing titles, values, colors and grouping; also improved the layout so small blocks are no longer squeezed into thin strips.\r\n- The Today's Orders popover in chart trading now shows the strategy name and leg details of multi-leg option orders.\r\n- Fixed an issue where a full leap-year range was rejected as longer than one year when exporting historical orders.\r\n- Dragging a widget into an empty custom layout now shows the drop area, and the widget toolbox hides automatically while you adjust panels so it no longer covers the canvas."}}
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
        .stable: (longbridgeStableRSS, "1.2.0"),
        .preview: (longbridgePreviewManifestNotes, "1.0.0-preview.3"),
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

    @Test func rolloutUsesOnlyThePublicVersionDateAndInstaller() async throws {
        let outcome = try await Self.probe(.stable, body: longbridgeRolloutManifest)
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "1.1.2")
        #expect(remote.publishedAt == ISO8601DateFormatter().date(from: "2026-11-10T11:15:55Z"))
        #expect(remote.downloadURL?.lastPathComponent == "longbridge-v1.1.2-macos-aarch64.dmg")
        #expect(remote.expectedSHA256 == "5d11818c6d87ffafaad1a56f9e24ddd547520575ebb90c6706c429c2183df622")
        #expect(outcome.warnings.isEmpty)
    }

    @Test func promotedStableReleaseAcceptsItsHashedDMGAndIgnoresOlderAssets() async throws {
        var manifest = try #require(JSONSerialization.jsonObject(
            with: Data(longbridgeRolloutManifest.utf8)) as? [String: Any])
        let gray = try #require(manifest.removeValue(forKey: "gray") as? [String: Any])
        manifest["version"] = gray["version"]
        manifest["published_at"] = "2026-11-18T06:07:09Z"
        let promotedAssets = try #require(gray["assets"] as? [[String: String]])
        let olderAssets = try #require(manifest["assets"] as? [[String: String]])
        // The vendor's hex digest may be written in either case.
        manifest["assets"] = olderAssets + promotedAssets.map { asset in
            var asset = asset
            asset["sha256"] = asset["sha256"]?.uppercased()
            return asset
        }
        let body = String(decoding: try JSONSerialization.data(withJSONObject: manifest), as: UTF8.self)
        let outcome = try await Self.probe(.stable, body: body)
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "1.2.0")
        #expect(remote.publishedAt == ISO8601DateFormatter().date(from: "2026-11-18T06:07:09Z"))
        #expect(remote.downloadURL?.lastPathComponent == "longbridge-v1.2.0-g7595e75-macos-aarch64.dmg")
        #expect(remote.expectedSHA256 == "0b389c7249467c2db06844b124d51b187cc26aeb65edce3612953e0ef55f5a9a")
        #expect(outcome.warnings.isEmpty)
    }

    @Test func grayOnlyDataCannotSupplyAMissingPublicVersionOrInstaller() async throws {
        let manifest = try #require(JSONSerialization.jsonObject(
            with: Data(longbridgeRolloutManifest.utf8)) as? [String: Any])
        let gray = try #require(manifest["gray"])
        let grayOnly = String(decoding: try JSONSerialization.data(
            withJSONObject: ["gray": gray]), as: UTF8.self)
        let missingVersion = try await Self.probe(.stable, body: grayOnly)
        #expect(missingVersion.remote == nil)

        let noPublicAsset = String(decoding: try JSONSerialization.data(
            withJSONObject: ["gray": gray, "version": "1.2.0"]), as: UTF8.self)
        let missingAsset = try await Self.probe(.stable, body: noPublicAsset)
        #expect(missingAsset.remote?.shortVersion == "1.2.0")
        #expect(missingAsset.remote?.vendorInstallerKind == nil)
        #expect(missingAsset.remote?.expectedSHA256 == nil)
        #expect(missingAsset.warnings.contains(.installURLUnresolved))
    }

    @Test func ineligibleURLsCannotHideTheSelectedAssetsDigest() async throws {
        var manifest = try #require(JSONSerialization.jsonObject(
            with: Data(longbridgeRolloutManifest.utf8)) as? [String: Any])
        let assets = try #require(manifest["assets"] as? [[String: String]])
        let base = "https://assets.lbkrs.com/github/release/longbridge-desktop"
        let filename = "longbridge-v1.1.2-g1234-macos-aarch64.dmg"
        let invalid = [
            ["url": "https://other.example/stable/\(filename)", "sha256": String(repeating: "a", count: 64)],
            ["url": "\(base)/preview/\(filename)", "sha256": String(repeating: "b", count: 64)],
            ["url": "\(base)/stable/\(filename)?variant=other", "sha256": String(repeating: "c", count: 64)],
        ]
        manifest["assets"] = invalid + assets
        let body = String(decoding: try JSONSerialization.data(withJSONObject: manifest), as: UTF8.self)
        let outcome = try await Self.probe(.stable, body: body)
        let remote = try #require(outcome.remote)
        #expect(remote.downloadURL?.absoluteString == assets.first?["url"])
        #expect(remote.expectedSHA256 == assets.first?["sha256"])
        #expect(remote.expectedSHA256 != nil)
        #expect(outcome.warnings.isEmpty)
    }

    @Test func previewStillResolvesItsOwnHashedDMG() async throws {
        let outcome = try await Self.probe(.preview, body: longbridgePreviewManifestWithBuildHash)
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "1.2.0-preview.0")
        #expect(remote.downloadURL?.lastPathComponent == "longbridge-v1.2.0-preview.0-g86ccd38-macos-aarch64.dmg")
        #expect(remote.expectedSHA256 == "ff841bd9847ea824511ecb4b50fc1d4dc2ab65283c030f14b9495c1586048225")
        #expect(outcome.warnings.isEmpty)
    }

    private static func probe(_ channel: ReleaseChannel, body: String) async throws -> ProbeOutcome {
        let recipe = try #require(probes[channel])
        let server = try RecipeVerificationTests.StubServer(body: body)
        defer { server.stop() }
        return await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
    }

    // MARK: - Download digest

    private static func checksumPattern(_ channel: ReleaseChannel) throws -> String {
        let spec = try #require(probes[channel]?.install)
        #expect(spec.checksumFormat == .sha256Hex)
        return try #require(spec.checksumPattern)
    }

    /// The digest is the aarch64 dmg's — the asset the URL reads — not the linux
    /// asset listed first or the x86_64 dmg right after it.
    @Test func eachChannelChecksTheAppleSiliconDMGsOwnSHA256() throws {
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeStableManifest, pattern: try Self.checksumPattern(.stable))
            == "a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa")
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifestWithDigests, pattern: try Self.checksumPattern(.preview))
            == "4c9aa9992675af7787756c83dda048beb0adb2bb0abefcaec53944572331bd02")
        // The preview URL pattern reads the same asset on that body.
        guard case .bodyPattern(let url) = try #require(Self.probes[.preview]?.install).urlSource
        else { return }
        #expect(VendorProbeRecipe.extractVersion(from: longbridgePreviewManifestWithDigests, pattern: url)
            == "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.0.0-preview.1-macos-aarch64.dmg")
    }

    /// Preview file names with the build's git hash (`…-preview.0-g86ccd38-macos-aarch64.dmg`)
    /// still resolve the installer and its own digest, not the x86_64 dmg's (#1930).
    @Test func previewFileNamesWithABuildHashStillResolve() throws {
        let preview = try #require(Self.probes[.preview])
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifestWithBuildHash, pattern: preview.versionPattern) == "1.2.0-preview.0")
        guard case .bodyPattern(let url) = try #require(preview.install).urlSource else {
            Issue.record("preview installer is not read from the body"); return
        }
        #expect(VendorProbeRecipe.extractVersion(from: longbridgePreviewManifestWithBuildHash, pattern: url)
            == "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/longbridge-v1.2.0-preview.0-g86ccd38-macos-aarch64.dmg")
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifestWithBuildHash, pattern: try Self.checksumPattern(.preview))
            == "ff841bd9847ea824511ecb4b50fc1d4dc2ab65283c030f14b9495c1586048225")
        // Without its own digest the aarch64 asset reads nothing, not x86_64's.
        let digestless = longbridgePreviewManifestWithBuildHash.replacingOccurrences(
            of: #","sha256":"ff841bd9847ea824511ecb4b50fc1d4dc2ab65283c030f14b9495c1586048225""#, with: "")
        #expect(VendorProbeRecipe.extractVersion(
            from: digestless, pattern: try Self.checksumPattern(.preview)) == nil)
    }

    /// `sha256` ahead of `name` and `url` inside the asset still pairs with it.
    @Test func theDigestDoesNotDependOnKeyOrder() throws {
        let entry = #"{"name":"longbridge-v0.19.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-aarch64.dmg","sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa"}"#
        let reordered = #"{"sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa","name":"longbridge-v0.19.1-macos-aarch64.dmg","url":"https://assets.lbkrs.com/github/release/longbridge-desktop/stable/longbridge-v0.19.1-macos-aarch64.dmg"}"#
        #expect(longbridgeStableManifest.contains(entry))
        let body = longbridgeStableManifest.replacingOccurrences(of: entry, with: reordered)
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.checksumPattern(.stable))
            == "a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa")
    }

    /// An aarch64 asset without `sha256` reads nothing, not the x86_64 dmg's
    /// digest after it: on preview's 0.19.0-preview.1 manifest (no digests at
    /// all), and on stable's with only the aarch64 digest removed.
    @Test func aDigestlessAssetReadsNothingRatherThanTheNextAssetsDigest() throws {
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifest, pattern: try Self.checksumPattern(.preview)) == nil)
        let body = longbridgeStableManifest.replacingOccurrences(
            of: #","sha256":"a666daf0da71e524a378178f45cbd216d377a9cbe2cd8353ff6a77b1f6a74daa""#, with: "")
        #expect(body != longbridgeStableManifest)
        #expect(body.contains("5d3325bd671735b4720e2ac7d232cedf9b4a8abf3953ff2247e17e54d9d134b5"))
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.checksumPattern(.stable)) == nil)
    }

    /// Neither channel's digest pattern reads the other train's manifest.
    @Test func theTwoChannelsDigestPatternsCannotReadEachOthersManifest() throws {
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgePreviewManifestWithDigests, pattern: try Self.checksumPattern(.stable)) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: longbridgeStableManifest, pattern: try Self.checksumPattern(.preview)) == nil)
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

    @Test func stableReadsVersionedSummariesFromTheOfficialRSS() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let (feed, expected) = try #require(Self.notes[.stable])
        #expect(recipe.source.absoluteString == "https://longbridge.com/en/changelog/rss.xml")
        #expect(recipe.resolvedSource(forVersion: expected) == recipe.source)
        #expect(recipe.resolvedSource(forVersion: nil) == recipe.source)

        let log = try #require(ChangelogService.parse(recipe, body: feed, version: expected))
        #expect(log.entries.map(\.version) == [expected, "1.1.2", "0.19.1"])
        let release = try #require(log.entries.first)
        #expect(release.title == "Community, Message Center, and watchlist import and export")
        #expect(release.date == "18 Nov 2026")
        #expect(release.items == [
            "Adds Community and a Message Center, watchlist import and export as CSV / Excel, and Related ETFs in Stock Detail.",
        ])
    }

    @Test func stableSkipsPreviewAndMismatchedItemLinks() throws {
        let recipe = try #require(Self.changelogs[.stable])
        let feed = longbridgeStableRSS
            .replacingOccurrences(of: "LongbridgeAI 1.8.0 ·", with: "Longbridge Pro 1.8.0 ·")
            .replacingOccurrences(of: "Longbridge Pro 1.2.0 ·", with: "Longbridge Pro 1.2.0-preview.1 ·")
            .replacingOccurrences(of: "#v1.2.0</link>", with: "#v1.2.0-preview.1</link>")
            .replacingOccurrences(of: "/longbridge-pro/v1.1#v1.1.2</link>",
                                  with: "/longbridge-pro/v1.1#v1.1.1</link>")
        let log = try #require(ChangelogService.parse(recipe, body: feed, version: "1.2.0"))
        #expect(log.entries.map(\.version) == ["0.19.1"])
    }

    /// Preview has no per-version page any more. Its notes come from the manifest's
    /// `release_notes.en`, read as a JSON string: the escapes resolve, the `**`
    /// around each bullet's label is dropped, and the `###` headings are not items.
    @Test func previewReadsTheManifestsNotesAsPlainChangeLines() throws {
        let recipe = try #require(Self.changelogs[.preview])
        let (manifest, expected) = try #require(Self.notes[.preview])

        #expect(recipe.structuredFormat == .longbridgeDesktopManifest)
        #expect(recipe.sourceTemplate == nil)
        #expect(recipe.mode == .json)

        let log = try #require(ChangelogService.parse(recipe, body: manifest))
        #expect(log.entries.count == 1)
        let entry = try #require(log.entries.first)
        #expect(entry.version == expected)
        #expect(entry.date == "2026-10-09")
        #expect(entry.items.count == 11)
        #expect(entry.items.first == "LongbridgeAI: Redesigned the reasoning process, making the AI's progress easy to follow and keeping answers focused.")
        #expect(entry.items.contains("Chart: Added \"Signals & Catalysts\" to the K-line chart, marking trading signals and catalyst events on the chart; open one to see the details or ask AI to analyze it, helping you quickly understand what drives a move."))
        #expect(entry.items.allSatisfy { !$0.contains("**") && !$0.contains("\\") })
        #expect(entry.items.allSatisfy { !$0.hasPrefix("#") && !$0.hasPrefix("- ") })
    }

    /// Each channel's recipe reads only its own document, and the two routes are
    /// keyed by bundle id. The RSS pattern accepts only stable Pro items and
    /// the Preview decoder reads its separate JSON manifest.
    @Test func eachChannelsChangelogRecipeRejectsTheOtherChannelsDocument() throws {
        let stable = try #require(Self.changelogs[.stable])
        let preview = try #require(Self.changelogs[.preview])
        let (stableFeed, _) = try #require(Self.notes[.stable])
        let (previewManifest, _) = try #require(Self.notes[.preview])

        #expect(ChangelogService.parse(stable, body: previewManifest) == nil,
                "the stable entry pattern must not read the preview manifest")
        #expect(ChangelogService.parse(preview, body: stableFeed) == nil,
                "the preview decoder must not read the stable RSS")

        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop.preview", channel: .preview)?
            .bundleID == "com.longbridge.app.desktop.preview")
        #expect(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.longbridge.app.desktop", channel: .stable)?
            .bundleID == "com.longbridge.app.desktop")
    }

    @Test func changelogCatalogProvidesAWebFallbackForStable() {
        #expect(ChangelogCatalog.url(forBundleID: "com.longbridge.app.desktop")?
            .absoluteString == "https://longbridge.com/desktop/release-notes/")
    }
}
