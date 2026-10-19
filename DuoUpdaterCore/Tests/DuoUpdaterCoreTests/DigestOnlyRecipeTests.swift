import Foundation
import Testing
@testable import DuoUpdaterCore

/// The three rules this route was opened for, against the asset names their
/// repositories actually published (every stable release with a digest, read
/// from the GitHub API 2026-10-02 — see `docs/app-audits/org-alacritty.md`),
/// and Lokii, added since (both releases, 2026-10-07 — `docs/app-audits/com-lokii-app.md`),
/// and disktree (its two newest releases, 2026-10-12 — `docs/app-audits/io-github-tobi-disktree.md`),
/// and Obelus (its two newest releases, 2026-10-19 — `docs/app-audits/io-github-obelus-editor-obelus.md`).
@Suite struct DigestOnlyRecipeTests {

    private static let expected: [String: [[String]]] = [
        "org.alacritty": [
            ["Alacritty-v0.17.0.dmg", "Alacritty-v0.17.0-rc2.dmg"],
            ["Alacritty-v0.16.1.dmg", "alacritty.1.gz", "Alacritty-v0.16.1-portable.exe"],
        ],
        "org.flameshot.Flameshot": [
            ["Flameshot-14.0-macos-arm64.dmg", "Flameshot-14.0-macos-arm64.dmg.sha256sum",
             "Flameshot-14.0-macos-intel.dmg", "Flameshot-14.0-macos-intel.dmg.sha256sum",
             "flameshot-14.0.0-win64.zip"],
            ["Flameshot-13.3.0-artifact-macos-arm64.dmg", "Flameshot-13.3.0-artifact-macos-intel.dmg"],
        ],
        "org.darktable": [
            ["darktable-5.6.1-arm64.dmg", "darktable-5.6.1-x86_64.dmg", "darktable-5.6.1.tar.xz"],
            ["darktable-5.2.1-arm64-13.5.dmg", "darktable-5.2.1-arm64.dmg", "darktable-5.2.1-x86_64.dmg"],
            ["darktable-5.4.0-arm64.dmg"],
        ],
        "com.lokii.app": [
            ["Lokii-arm64.dmg", "Lokii-x86_64.dmg"],
            ["Lokii-arm64.dmg", "Lokii-x86_64.dmg"],
        ],
        "io.github.tobi.disktree": [
            ["disktree-0.11.0-aarch64-linux.tar.gz", "disktree-0.11.0-aarch64-linux.tar.gz.sha256",
             "disktree-0.11.0-aarch64-macos.zip", "disktree-0.11.0-aarch64-macos.zip.sha256",
             "disktree-0.11.0-aarch64-windows.zip", "disktree-0.11.0-aarch64-windows.zip.sha256",
             "disktree-0.11.0-x86_64-linux.tar.gz", "disktree-0.11.0-x86_64-linux.tar.gz.sha256",
             "disktree-0.11.0-x86_64-macos.zip", "disktree-0.11.0-x86_64-macos.zip.sha256",
             "disktree-0.11.0-x86_64-windows.zip", "disktree-0.11.0-x86_64-windows.zip.sha256"],
            ["disktree-0.10.1-aarch64-linux.tar.gz", "disktree-0.10.1-aarch64-linux.tar.gz.sha256",
             "disktree-0.10.1-aarch64-macos.zip", "disktree-0.10.1-aarch64-macos.zip.sha256",
             "disktree-0.10.1-aarch64-windows.zip", "disktree-0.10.1-aarch64-windows.zip.sha256",
             "disktree-0.10.1-x86_64-linux.tar.gz", "disktree-0.10.1-x86_64-linux.tar.gz.sha256",
             "disktree-0.10.1-x86_64-macos.zip", "disktree-0.10.1-x86_64-macos.zip.sha256",
             "disktree-0.10.1-x86_64-windows.zip", "disktree-0.10.1-x86_64-windows.zip.sha256"],
        ],
        "io.github.obelus-editor.obelus": [
            ["ob-0.16.0-aarch64-pc-windows-msvc.zip", "ob-0.16.0-aarch64-unknown-linux-gnu.tar.xz",
             "ob-0.16.0-aarch64-unknown-linux-musl.tar.xz", "ob-0.16.0-universal2-apple-darwin.tar.xz",
             "ob-0.16.0-x86_64-pc-windows-msvc.zip", "ob-0.16.0-x86_64-unknown-linux-gnu.tar.xz",
             "ob-0.16.0-x86_64-unknown-linux-musl.tar.xz", "obelus-0.16.0-1.aarch64.rpm",
             "obelus-0.16.0-1.x86_64.rpm", "Obelus-0.16.0-aarch64-pc-windows-msvc.msi",
             "Obelus-0.16.0-universal2-apple-darwin.app.zip", "Obelus-0.16.0-x86_64-pc-windows-msvc.msi",
             "obelus-gui-0.16.0-1.aarch64.rpm", "obelus-gui-0.16.0-1.x86_64.rpm", "obelus-gui_0.16.0-1_amd64.deb",
             "obelus-gui_0.16.0-1_arm64.deb", "obelus-terminal.desktop", "obelus.desktop", "obelus.svg",
             "obelus.toml.tpl", "obelus_0.16.0-1_amd64.deb", "obelus_0.16.0-1_arm64.deb",
             "obg-0.16.0-aarch64-pc-windows-msvc.zip", "obg-0.16.0-aarch64-unknown-linux-gnu.tar.xz",
             "obg-0.16.0-aarch64.AppImage", "obg-0.16.0-universal2-apple-darwin.tar.xz",
             "obg-0.16.0-x86_64-pc-windows-msvc.zip", "obg-0.16.0-x86_64-unknown-linux-gnu.tar.xz",
             "obg-0.16.0-x86_64.AppImage", "SHA256SUMS"],
            ["ob-0.15.0-aarch64-pc-windows-msvc.zip", "ob-0.15.0-aarch64-unknown-linux-gnu.tar.xz",
             "ob-0.15.0-aarch64-unknown-linux-musl.tar.xz", "ob-0.15.0-universal2-apple-darwin.tar.xz",
             "ob-0.15.0-x86_64-pc-windows-msvc.zip", "ob-0.15.0-x86_64-unknown-linux-gnu.tar.xz",
             "ob-0.15.0-x86_64-unknown-linux-musl.tar.xz", "obelus-0.15.0-1.aarch64.rpm",
             "obelus-0.15.0-1.x86_64.rpm", "Obelus-0.15.0-aarch64-pc-windows-msvc.msi",
             "Obelus-0.15.0-universal2-apple-darwin.app.zip", "Obelus-0.15.0-x86_64-pc-windows-msvc.msi",
             "obelus-gui-0.15.0-1.aarch64.rpm", "obelus-gui-0.15.0-1.x86_64.rpm", "obelus-gui_0.15.0-1_amd64.deb",
             "obelus-gui_0.15.0-1_arm64.deb", "obelus-terminal.desktop", "obelus.desktop", "obelus.svg",
             "obelus.toml.tpl", "obelus_0.15.0-1_amd64.deb", "obelus_0.15.0-1_arm64.deb",
             "obg-0.15.0-aarch64-pc-windows-msvc.zip", "obg-0.15.0-aarch64-unknown-linux-gnu.tar.xz",
             "obg-0.15.0-aarch64.AppImage", "obg-0.15.0-universal2-apple-darwin.tar.xz",
             "obg-0.15.0-x86_64-pc-windows-msvc.zip", "obg-0.15.0-x86_64-unknown-linux-gnu.tar.xz",
             "obg-0.15.0-x86_64.AppImage", "SHA256SUMS"],
        ],
    ]

    private func rule(_ bundleID: String) -> GitHubReleaseRule? {
        GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID }
    }

    /// Presence anchor, and the shape every digest-only rule must have: an asset
    /// pattern, a format the bundle gates can read (never `.pkg`), stable only.
    @Test func everyDigestOnlyRuleIsADmgZipOrTarballOnTheStableChannel() {
        let digestOnly = GitHubReleaseRegistry.rules.filter { $0.installTrust == .publishedDigestOnly }
        #expect(Set(digestOnly.map(\.bundleID)) == Set(Self.expected.keys))
        for rule in digestOnly {
            #expect(rule.installAssetPattern != nil, "\(rule.bundleID)")
            #expect(rule.installerKind != nil && rule.installerKind != .pkg, "\(rule.bundleID)")
            #expect(rule.channel == .stable && !rule.usePrereleases, "\(rule.bundleID)")
        }
    }

    /// Exactly one arm64-runnable dmg per release, and never a checksum file,
    /// a prerelease's, or an OS-specific extra.
    @Test func eachPatternPicksTheOneDmgForThisMac() throws {
        let picks: [String: [String]] = [
            "org.alacritty": ["Alacritty-v0.17.0.dmg", "Alacritty-v0.16.1.dmg"],
            "org.flameshot.Flameshot": ["Flameshot-14.0-macos-arm64.dmg", "Flameshot-13.3.0-artifact-macos-arm64.dmg"],
            "org.darktable": ["darktable-5.6.1-arm64.dmg", "darktable-5.2.1-arm64.dmg", "darktable-5.4.0-arm64.dmg"],
            "com.lokii.app": ["Lokii-arm64.dmg", "Lokii-arm64.dmg"],
            "io.github.tobi.disktree": ["disktree-0.11.0-aarch64-macos.zip", "disktree-0.10.1-aarch64-macos.zip"],
            "io.github.obelus-editor.obelus": ["Obelus-0.16.0-universal2-apple-darwin.app.zip",
                                               "Obelus-0.15.0-universal2-apple-darwin.app.zip"],
        ]
        for (bundleID, releases) in Self.expected {
            let pattern = try #require(rule(bundleID)?.installAssetPattern, "\(bundleID)")
            for (index, names) in releases.enumerated() {
                let assets = names.map { (name: $0, url: URL(string: "https://github.com/x/y/\($0)")!, size: Int64?.none) }
                let picked = GitHubReleaseRule.installableAsset(
                    from: assets, matching: pattern, preferring: .arm64, allowingIntelTranslation: false)
                #expect(picked?.url.lastPathComponent == picks[bundleID]?[index], "\(bundleID) release \(index)")
                // The rc asset ships under a prerelease tag, which `/releases/latest`
                // never returns; the pattern must still not prefer it. `-rc`, not
                // `rc`: disktree's `aarch64` spells it too.
                #expect(!(picked?.url.lastPathComponent.contains("-rc") ?? false))
            }
        }
    }
}
