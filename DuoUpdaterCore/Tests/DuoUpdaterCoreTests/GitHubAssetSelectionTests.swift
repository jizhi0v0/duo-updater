import Testing
import Foundation
@testable import DuoUpdaterCore

/// Asset selection for GitHub-sourced one-click installs. RustDesk's release
/// ships ~22 assets across every platform/arch; the rule must pick exactly the
/// macOS arm64 dmg and nothing else (a stray .deb/.exe/x86_64 build would fail
/// the install or target the wrong machine).
struct GitHubAssetSelectionTests {

    /// The real 1.4.6 asset filenames (trimmed to the macOS-relevant subset plus
    /// a few decoys), each with a download URL.
    private let assets: [(name: String, url: URL)] = [
        "rustdesk-1.4.6-0-x86_64.pkg.tar.zst",
        "rustdesk-1.4.6-0.aarch64.rpm",
        "rustdesk-1.4.6-aarch64.deb",
        "rustdesk-1.4.6-aarch64.dmg",
        "rustdesk-1.4.6-x86_64.dmg",
        "rustdesk-1.4.6-x86_64.exe",
        "rustdesk-1.4.6-aarch64.AppImage",
    ].map { ($0, URL(string: "https://github.com/rustdesk/rustdesk/releases/download/1.4.6/\($0)")!) }

    @Test func picksArm64Dmg() {
        let url = GitHubReleaseRule.installableAsset(from: assets, matching: #"aarch64\.dmg$"#)
        #expect(url?.lastPathComponent == "rustdesk-1.4.6-aarch64.dmg")
    }

    @Test func doesNotPickIntelOrLinuxAssets() {
        let url = GitHubReleaseRule.installableAsset(from: assets, matching: #"aarch64\.dmg$"#)
        #expect(url?.lastPathComponent.contains("x86_64") == false)
        #expect(url?.pathExtension == "dmg")
    }

    @Test func anchorRejectsAarch64NonDmg() {
        // The `$` anchor must not let ".dmg" match inside a longer name, and must
        // not let the arm64 .deb/.AppImage through.
        let onlyNonDmg: [(name: String, url: URL)] = [
            ("rustdesk-1.4.6-aarch64.deb", URL(string: "https://example.com/a.deb")!),
            ("rustdesk-1.4.6-aarch64.AppImage", URL(string: "https://example.com/a.img")!),
        ]
        #expect(GitHubReleaseRule.installableAsset(from: onlyNonDmg, matching: #"aarch64\.dmg$"#) == nil)
    }

    @Test func noMatchReturnsNilForDetectionOnly() {
        // A repo with no macOS arm64 dmg → nil → rule stays detection-only.
        let linuxOnly: [(name: String, url: URL)] = [
            ("app-1.0-x86_64.AppImage", URL(string: "https://example.com/x.img")!),
        ]
        #expect(GitHubReleaseRule.installableAsset(from: linuxOnly, matching: #"aarch64\.dmg$"#) == nil)
    }

    @Test func rustDeskRuleIsConfiguredForInstall() {
        let rule = GitHubReleaseRegistry.rules.first { $0.bundleID == "com.carriez.rustdesk" }
        #expect(rule?.installAssetPattern == #"aarch64\.dmg$"#)
        #expect(rule?.installerKind == .dmg)
    }
}
