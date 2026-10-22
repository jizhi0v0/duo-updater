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
        // Anki: `apple`/`intel` rather than arch tokens, so the arm build reads as
        // arch-neutral and only the Intel one is recognised as foreign.
        (#"^anki-[0-9.]+-mac-(apple|intel)\.dmg$"#,
         ["anki-25.9-mac-apple.dmg", "anki-25.9-mac-intel.dmg"]),
        // Goose: an optional suffix, so the neutral and the Intel build both match.
        (#"^Goose(_intel_mac)?\.zip$"#, ["Goose.zip", "Goose_intel_mac.zip"]),
        // OpenLens: the same respin-tolerant `[0-9.\-]+` run KeePassXC uses.
        (#"^OpenLens-[0-9.\-]+-arm64\.dmg$"#,
         ["OpenLens-6.5.2-366-arm64.dmg", "OpenLens-6.5.2-367-arm64.dmg"]),
        // Flameshot / darktable: one dmg per architecture under one tag (v14.0.0,
        // release-5.6.1 — every stable release with a macOS build ships both).
        (#"^Flameshot-.+-macos-(arm64|intel)\.dmg$"#,
         ["Flameshot-14.0-macos-arm64.dmg", "Flameshot-14.0-macos-intel.dmg"]),
        (#"^darktable-[0-9.]+-(arm64|x86_64)\.dmg$"#,
         ["darktable-5.6.1-arm64.dmg", "darktable-5.6.1-x86_64.dmg"]),
        // magpie: one zip per architecture under every tag (v0.1.1084).
        (#"^magpie-darwin-(?:arm64|amd64)\.zip$"#,
         ["magpie-darwin-amd64.zip", "magpie-darwin-arm64.zip"]),
        // Lokii: one dmg per architecture, no version in the name (v0.1.1).
        (#"^Lokii-(?:arm64|x86_64)\.dmg$"#,
         ["Lokii-arm64.dmg", "Lokii-x86_64.dmg"]),
        // disktree: one zip per architecture under every tag with a macOS build
        // (v0.11.0's macOS zips, beside Windows zips the pattern must not take).
        (#"^disktree-[0-9]+\.[0-9]+\.[0-9]+-(?:aarch64|x86_64)-macos\.zip$"#,
         ["disktree-0.11.0-aarch64-macos.zip", "disktree-0.11.0-aarch64-windows.zip",
          "disktree-0.11.0-x86_64-macos.zip", "disktree-0.11.0-x86_64-windows.zip"]),
        // Cindy: four macOS dmgs per release, two editions × two arches
        // (v0.1.97, in the order GitHub listed them); each rule admits its own
        // edition's two.
        (#"^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-global\.dmg$"#,
         ["cindy-0.1.97-darwin-arm64-cn.dmg", "cindy-0.1.97-darwin-arm64-global.dmg",
          "cindy-0.1.97-darwin-x64-cn.dmg", "cindy-0.1.97-darwin-x64-global.dmg"]),
        (#"^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-cn\.dmg$"#,
         ["cindy-0.1.97-darwin-arm64-cn.dmg", "cindy-0.1.97-darwin-arm64-global.dmg",
          "cindy-0.1.97-darwin-x64-cn.dmg", "cindy-0.1.97-darwin-x64-global.dmg"]),
        // Audacity: arm64, universal and x86_64 dmgs under one tag, a universal
        // pkg beside them on some 3.x releases (Audacity-3.7.9 and
        // Audacity-4.0.1, macOS assets in the order GitHub listed them).
        (#"^audacity-macOS-3\.[0-9]+\.[0-9]+-(?:arm64|x86_64|universal)\.dmg$"#,
         ["audacity-macOS-3.7.9-arm64.dmg", "audacity-macOS-3.7.9-universal.dmg",
          "audacity-macOS-3.7.9-universal.pkg", "audacity-macOS-3.7.9-x86_64.dmg"]),
        (#"^audacity-macOS-4\.[0-9]+\.[0-9]+-(?:arm64|x86_64|universal)\.dmg$"#,
         ["audacity-macOS-4.0.1-arm64.dmg", "audacity-macOS-4.0.1-universal.dmg",
          "audacity-macOS-4.0.1-x86_64.dmg"]),
        // Plexo: one dmg per architecture beside the updater's zips and the
        // blockmaps (v1.0.0-rc.15's macOS assets, in the order GitHub listed them).
        (#"^plexo-[0-9][0-9A-Za-z.-]*-(?:arm64|x64)\.dmg$"#,
         ["plexo-1.0.0-rc.15-arm64-mac.zip", "plexo-1.0.0-rc.15-arm64-mac.zip.blockmap",
          "plexo-1.0.0-rc.15-arm64.dmg", "plexo-1.0.0-rc.15-arm64.dmg.blockmap",
          "plexo-1.0.0-rc.15-x64-mac.zip", "plexo-1.0.0-rc.15-x64-mac.zip.blockmap",
          "plexo-1.0.0-rc.15-x64.dmg", "plexo-1.0.0-rc.15-x64.dmg.blockmap"]),
        // Open Screen Sharing: one pkg beside the iOS ipa, the AltStore source,
        // the icon and `metadata.json` (v1.0.1's assets, in the order GitHub
        // listed them).
        (#"^OpenScreenSharing\.pkg$"#,
         ["altstore.json", "icon.png", "metadata.json", "OpenScreenSharing.ipa",
          "OpenScreenSharing.pkg"]),
        // RustGIS: one dmg per architecture beside the Linux/Windows packages
        // and the CLI tarballs (v0.1.0's assets, in the order GitHub listed them).
        (#"^RustGIS-[0-9][0-9A-Za-z.-]*-macos-(?:aarch64|x86_64)\.dmg$"#,
         ["rustgis-0.1.0-1.aarch64.rpm", "rustgis-0.1.0-1.x86_64.rpm",
          "RustGIS-0.1.0-linux-aarch64.AppImage", "RustGIS-0.1.0-linux-aarch64.tar.gz",
          "RustGIS-0.1.0-linux-x86_64.AppImage", "RustGIS-0.1.0-linux-x86_64.tar.gz",
          "RustGIS-0.1.0-macos-aarch64.dmg", "RustGIS-0.1.0-macos-x86_64.dmg",
          "RustGIS-0.1.0-windows-x86_64-portable.zip", "RustGIS-0.1.0-windows-x86_64-setup.exe",
          "RustGIS-0.1.0-windows-x86_64.msi", "RustGIS-0.1.0-windows-x86_64.msix",
          "rustgis-cli-0.1.0-macos-aarch64.tar.gz", "rustgis-cli-0.1.0-macos-x86_64.tar.gz",
          "rustgis_0.1.0_amd64.deb", "rustgis_0.1.0_arm64.deb", "SHA256SUMS"]),
        // Zettlr stable and beta: one dmg per architecture beside the Linux and
        // Windows packages (v4.8.0's and v4.0.0-beta.5's assets, in GitHub's order).
        (#"^Zettlr-[0-9]+(?:\.[0-9]+)+-(?:arm64|x64)\.dmg$"#,
         ["SHA256SUMS.txt", "Zettlr-4.8.0-aarch64.rpm", "Zettlr-4.8.0-amd64.deb",
          "Zettlr-4.8.0-arm64.AppImage", "Zettlr-4.8.0-arm64.deb", "Zettlr-4.8.0-arm64.dmg",
          "Zettlr-4.8.0-x64.dmg", "Zettlr-4.8.0-x64.exe", "Zettlr-4.8.0-x86_64.AppImage",
          "Zettlr-4.8.0-x86_64.rpm"]),
        (#"^Zettlr-[0-9]+(?:\.[0-9]+)+(?:-beta(?:\.[0-9]+)?)?-(?:arm64|x64)\.dmg$"#,
         ["SHA256SUMS.txt", "Zettlr-4.0.0-beta.5-aarch64.rpm", "Zettlr-4.0.0-beta.5-amd64.deb",
          "Zettlr-4.0.0-beta.5-arm64.AppImage", "Zettlr-4.0.0-beta.5-arm64.deb",
          "Zettlr-4.0.0-beta.5-arm64.dmg", "Zettlr-4.0.0-beta.5-x64.dmg",
          "Zettlr-4.0.0-beta.5-x64.exe", "Zettlr-4.0.0-beta.5-x86_64.AppImage",
          "Zettlr-4.0.0-beta.5-x86_64.rpm"]),
        // AstrLink: one dmg per architecture beside the Tauri updater's
        // `.app.tar.gz` archives and the Linux/Windows packages (v0.2.6's
        // assets, in the order GitHub listed them).
        (#"^AstrLink_[0-9][0-9A-Za-z.-]*_(?:aarch64|x64)\.dmg$"#,
         ["AstrLink-macOS-arm64.app.tar.gz", "AstrLink-macOS-arm64.app.tar.gz.sig",
          "AstrLink-macOS-x86_64.app.tar.gz", "AstrLink-macOS-x86_64.app.tar.gz.sig",
          "AstrLink_0.2.6_aarch64.dmg", "AstrLink_0.2.6_amd64.AppImage",
          "AstrLink_0.2.6_amd64.AppImage.sig", "AstrLink_0.2.6_amd64.deb",
          "AstrLink_0.2.6_x64-setup.exe", "AstrLink_0.2.6_x64-setup.exe.sig",
          "AstrLink_0.2.6_x64.dmg", "latest.json", "SHA256SUMS"]),
        // Hoppscotch: Cloud and Self-Host dmgs per architecture beside the
        // Tauri tar.gz archives and the Linux/Windows packages (v26.9.0-0's
        // assets, in the order GitHub listed them); only the Cloud dmgs match.
        (#"^Hoppscotch_mac_(?:aarch64|x64)\.dmg$"#,
         ["Hoppscotch_Cloud_win_x64_portable.zip", "Hoppscotch_linux_x64.AppImage",
          "Hoppscotch_linux_x64.deb", "Hoppscotch_mac_aarch64.dmg", "Hoppscotch_mac_aarch64.tar.gz",
          "Hoppscotch_mac_x64.dmg", "Hoppscotch_mac_x64.tar.gz", "Hoppscotch_SelfHost_linux_x64.AppImage",
          "Hoppscotch_SelfHost_linux_x64.deb", "Hoppscotch_SelfHost_mac_aarch64.dmg",
          "Hoppscotch_SelfHost_mac_aarch64.tar.gz", "Hoppscotch_SelfHost_mac_x64.dmg",
          "Hoppscotch_SelfHost_mac_x64.tar.gz", "Hoppscotch_SelfHost_win_x64.msi",
          "Hoppscotch_SelfHost_win_x64_portable.zip", "Hoppscotch_win_x64.msi"]),
    ]

    /// Registry patterns whose alternation chooses between TAGS rather than
    /// between the assets of ONE release.
    ///
    /// `multiCandidatePatternsAreAllCovered` is deliberately syntactic — any `|`
    /// or `\-` run counts — and that default is the right one: a pattern with a
    /// choice to make has to prove the choice is order-independent. But a `|` is
    /// not always a choice within a release. CotEditor's beta rule accepts both
    /// phases of its one prerelease train (`-beta[.N]`, `-rc[.N]`) plus the plain
    /// release it graduates into, and this vendor publishes exactly ONE asset per
    /// release, `CotEditor_<tag>.dmg` (measured over the newest 100, 2026-09-06).
    /// The branches therefore span tags, and no release's asset list can present
    /// two candidates.
    ///
    /// **Why not just add it to `multiCandidateCases`.** Every entry in that table
    /// is a real co-occurrence — KeePassXC's respins, Goose's neutral/Intel pair,
    /// two architectures under one tag — and its doc says so. Putting CotEditor
    /// there would mean writing a listing this vendor does not publish under a
    /// table that claims its listings are real, which is the fixture-wider-than-
    /// the-vendor failure this repo keeps re-learning. The exemption is explicit
    /// and carries its reason instead.
    ///
    /// **It is not a free pass.** `names` is still exercised by
    /// `crossTagAlternationsStillSelectIndependentlyOfOrder` below — labelled for
    /// what it is, a shape the vendor does not ship, used only to drive the
    /// selector — and `everyCrossTagExemptionIsStillEarned` fails the build on an
    /// exemption that no longer matches an ambiguous registry pattern, the way
    /// `mayLookAlike` does and `mayBeBlank` (#271) does not.
    static let crossTagAlternations:
        [(pattern: String, names: [String], reason: String)] = [
        (#"^CotEditor_[0-9.]+(?:-beta(?:\.[0-9]+)?|-rc(?:\.[0-9]+)?)?\.dmg$"#,
         // Not a listing: these two tags are two different releases, and each
         // release carries only its own dmg. Here to drive the selector.
         ["CotEditor_7.1.0-rc.dmg", "CotEditor_7.1.0-beta.6.dmg"],
         "one prerelease train with two phases (-beta[.N] -> -rc[.N] -> the plain release); "
             + "one asset per release, so the branches select between tags and never within one"),
        (#"^Flycut(?:\.app)?(?:\.[0-9][0-9A-Za-z.-]*)?\.(?:zip|dmg)$"#,
         // Not a listing: 1.8 … 1.9.6 each carry one zip (no dmg); release.yml
         // on master uploads only `Flycut.dmg`. Here to drive the selector.
         ["Flycut.1.9.6.zip", "Flycut.dmg"],
         "zip-era releases (1.8 ... 1.9.6, one zip each) and the release.yml era (one Flycut.dmg); "
             + "one asset per release, so the branches select between tags and never within one"),
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
            .union(Self.crossTagAlternations.map(\.pattern))
        for pattern in Self.ambiguousRegistryPatterns.sorted() {
            #expect(covered.contains(pattern),
                    "\(pattern) can match several assets from one release but no order-independence case covers it")
        }
    }

    /// The registry patterns the gate above judges, factored out so the gate and
    /// the staleness check below read the SAME set rather than two copies of the
    /// same filter.
    static var ambiguousRegistryPatterns: Set<String> {
        Set(GitHubReleaseRegistry.rules.compactMap(\.installAssetPattern)
            .filter { $0.contains("|") || $0.contains(#"\-"#) })
    }

    /// An exemption that no longer matches anything is a permanent free pass for
    /// whatever drifts into its place — `mayLookAlike`'s rule, and the hole
    /// `mayBeBlank` still has (#271). So each one must still name a live,
    /// still-ambiguous registry pattern, must not double as a `multiCandidateCases`
    /// entry (the two tables say opposite things), and must carry a reason.
    @Test func everyCrossTagExemptionIsStillEarned() {
        let live = Self.ambiguousRegistryPatterns
        let realCoOccurrences = Set(Self.multiCandidateCases.map(\.pattern))
        for entry in Self.crossTagAlternations {
            #expect(live.contains(entry.pattern),
                    "\(entry.pattern) is exempted as a cross-tag alternation but no registry rule carries it (or it is no longer ambiguous) — drop the exemption")
            #expect(!realCoOccurrences.contains(entry.pattern),
                    "\(entry.pattern) is in both tables: it cannot both admit two assets from one release and not")
            #expect(!entry.reason.isEmpty, "\(entry.pattern) is exempted with no reason")
        }
    }

    /// The exemption buys the pattern out of `multiCandidateCases`, not out of the
    /// property. Same assertion as `selectionIsIndependentOfListOrder` — if two
    /// matching names ever DID land in one release, selection must not depend on
    /// the order GitHub listed them in.
    @Test(arguments: crossTagAlternations)
    func crossTagAlternationsStillSelectIndependentlyOfOrder(
        testCase: (pattern: String, names: [String], reason: String)
    ) {
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
            #expect(pick(testCase.names) == pick(testCase.names.reversed()),
                    "\(testCase.pattern) on \(arch) is order-dependent")
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
