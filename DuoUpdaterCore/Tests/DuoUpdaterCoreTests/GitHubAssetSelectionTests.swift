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

    // MARK: - Order independence (issue #80)

    /// The registry patterns that can genuinely admit more than one asset from a
    /// single release, each with a real listing for that release.
    ///
    /// Kept as one table so the property test below and the coverage check below
    /// that read the same set — a case added here is exercised AND counted as
    /// covered, and neither can drift from the other.
    static let multiCandidateCases: [(pattern: String, names: [String])] = [
        // KeePassXC: a respun release keeps both dmgs under the one tag.
        (#"^KeePassXC-[0-9.\-]+-arm64\.dmg$"#,
         ["KeePassXC-2.7.11-1-arm64.dmg", "KeePassXC-2.7.11-2-arm64.dmg",
          "KeePassXC-2.7.11-arm64.dmg", "KeePassXC-2.7.11-x86_64.dmg"]),
        // OpenCode / OpenChamber: one alternation matching both architectures.
        (#"^opencode-desktop-mac-(?:arm64|x64)\.dmg$"#,
         ["opencode-desktop-mac-arm64.dmg", "opencode-desktop-mac-x64.dmg"]),
        (#"^OpenChamber-[0-9.]+-mac-(?:arm64|x64)\.dmg$"#,
         ["OpenChamber-1.4.0-mac-arm64.dmg", "OpenChamber-1.4.0-mac-x64.dmg"]),
        // VSCodium Insiders: same alternation shape, real 1.126.04518-insider
        // filenames (verified 2026-08-27 against the live release).
        (#"^VSCodium-darwin-(?:arm64|x64)-[0-9.]+-insider\.zip$"#,
         ["VSCodium-darwin-arm64-1.126.04518-insider.zip", "VSCodium-darwin-x64-1.126.04518-insider.zip"]),
        // Anki: `apple`/`intel` rather than arch tokens, so the arm build reads as
        // arch-neutral and only the Intel one is recognised as foreign.
        (#"^anki-[0-9.]+-mac-(apple|intel)\.dmg$"#,
         ["anki-25.9-mac-apple.dmg", "anki-25.9-mac-intel.dmg"]),
        // Goose: an optional suffix, so the neutral and the Intel build both match.
        (#"^Goose(_intel_mac)?\.zip$"#, ["Goose.zip", "Goose_intel_mac.zip"]),
        // OpenLens: the same respin-tolerant `[0-9.\-]+` run KeePassXC uses.
        (#"^OpenLens-[0-9.\-]+-arm64\.dmg$"#,
         ["OpenLens-6.5.2-366-arm64.dmg", "OpenLens-6.5.2-367-arm64.dmg"]),
    ]

    /// Selection must not depend on the order GitHub happens to list assets in.
    ///
    /// This is the property the `-2`-loses-to-`-1` respin bug violated, stated
    /// directly instead of through one example: whatever `installableAsset`
    /// returns for a list it must also return for that list reversed, on either
    /// architecture. Reversal is enough to catch positional selection — a
    /// `first(where:)` over a tier holding two admissible candidates flips its
    /// answer under it, and a comparison-based selector cannot.
    @Test(arguments: multiCandidateCases)
    func selectionIsIndependentOfListOrder(testCase: (pattern: String, names: [String])) {
        func assets(_ names: [String]) -> [(name: String, url: URL, size: Int64?)] {
            names.map { (name: $0, url: URL(string: "https://example.invalid/\($0)")!,
                         size: Int64?.none) }
        }
        for arch in [HostArch.arm64, HostArch.x86_64] {
            func pick(_ names: [String]) -> String? {
                GitHubReleaseRule.installableAsset(
                    from: assets(names), matching: testCase.pattern, preferring: arch,
                    allowingIntelTranslation: true)?.url.lastPathComponent
            }
            let forward = pick(testCase.names)
            let reversed = pick(testCase.names.reversed())
            #expect(forward == reversed,
                    "\(testCase.pattern) on \(arch) picked \(forward ?? "nil") forwards and \(reversed ?? "nil") reversed")
        }
    }

    /// Every registry pattern with something to decide is in `multiCandidateCases`.
    ///
    /// Derived from the registry rather than hand-listed, for the reason
    /// `VendorProbeRecipe.localReads` gives: a rule whose pattern carries an
    /// alternation or a respin-tolerant `\-` run is one where selection has a
    /// choice to make, and adding such a rule must fail here rather than quietly
    /// skip the property above.
    @Test func multiCandidatePatternsAreAllCovered() {
        let covered = Set(Self.multiCandidateCases.map(\.pattern))
        let ambiguous = Set(
            GitHubReleaseRegistry.rules.compactMap(\.installAssetPattern)
                .filter { $0.contains("|") || $0.contains(#"\-"#) })
        for pattern in ambiguous.sorted() {
            #expect(covered.contains(pattern),
                    "\(pattern) can match several assets from one release but no order-independence case covers it")
        }
    }

    /// The respin case itself, end to end: the artifact chosen is the highest
    /// respin, not the first-listed one.
    @Test func respinBeatsTheOriginalRegardlessOfListing() {
        func picked(_ names: [String]) -> String? {
            GitHubReleaseRule.installableAsset(
                from: names.map { (name: $0, url: URL(string: "https://example.invalid/\($0)")!,
                                   size: Int64?.none) },
                matching: #"^KeePassXC-[0-9.\-]+-arm64\.dmg$"#, preferring: .arm64)?
                .url.lastPathComponent
        }
        #expect(picked(["KeePassXC-2.7.11-arm64.dmg", "KeePassXC-2.7.11-1-arm64.dmg"])
                == "KeePassXC-2.7.11-1-arm64.dmg")
        #expect(picked(["KeePassXC-2.7.11-1-arm64.dmg", "KeePassXC-2.7.11-2-arm64.dmg"])
                == "KeePassXC-2.7.11-2-arm64.dmg")
        // Numeric, not alphabetical: a string sort reads `-10-` as older than `-9-`.
        #expect(picked(["KeePassXC-2.7.11-9-arm64.dmg", "KeePassXC-2.7.11-10-arm64.dmg"])
                == "KeePassXC-2.7.11-10-arm64.dmg")
    }
}
