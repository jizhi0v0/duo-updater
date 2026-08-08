import Testing
import Foundation
@testable import DuoUpdaterCore

/// Asset selection for GitHub-sourced one-click installs. RustDesk's release
/// ships ~22 assets across every platform/arch; the rule must pick exactly the
/// macOS arm64 dmg and nothing else (a stray .deb/.exe/x86_64 build would fail
/// the install or target the wrong machine).
struct GitHubAssetSelectionTests {

    /// The real 1.4.6 asset filenames (trimmed to the macOS-relevant subset plus
    /// a few decoys), each with a download URL and declared size.
    private let assets: [(name: String, url: URL, size: Int64?)] = [
        "rustdesk-1.4.6-0-x86_64.pkg.tar.zst",
        "rustdesk-1.4.6-0.aarch64.rpm",
        "rustdesk-1.4.6-aarch64.deb",
        "rustdesk-1.4.6-aarch64.dmg",
        "rustdesk-1.4.6-x86_64.dmg",
        "rustdesk-1.4.6-x86_64.exe",
        "rustdesk-1.4.6-aarch64.AppImage",
    ].enumerated().map { index, name in
        (name, URL(string: "https://github.com/rustdesk/rustdesk/releases/download/1.4.6/\(name)")!, Int64(index) * 1000)
    }

    @Test func picksArm64Dmg() {
        let asset = GitHubReleaseRule.installableAsset(from: assets, matching: #"aarch64\.dmg$"#)
        #expect(asset?.url.lastPathComponent == "rustdesk-1.4.6-aarch64.dmg")
        // The chosen asset's declared size rides along, for "Update All" ordering.
        #expect(asset?.size == 3000)
    }

    @Test func doesNotPickIntelOrLinuxAssets() {
        let asset = GitHubReleaseRule.installableAsset(from: assets, matching: #"aarch64\.dmg$"#)
        #expect(asset?.url.lastPathComponent.contains("x86_64") == false)
        #expect(asset?.url.pathExtension == "dmg")
    }

    @Test func anchorRejectsAarch64NonDmg() {
        // The `$` anchor must not let ".dmg" match inside a longer name, and must
        // not let the arm64 .deb/.AppImage through.
        let onlyNonDmg: [(name: String, url: URL, size: Int64?)] = [
            ("rustdesk-1.4.6-aarch64.deb", URL(string: "https://example.com/a.deb")!, nil),
            ("rustdesk-1.4.6-aarch64.AppImage", URL(string: "https://example.com/a.img")!, nil),
        ]
        #expect(GitHubReleaseRule.installableAsset(from: onlyNonDmg, matching: #"aarch64\.dmg$"#) == nil)
    }

    @Test func noMatchReturnsNilForDetectionOnly() {
        // A repo with no macOS arm64 dmg → nil → rule stays detection-only.
        let linuxOnly: [(name: String, url: URL, size: Int64?)] = [
            ("app-1.0-x86_64.AppImage", URL(string: "https://example.com/x.img")!, 42),
        ]
        #expect(GitHubReleaseRule.installableAsset(from: linuxOnly, matching: #"aarch64\.dmg$"#) == nil)
    }

    @Test func rustDeskRuleIsConfiguredForInstall() {
        let rule = GitHubReleaseRegistry.rules.first { $0.bundleID == "com.carriez.rustdesk" }
        #expect(rule?.installAssetPattern == #"^rustdesk-[0-9.]+-aarch64\.dmg$"#)
        #expect(rule?.installerKind == .dmg)
    }

    /// The fully-anchored RustDesk pattern picks the canonical arm64 dmg even when
    /// a flavored arm64 dmg (e.g. a future `-sciter` build) is listed first — the
    /// old suffix-only `aarch64\.dmg$` would have let `…-aarch64-sciter.dmg`
    /// through by position. (`-sciter.dmg` ends in `sciter.dmg`, not `aarch64.dmg`,
    /// so even the suffix pattern is safe today — but anchoring removes the doubt.)
    @Test func anchoredRustDeskPatternPicksCanonicalArm64Dmg() {
        let pattern = #"^rustdesk-[0-9.]+-aarch64\.dmg$"#
        let withFlavor: [(name: String, url: URL, size: Int64?)] = [
            "rustdesk-1.4.6-aarch64-sciter.dmg",
            "rustdesk-1.4.6-aarch64.dmg",
        ].enumerated().map { index, name in
            (name, URL(string: "https://example.com/\(name)")!, Int64(index))
        }
        let asset = GitHubReleaseRule.installableAsset(from: withFlavor, matching: pattern)
        #expect(asset?.url.lastPathComponent == "rustdesk-1.4.6-aarch64.dmg")
        #expect(asset?.size == 1)  // the size of the CHOSEN asset, not the decoy
        // And it still picks the real asset out of the full release set.
        #expect(GitHubReleaseRule.installableAsset(from: assets, matching: pattern)?
            .url.lastPathComponent == "rustdesk-1.4.6-aarch64.dmg")
    }

    /// Stats ships exactly one asset per release, `Stats.dmg`. Verified against the
    /// real v3.0.10 dmg on 2026-08-08: `Stats.app` at the root, bundle id
    /// eu.exelban.Stats, notarized Developer ID build from Team RP2S87B72W matching
    /// the installed copy, and a `CFBundleShortVersionString` equal to the tag.
    @Test func statsRuleIsConfiguredForInstall() {
        let rule = GitHubReleaseRegistry.rules.first { $0.bundleID == "eu.exelban.Stats" }
        #expect(rule?.installAssetPattern == #"^Stats\.dmg$"#)
        #expect(rule?.installerKind == .dmg)
        let assets: [(name: String, url: URL, size: Int64?)] = [
            ("Stats.dmg", URL(string: "https://github.com/exelban/stats/releases/download/v3.0.10/Stats.dmg")!, 8_000_000)
        ]
        #expect(GitHubReleaseRule.installableAsset(from: assets, matching: #"^Stats\.dmg$"#) != nil)
    }
}
