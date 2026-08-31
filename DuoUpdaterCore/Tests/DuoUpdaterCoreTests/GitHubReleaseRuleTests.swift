import Testing
import Foundation
@testable import DuoUpdaterCore

// Each rule's versionPattern is applied to a release `tag_name` exactly like the
// pure helper VendorProbeRecipe.extractVersion (capture group 1, else whole
// match). These fixtures pin the pattern against the REAL tag formats observed
// on each repo, so a future pattern edit that breaks extraction fails loudly.

private func rule(_ bundleID: String) -> GitHubReleaseRule {
    // Reported as a failed expectation rather than a crash: a deleted registry
    // entry should fail the test that covers it, not take the whole suite down.
    guard let match = GitHubReleaseRegistry.rules.first(where: { $0.bundleID == bundleID })
    else {
        Issue.record("no GitHubReleaseRule for \(bundleID)")
        return GitHubReleaseRule(bundleID: bundleID, owner: "", repo: "")
    }
    return match
}

private func extract(_ tag: String, _ bundleID: String) -> String? {
    VendorProbeRecipe.extractVersion(from: tag, pattern: rule(bundleID).versionPattern)
}

@Test func statsRuleExtractsVPrefixedTag() {
    #expect(extract("v2.12.16", "eu.exelban.Stats") == "2.12.16")
}

@Test func dbeaverRuleExtractsBareTag() {
    #expect(extract("26.1.0", "org.jkiss.dbeaver.core.product") == "26.1.0")
    // One-click pins the aarch64 asset: the release publishes an x86_64 dmg beside
    // it, and a looser pattern could hand an Intel build to an Apple Silicon Mac.
    let pattern = try! #require(rule("org.jkiss.dbeaver.core.product").installAssetPattern)
    #expect("dbeaver-ce-26.1.4-macos-aarch64.dmg".range(of: pattern, options: .regularExpression) != nil)
    #expect("dbeaver-ce-26.1.4-macos-x86_64.dmg".range(of: pattern, options: .regularExpression) == nil)
}

@Test func beekeeperRuleExtractsVPrefixedTag() {
    #expect(extract("v5.8.1", "io.beekeeperstudio.desktop") == "5.8.1")
}

@Test func heliumRuleReadsBareTagsAndPinsTheArm64Dmg() {
    #expect(extract("0.16.2.1", "net.imput.helium") == "0.16.2.1")
    #expect(extract("v0.16.2.1", "net.imput.helium") == nil)
    let pattern = try! #require(rule("net.imput.helium").installAssetPattern)
    #expect("helium_0.16.2.1_arm64-macos.dmg".range(of: pattern, options: .regularExpression) != nil)
    #expect("helium_0.16.2.1_x86_64-macos.dmg".range(of: pattern, options: .regularExpression) == nil)
    #expect("0.15.4.1-arm64.delta".range(of: pattern, options: .regularExpression) == nil)
    #expect(rule("net.imput.helium").slug == "imputnet/helium-macos")
    #expect(rule("net.imput.helium").installerKind == .dmg)
}

@Test func claudeStatusBarRuleReadsVPrefixedTagsAndTheVersionlessDmg() {
    #expect(extract("v0.4.4", "com.local.claudestatusbar") == "0.4.4")
    #expect(extract("v0.4.4-beta.1", "com.local.claudestatusbar") == nil)
    let pattern = try! #require(rule("com.local.claudestatusbar").installAssetPattern)
    #expect("ClaudeStatusBar.dmg".range(of: pattern, options: .regularExpression) != nil)
    #expect("ClaudeStatusBar.zip".range(of: pattern, options: .regularExpression) == nil)
    #expect(rule("com.local.claudestatusbar").slug == "m1ckc3s/claude-status-bar")
    #expect(rule("com.local.claudestatusbar").installerKind == .dmg)
}

@Test func claudeDevtoolsRulePinsTheArm64Dmg() {
    #expect(extract("v0.5.0", "com.claudecode.context") == "0.5.0")
    #expect(extract("v0.5.0-rc.1", "com.claudecode.context") == nil)
    let pattern = try! #require(rule("com.claudecode.context").installAssetPattern)
    #expect("claude-devtools-0.5.0-arm64.dmg".range(of: pattern, options: .regularExpression) != nil)
    #expect("claude-devtools-0.5.0-x64.dmg".range(of: pattern, options: .regularExpression) == nil)
    #expect("claude-devtools-0.5.0-arm64.zip".range(of: pattern, options: .regularExpression) == nil)
    #expect(rule("com.claudecode.context").slug == "matt1398/claude-devtools")
    #expect(rule("com.claudecode.context").installerKind == .dmg)
}

@Test func insomniaRuleMatchesCoreTagOnly() {
    // Captures the desktop version from a stable core@ tag…
    #expect(extract("core@12.6.0", "com.insomnia.app") == "12.6.0")
    // …and ignores sibling monorepo packages (no capture → skipped by the source).
    #expect(extract("lib@3.0.0", "com.insomnia.app") == nil)
    #expect(extract("inso@11.0.0", "com.insomnia.app") == nil)
    // The `$` anchor rejects PRERELEASE tags so the stable rule never serves a beta
    // as if it were stable — the cross-channel push bug. (A 12.6.0 stable install
    // was being offered "13.0.0", stripped out of `core@13.0.0-beta.0`.)
    #expect(extract("core@13.0.0-beta.0", "com.insomnia.app") == nil)
    #expect(extract("core@12.5.1-alpha.0", "com.insomnia.app") == nil)
    // Real failing feed (observed 2026-06-06): a brand-new line debuts as a
    // prerelease, so it sorts NEWEST — first in the newest-first list — ahead of
    // the actual latest stable. The first MATCHING tag must still be 12.6.0, not
    // 13.0.0.
    let feed = ["core@13.0.0-beta.0", "core@12.6.0", "core@12.6.0-beta.0", "core@12.5.0"]
    let first = feed.lazy.compactMap { extract($0, "com.insomnia.app") }.first
    #expect(first == "12.6.0")
}

@Test func zedStableRuleExtractsVPrefixedTag() {
    // Stable ships non-prerelease `vX.Y.Z`; `/releases/latest` never returns a
    // `-pre`, so the default pattern just strips the `v`.
    #expect(extract("v1.5.3", "dev.zed.Zed") == "1.5.3")
    // Stable rule reads `/releases/latest` (not the prerelease list)…
    #expect(rule("dev.zed.Zed").usePrereleases == false)
    // …is gated to the stable channel, and now ships best-effort one-click: the
    // stable `Zed-aarch64.dmg` is a notarized Developer ID build matching the
    // installed bundle, so the swap passes the VendorInstaller gate.
    #expect(rule("dev.zed.Zed").channel == .stable)
    #expect(rule("dev.zed.Zed").installAssetPattern == #"^Zed-aarch64\.dmg$"#)
    // Preview stays a distinct bundle id on the prerelease list — no collision.
    #expect(rule("dev.zed.Zed-Preview").usePrereleases == true)
    // Preview MUST be channel-gated to `.preview`, else the source's channel gate
    // skips it and a real Preview install resolves to no source (the regression
    // the live `--check` caught when the gate defaulted the rule to `.stable`).
    #expect(rule("dev.zed.Zed-Preview").channel == .preview)
    // Preview also ships best-effort one-click (its own prerelease `Zed-aarch64.dmg`,
    // bundle id dev.zed.Zed-Preview, same Team — each channel gets its own dmg).
    #expect(rule("dev.zed.Zed-Preview").installAssetPattern == #"^Zed-aarch64\.dmg$"#)
}

@Test func zenRuleKeepsLetterSuffix() {
    // The trailing 'b' is part of the installed version string, so it must survive.
    #expect(extract("1.20.1b", "app.zen-browser.zen") == "1.20.1b")
}

@Test func githubDesktopRuleExcludesBetaAndTestTags() {
    // Production tag → bare X.Y.Z.
    #expect(extract("release-3.5.12", "com.github.GitHubClient") == "3.5.12")
    // Beta/test tags must NOT match (the `$` anchor rejects the suffix), so a
    // stray prerelease can never be read as a production version.
    #expect(extract("release-3.5.12-beta2", "com.github.GitHubClient") == nil)
    #expect(extract("release-3.5.13-beta1", "com.github.GitHubClient") == nil)
    #expect(extract("release-3.5.12-test1", "com.github.GitHubClient") == nil)
}

// MARK: - 2026-08-16 coverage batch
//
// Tags and asset filenames below are the REAL ones observed on each repo on
// 2026-08-16; the negative cases are the specific artifacts that sit beside the
// wanted one in the same release and would be picked by a looser pattern.

private func assetList(_ names: [String]) -> [(name: String, url: URL, size: Int64?)] {
    names.map { (name: $0, url: URL(string: "https://example.invalid/\($0)")!, size: Int64?.none) }
}

private func matches(_ name: String, _ bundleID: String) -> Bool {
    guard let p = rule(bundleID).installAssetPattern else { return false }
    return name.range(of: p, options: .regularExpression) != nil
}

@Test func ccSwitchRulePicksTheMacDmg() {
    #expect(extract("v3.19.2", "com.ccswitch.desktop") == "3.19.2")
    #expect(matches("CC-Switch-v3.19.2-macOS.dmg", "com.ccswitch.desktop"))
    // The same build also ships as .zip/.tar.gz, and Windows artifacts share the
    // release; none of them may be selected.
    #expect(!matches("CC-Switch-v3.19.2-macOS.zip", "com.ccswitch.desktop"))
    #expect(!matches("CC-Switch-v3.19.2-macOS.tar.gz", "com.ccswitch.desktop"))
    #expect(!matches("CC-Switch-v3.19.2-Windows-Portable.zip", "com.ccswitch.desktop"))
}

@Test func brunoRulePinsArm64() {
    #expect(extract("v4.0.0", "com.usebruno.app") == "4.0.0")
    #expect(matches("bruno_4.0.0_arm64_mac.dmg", "com.usebruno.app"))
    // An Intel dmg ships in the same release — never hand it to an arm64 Mac.
    #expect(!matches("bruno_4.0.0_x64_mac.dmg", "com.usebruno.app"))
    #expect(!matches("bruno_4.0.0_arm64_mac.pkg", "com.usebruno.app"))
    #expect(!matches("bruno_4.0.0_arm64_win.zip", "com.usebruno.app"))
}

/// PureMac ships a second product out of the same releases: `cli-v1.0.0`
/// (2026-08-17) carries only `puremac-cli-1.0.0.tar.gz` and GitHub marks it
/// latest. Unanchored, the default pattern read that as 1.0.0 — and a remote
/// *behind* the installed 2.9.x evaluates to "up to date", so every real update
/// disappeared silently. CI's own baseline had recorded `lastGoodVersion: 1.0.0`.
@Test func pureMacRuleRejectsTheCLIProductTag() {
    #expect(extract("v2.9.7", "com.puremac.app") == "2.9.7")
    #expect(extract("cli-v1.0.0", "com.puremac.app") == nil)
    // The asset gate is the second guard, not a substitute for the first.
    #expect(matches("PureMac-2.9.7.dmg", "com.puremac.app"))
    #expect(!matches("puremac-cli-1.0.0.tar.gz", "com.puremac.app"))
    #expect(!matches("PureMac-2.9.7.zip", "com.puremac.app"))
}

@Test func localSendRulePicksTheDmgAndNothingElse() {
    #expect(extract("v1.18.0", "org.localsend.localsendApp") == "1.18.0")
    #expect(matches("LocalSend-1.18.0.dmg", "org.localsend.localsendApp"))
    // Everything else in the real v1.18.0 listing shares the `LocalSend-` prefix,
    // which is why the pattern anchors both ends. The CLI tarballs even carry a
    // `macos` token, so an extension check alone is not enough.
    #expect(!matches("LocalSend-CLI-1.18.0-macos-arm-64.tar.gz", "org.localsend.localsendApp"))
    #expect(!matches("LocalSend-CLI-1.18.0-macos-x86-64.tar.gz", "org.localsend.localsendApp"))
    #expect(!matches("LocalSend-1.18.0-windows-x86-64.zip", "org.localsend.localsendApp"))
    #expect(!matches("LocalSend-1.18.0-linux-x86-64.deb", "org.localsend.localsendApp"))
    #expect(!matches("LocalSend-1.18.1-android-arm64v8.apk", "org.localsend.localsendApp"))
}

/// The phantom-update regression, replayed on the exact listings that produced
/// it: v1.18.1 (2026-08-12) carries four Android `.apk` files and no macOS build
/// because upstream cut a mobile-only hotfix out of a version number shared by
/// all five platforms. Reading the tag alone reported an uninstallable
/// 1.18.0 → 1.18.1 update; the asset gate has to walk back to v1.18.0.
@Test func localSendMobileOnlyReleaseIsNotAMacOSRelease() {
    guard let pattern = rule("org.localsend.localsendApp").installAssetPattern else {
        Issue.record("LocalSend rule lost its installAssetPattern")
        return
    }
    func carries(_ names: [String]) -> Bool {
        GitHubReleaseRule.carriesInstallableAsset(from: assetList(names), matching: pattern)
    }
    // v1.18.1, verbatim.
    #expect(!carries([
        "LocalSend-1.18.1-android-arm32v7.apk", "LocalSend-1.18.1-android-arm64v8.apk",
        "LocalSend-1.18.1-android-google-play.apk", "LocalSend-1.18.1-android-x64.apk",
    ]))
    // v1.18.0, abridged to one asset per platform.
    #expect(carries([
        "LocalSend-1.18.0-android-arm64v8.apk", "LocalSend-1.18.0-windows-x86-64.zip",
        "LocalSend-1.18.0-linux-x86-64.deb", "LocalSend-1.18.0.dmg",
        "LocalSend-CLI-1.18.0-macos-arm-64.tar.gz",
    ]))
}

/// The gate answers "does a macOS build exist here", which is a different
/// question from "which file do we install" — and conflating them breaks the
/// Intel case. `installableAsset` returns nil when every match is built for the
/// other architecture and this Mac can't run it; if that nil were the gate, an
/// Intel Mac would walk *past* a release that genuinely ships macOS and report
/// an older version as the newest. The gate is a plain pattern match on purpose.
@Test func assetGateIgnoresArchitectureSelectability() {
    let pattern = #"^App-[0-9.]+-(?:arm64|x86_64)\.dmg$"#
    let arm64Only = assetList(["App-2.0-arm64.dmg"])
    #expect(GitHubReleaseRule.carriesInstallableAsset(from: arm64Only, matching: pattern))
    // An Intel Mac can't install it — but the release is still a macOS release,
    // so resolution must report 2.0 rather than fall back to an older tag.
    #expect(GitHubReleaseRule.installableAsset(
        from: arm64Only, matching: pattern, preferring: .x86_64,
        allowingIntelTranslation: false) == nil)
    #expect(!GitHubReleaseRule.carriesInstallableAsset(
        from: assetList(["App-2.0-linux.tar.gz"]), matching: pattern))
}

@Test func utmRuleStaysOnTheStableTrain() {
    #expect(extract("v4.7.5", "com.utmapp.UTM") == "4.7.5")
    // v5.x exists but only as prereleases: reading `/releases/latest` is what keeps
    // a 4.x install from being offered a v5 preview.
    #expect(rule("com.utmapp.UTM").usePrereleases == false)
    #expect(rule("com.utmapp.UTM").channel == .stable)
    #expect(matches("UTM.dmg", "com.utmapp.UTM"))
    // Real siblings in the same release: the iOS/visionOS builds and the Debian
    // package. UTM SE ships only as .ipa, so the `.dmg` anchor already excludes it.
    #expect(!matches("UTM.ipa", "com.utmapp.UTM"))
    #expect(!matches("UTM-SE.ipa", "com.utmapp.UTM"))
    #expect(!matches("UTM.deb", "com.utmapp.UTM"))
}

@Test func kittyRuleMatchesVersionedDmgOnly() {
    #expect(extract("v0.48.2", "net.kovidgoyal.kitty") == "0.48.2")
    #expect(rule("net.kovidgoyal.kitty").usePrereleases == false)  // rolling `nightly` tag
    #expect(matches("kitty-0.48.2.dmg", "net.kovidgoyal.kitty"))
    // The detached signature sits beside the dmg.
    #expect(!matches("kitty-0.48.2.dmg.sig", "net.kovidgoyal.kitty"))
}

@Test func sqliteBrowserRuleExcludesSQLCipherBuild() {
    #expect(extract("v3.13.1", "net.sourceforge.sqlitebrowser") == "3.13.1")
    #expect(matches("DB.Browser.for.SQLite-v3.13.1.dmg", "net.sourceforge.sqlitebrowser"))
    // A different product (SQLCipher) builds from the same repo, and Windows/Linux
    // artifacts share the release.
    #expect(!matches("DB.Browser.for.SQLCipher-universal_20260810.dmg",
                     "net.sourceforge.sqlitebrowser"))
    #expect(!matches("DB.Browser.for.SQLite-v3.13.1-arm64.zip", "net.sourceforge.sqlitebrowser"))
    #expect(!matches("DB.Browser.for.SQLite-v3.13.1-win64.msi", "net.sourceforge.sqlitebrowser"))
}

@Test func drawioRulePicksArm64Dmg() {
    #expect(extract("v31.1.8", "com.jgraph.drawio.desktop") == "31.1.8")
    #expect(matches("draw.io-arm64-31.1.8.dmg", "com.jgraph.drawio.desktop"))
    #expect(!matches("draw.io-universal-31.1.8.dmg", "com.jgraph.drawio.desktop"))
    #expect(!matches("draw.io-arm64-31.1.8.zip", "com.jgraph.drawio.desktop"))
}

@Test func podmanDesktopRuleExcludesAirgapBuild() {
    #expect(extract("v1.29.1", "io.podmandesktop.PodmanDesktop") == "1.29.1")
    #expect(matches("podman-desktop-1.29.1-arm64.dmg", "io.podmandesktop.PodmanDesktop"))
    // The airgap variant is the same app plus ~900 MB of bundled images; a
    // substring match would download it instead.
    #expect(!matches("podman-desktop-airgap-1.29.1-arm64.dmg", "io.podmandesktop.PodmanDesktop"))
    #expect(!matches("podman-desktop-1.29.1-universal.dmg", "io.podmandesktop.PodmanDesktop"))
    #expect(!matches("podman-desktop-1.29.1-arm64.zip", "io.podmandesktop.PodmanDesktop"))
}

@Test func bitwardenRuleTracksTheDesktopTagOnly() {
    // The monorepo tags every client; only `desktop-v…` is this app's version.
    #expect(extract("desktop-v2026.7.0", "com.bitwarden.desktop") == "2026.7.0")
    // The tags that are usually NEWER than the desktop one must not match, or the
    // desktop app would start reporting the web client's version.
    #expect(extract("web-v2026.7.1", "com.bitwarden.desktop") == nil)
    #expect(extract("cli-v2026.7.0", "com.bitwarden.desktop") == nil)
    #expect(extract("browser-v2026.7.0", "com.bitwarden.desktop") == nil)
    // Defensive, not observed: every desktop tag in the newest 100 releases is
    // bare, but if a suffixed one ever appears it must not read as stable.
    #expect(extract("desktop-v2026.8.0-rc1", "com.bitwarden.desktop") == nil)
    // Which requires reading the release LIST, not `/releases/latest`.
    #expect(rule("com.bitwarden.desktop").usePrereleases == true)
    #expect(matches("Bitwarden-2026.7.0-universal.dmg", "com.bitwarden.desktop"))
    #expect(!matches("Bitwarden-2026.7.0-universal-mac.zip", "com.bitwarden.desktop"))
    #expect(!matches("Bitwarden-2026.7.0-universal.pkg.archive", "com.bitwarden.desktop"))
}

@Test func vscodiumRuleKeepsBuildStampInVersion() {
    // The last group is VSCodium's build stamp and IS part of the installed
    // version string — truncating it to 1.126 would report a phantom update.
    #expect(extract("1.126.04524", "com.vscodium") == "1.126.04524")
    #expect(matches("VSCodium-darwin-arm64-1.126.04524.zip", "com.vscodium"))
    #expect(!matches("VSCodium-darwin-x64-1.126.04524.zip", "com.vscodium"))
    #expect(!matches("vscodium-cli-darwin-arm64-1.126.04524.tar.gz", "com.vscodium"))
}

/// VSCodium Insiders — own repo (VSCodium/vscodium-insiders), distinct bundle
/// id. Fixture is the REAL `/releases/latest` response for tag
/// `1.126.04518-insider`, verified 2026-08-27 (`GET
/// /repos/VSCodium/vscodium-insiders/releases/latest`): 165 assets, exactly the
/// two darwin zips below match, and the tag/asset shapes are what's asserted.
@Test func vscodiumInsidersRuleKeepsInsiderSuffixInVersion() {
    // The `-insider` suffix MUST survive extraction — see the registry comment.
    // A pattern that stopped at the digits (like the default
    // `v?([0-9]+(?:\.[0-9]+)+)`) would drop it; the trap is pinned separately in
    // `vscodiumInsidersMissingSuffixWouldBeAPermanentPhantomUpdate` below.
    #expect(extract("1.126.04518-insider", "com.vscodium.VSCodiumInsiders") == "1.126.04518-insider")
    // A bare stable-shaped tag (no repo actually publishes this, but the pattern
    // must not accept it either) is rejected.
    #expect(extract("1.126.04518", "com.vscodium.VSCodiumInsiders") == nil)

    // The arm64 darwin asset matches…
    #expect(matches("VSCodium-darwin-arm64-1.126.04518-insider.zip", "com.vscodium.VSCodiumInsiders"))
    // …and the x64 one deliberately does NOT. This track ships platform-partial
    // releases (`1.126.04405-insider` is x64-only), where matching x64 would let
    // `installableAsset` step 3 hand an Apple-silicon install an Intel build
    // under Rosetta. Not matching it makes that release carry no installable
    // asset, which is the outcome we want. See the rule's comment.
    #expect(!matches("VSCodium-darwin-x64-1.126.04518-insider.zip", "com.vscodium.VSCodiumInsiders"))
    // …but the stable build's un-suffixed filename, the CLI tarball, and the
    // checksum sidecars beside the real asset must not.
    #expect(!matches("VSCodium-darwin-arm64-1.126.04518.zip", "com.vscodium.VSCodiumInsiders"))
    #expect(!matches("vscodium-cli-darwin-arm64-1.126.04518-insider.tar.gz", "com.vscodium.VSCodiumInsiders"))
    #expect(!matches("VSCodium-darwin-arm64-1.126.04518-insider.zip.sha256", "com.vscodium.VSCodiumInsiders"))

    // Insiders' `/releases/latest` returns a non-prerelease object (verified
    // above), so the rule reads it directly rather than walking the list.
    #expect(rule("com.vscodium.VSCodiumInsiders").usePrereleases == false)
    // MUST be channel-gated to `.preview`, or the source's channel gate skips it
    // for a real Insiders install (same regression class as Zed Preview above).
    #expect(rule("com.vscodium.VSCodiumInsiders").channel == .preview)
    #expect(rule("com.vscodium.VSCodiumInsiders").installerKind == .zip)
}

/// The trap the registry comment and issue #92 call out by name, replayed
/// through the real comparator rather than asserted by description. Verified
/// 2026-08-27 against the real downloaded arm64 asset's Info.plist:
/// CFBundleShortVersionString and CFBundleVersion are both
/// "1.126.04518-insider" — so this is the actual installed-side string, not a
/// guess.
@Test func vscodiumInsidersMissingSuffixWouldBeAPermanentPhantomUpdate() {
    let installed = "1.126.04518-insider"
    // What the DEFAULT rule pattern (`v?([0-9]+(?:\.[0-9]+)+)`) would have
    // extracted from the same real tag — the suffix is gone.
    let defaultExtracted = VendorProbeRecipe.extractVersion(
        from: "1.126.04518-insider", pattern: #"v?([0-9]+(?:\.[0-9]+)+)"#)
    #expect(defaultExtracted == "1.126.04518")
    // A missing trailing component pads to "0", which OUTRANKS the text token
    // "insider" (VersionComparator: a numeric component always beats a textual
    // one) — so the bare remote would forever read as newer than the correctly
    // suffixed installed version, even though it is the exact same release.
    #expect(VersionComparator.isNewer(defaultExtracted!, than: installed))

    // The shipping rule's pattern keeps the suffix, so remote == installed
    // compares equal — no phantom update.
    let shipping = extract("1.126.04518-insider", "com.vscodium.VSCodiumInsiders")
    #expect(shipping == installed)
    #expect(!VersionComparator.isNewer(shipping!, than: installed))
    #expect(VersionComparator.compare(shipping!, installed) == .orderedSame)
}

@Test func balenaEtcherRulePinsArm64Dmg() {
    #expect(extract("v2.1.6", "io.balena.etcher") == "2.1.6")
    #expect(matches("balenaEtcher-2.1.6-arm64.dmg", "io.balena.etcher"))
    #expect(!matches("balenaEtcher-2.1.6-x64.dmg", "io.balena.etcher"))
    #expect(!matches("balenaEtcher-darwin-arm64-2.1.6.zip", "io.balena.etcher"))
}

@Test func caffeineRuleMatchesConstantDmgName() {
    #expect(extract("1.1.4", "com.intelliscapesolutions.caffeine") == "1.1.4")
    #expect(matches("Caffeine.dmg", "com.intelliscapesolutions.caffeine"))
    // The release ships this one asset, so there is no real sibling to exclude.
    // The `installerKind` assertion covers the other way this rule can rot: the
    // pattern survives but the kind is dropped, which makes the update silently
    // detection-only. (A dropped PATTERN is already caught by the positive
    // `matches(…)` above.) The six sibling tests assert it for the same reason.
    #expect(rule("com.intelliscapesolutions.caffeine").installerKind == .dmg)
}

@Test func godotRuleExcludesMonoBuild() {
    #expect(extract("4.7.1-stable", "org.godotengine.godot") == "4.7.1")
    // A .0 release tags as `4.7-stable`; two components is still a valid version.
    #expect(extract("4.7-stable", "org.godotengine.godot") == "4.7")
    #expect(matches("Godot_v4.7.1-stable_macos.universal.zip", "org.godotengine.godot"))
    // The Mono/.NET build shares the bundle id — installing it over a plain install
    // would switch the user's editor flavour.
    #expect(!matches("Godot_v4.7.1-stable_mono_macos.universal.zip", "org.godotengine.godot"))
    #expect(!matches("Godot_v4.7.1-stable_linux.arm64.zip", "org.godotengine.godot"))
}

/// A respun KeePassXC release keeps both the original and the respun dmg, so the
/// pattern matches more than one asset and `installableAsset`'s arch tiering plus
/// highest-name-wins rule decides. This does NOT pin upstream's ordering (it
/// can't — the list is a fixture): it pins the *selection semantics* against the
/// real 2.7.11 asset list in the order GitHub returns it, alphabetical, and then
/// against the orders GitHub could equally have returned.
@Test func keepassxcRespinIsTheAssetSelected() {
    func assets(_ names: [String]) -> [(name: String, url: URL, size: Int64?)] {
        names.map { (name: $0, url: URL(string: "https://example.invalid/\($0)")!,
                     size: Int64?.none) }
    }
    guard let pattern = rule("org.keepassxc.keepassxc").installAssetPattern else {
        Issue.record("KeePassXC rule lost its installAssetPattern")
        return
    }
    func picked(_ names: [String]) -> String? {
        GitHubReleaseRule.installableAsset(
            from: assets(names), matching: pattern, preferring: .arm64)?
            .url.lastPathComponent
    }
    // Real 2.7.11 listing: the respin sorts first, so the respin is what installs.
    #expect(picked(["KeePassXC-2.7.11-1-arm64.dmg", "KeePassXC-2.7.11-1-x86_64.dmg",
                    "KeePassXC-2.7.11-arm64.dmg", "KeePassXC-2.7.11-x86_64.dmg"])
            == "KeePassXC-2.7.11-1-arm64.dmg")
    // A normal release has exactly one arm64 match, so there is nothing to decide.
    #expect(picked(["KeePassXC-2.7.12-arm64.dmg", "KeePassXC-2.7.12-x86_64.dmg"])
            == "KeePassXC-2.7.12-arm64.dmg")
    // A SECOND respin wins over the first, which alphabetical order gets backwards
    // (`-1-` sorts before `-2-`). Not reachable in KeePassXC's own history — no
    // release has gone past `-1` — but this is the case that made the selection
    // positional-by-accident, and it is now decided by comparison (issue #80).
    #expect(picked(["KeePassXC-2.7.11-1-arm64.dmg", "KeePassXC-2.7.11-2-arm64.dmg",
                    "KeePassXC-2.7.11-arm64.dmg"]) == "KeePassXC-2.7.11-2-arm64.dmg")
    // …in either listing order: the point is that position stopped deciding.
    #expect(picked(["KeePassXC-2.7.11-2-arm64.dmg", "KeePassXC-2.7.11-1-arm64.dmg",
                    "KeePassXC-2.7.11-arm64.dmg"]) == "KeePassXC-2.7.11-2-arm64.dmg")
    // Double digits: `-10-` beats `-9-` numerically, where a string sort would
    // put `-10-` first and read it as the newer one.
    #expect(picked(["KeePassXC-2.7.11-9-arm64.dmg", "KeePassXC-2.7.11-10-arm64.dmg"])
            == "KeePassXC-2.7.11-10-arm64.dmg")
    // And the respin still beats the un-respun original whichever way round the
    // list arrives — the real 2.7.11 case, no longer relying on GitHub's sort.
    #expect(picked(["KeePassXC-2.7.11-arm64.dmg", "KeePassXC-2.7.11-1-arm64.dmg"])
            == "KeePassXC-2.7.11-1-arm64.dmg")
}

@Test func keepassxcRuleAllowsRespinSuffix() {
    #expect(extract("2.7.12", "org.keepassxc.keepassxc") == "2.7.12")
    #expect(matches("KeePassXC-2.7.12-arm64.dmg", "org.keepassxc.keepassxc"))
    // A respin appends `-1` to the FILENAME under the same tag.
    #expect(matches("KeePassXC-2.7.11-1-arm64.dmg", "org.keepassxc.keepassxc"))
    #expect(!matches("KeePassXC-2.7.12-x86_64.dmg", "org.keepassxc.keepassxc"))
    #expect(!matches("KeePassXC-2.7.12-Win64.zip", "org.keepassxc.keepassxc"))
}

@Test func sequelAceRuleReadsMarketingVersionFromTag() {
    // `production/<marketing>-<build>` → the marketing version the app reports.
    #expect(extract("production/5.4.0-20109", "com.sequel-ace.sequel-ace") == "5.4.0")
    #expect(matches("Sequel-Ace-5.4.0.zip", "com.sequel-ace.sequel-ace"))
    #expect(rule("com.sequel-ace.sequel-ace").installerKind == .zip)
}

@Test func swiftBarRuleMatchesVersionedBuildZip() {
    #expect(extract("v2.1.1", "com.ameba.SwiftBar") == "2.1.1")
    // Betas are published as prereleases, so the stable rule reads /releases/latest.
    // That gate matters here: the beta asset (`SwiftBar.v2.1.2.b607.zip`) has the
    // same filename shape and WOULD match the pattern — only the endpoint keeps it
    // out of a stable install's reach.
    #expect(rule("com.ameba.SwiftBar").usePrereleases == false)
    #expect(matches("SwiftBar.v2.1.1.b597.zip", "com.ameba.SwiftBar"))
    #expect(rule("com.ameba.SwiftBar").installerKind == .zip)
}

@Test func openMTPRulePinsArm64Dmg() {
    #expect(extract("v3.2.25", "io.ganeshrvel.openmtp") == "3.2.25")
    #expect(matches("openmtp-3.2.25-mac-arm64.dmg", "io.ganeshrvel.openmtp"))
    #expect(!matches("openmtp-3.2.25-mac-x64.dmg", "io.ganeshrvel.openmtp"))
    #expect(!matches("openmtp-3.2.25-mac-arm64.zip", "io.ganeshrvel.openmtp"))
}

@Test func headlampRuleIgnoresChartTags() {
    #expect(extract("v0.44.0", "com.microsoft.Headlamp") == "0.44.0")
    // Helm-chart and plugin releases share the repo and can be published AFTER the
    // app's release; they must never be read as the app's version.
    #expect(extract("headlamp-helm-0.44.0", "com.microsoft.Headlamp") == nil)
    #expect(extract("headlamp-plugin-0.14.0", "com.microsoft.Headlamp") == nil)
    #expect(rule("com.microsoft.Headlamp").usePrereleases == true)  // reads the list
    #expect(matches("Headlamp-0.44.0-mac-arm64.dmg", "com.microsoft.Headlamp"))
    #expect(!matches("Headlamp-0.44.0-mac-x64.dmg", "com.microsoft.Headlamp"))
}

@Test func luluRuleMatchesUnderscoreDmg() {
    #expect(extract("v4.5.1", "com.objective-see.lulu.app") == "4.5.1")
    #expect(matches("LuLu_4.5.1.dmg", "com.objective-see.lulu.app"))
    // Single-asset release; `installerKind` asserted for the reason given on
    // `caffeineRuleMatchesConstantDmgName`.
    #expect(rule("com.objective-see.lulu.app").installerKind == .dmg)
}

@Test func noTunesRuleHandlesTwoComponentTag() {
    #expect(extract("v3.5", "digital.twisted.noTunes") == "3.5")
    #expect(matches("noTunes-3.5.zip", "digital.twisted.noTunes"))
    #expect(rule("digital.twisted.noTunes").installerKind == .zip)
    // The app reports short "3.5" with CFBundleVersion "1", so it carries the same
    // folded-build shape as Anki. Documented on the rule; this pins the premise, so
    // if upstream ever ships a three-component version the note gets revisited.
    #expect(VersionComparator.compare("3.5.1", "3.5") == .orderedDescending)
}

@Test func markEditRuleTakesTheUniversalDmg() {
    #expect(extract("v1.34.0", "app.cyan.markedit") == "1.34.0")
    // The universal dmg (x86_64 + arm64, verified with `file`) is the pin; the
    // `-apple-silicon` dmg is a single arm64 slice and must NOT match, or an Intel
    // Mac would be offered a build it cannot run.
    #expect(matches("MarkEdit-1.34.0.dmg", "app.cyan.markedit"))
    #expect(!matches("MarkEdit-1.34.0-apple-silicon.dmg", "app.cyan.markedit"))
    // The app's own updater payloads are for a different install path.
    #expect(!matches("UpdateArchive-arm64.zip", "app.cyan.markedit"))
    #expect(!matches("UpdateArchive.zip", "app.cyan.markedit"))
}

@Test func clashVergeRulePinsAarch64() {
    #expect(extract("v2.5.2", "io.github.clash-verge-rev.clash-verge-rev") == "2.5.2")
    #expect(matches("Clash.Verge_2.5.2_aarch64.dmg",
                    "io.github.clash-verge-rev.clash-verge-rev"))
    #expect(!matches("Clash.Verge_2.5.2_x64.dmg",
                     "io.github.clash-verge-rev.clash-verge-rev"))
}

@Test func freelensRulePinsArm64() {
    #expect(extract("v1.10.3", "app.freelens.Freelens") == "1.10.3")
    #expect(matches("Freelens-1.10.3-macos-arm64.dmg", "app.freelens.Freelens"))
    #expect(!matches("Freelens-1.10.3-macos-amd64.dmg", "app.freelens.Freelens"))
}

@Test func keepingYouAwakeRuleExtractsBareTag() {
    #expect(extract("1.6.8", "info.marcel-dierkes.KeepingYouAwake") == "1.6.8")
    #expect(matches("KeepingYouAwake-1.6.8.zip", "info.marcel-dierkes.KeepingYouAwake"))
    #expect(rule("info.marcel-dierkes.KeepingYouAwake").installerKind == .zip)
}

@Test func espansoRuleMatchesVersionlessAssetName() {
    #expect(extract("v2.4.0", "com.federicoterzi.espanso") == "2.4.0")
    #expect(matches("Espanso-Mac-Universal.dmg", "com.federicoterzi.espanso"))
    #expect(!matches("Espanso-Win-Portable-x86_64.zip", "com.federicoterzi.espanso"))
}

@Test func tabbyRulePinsMacArm64Dmg() {
    #expect(extract("v1.0.235", "org.tabby") == "1.0.235")
    #expect(matches("tabby-1.0.235-macos-arm64.dmg", "org.tabby"))
    #expect(!matches("tabby-1.0.235-macos-x86_64.dmg", "org.tabby"))
    #expect(!matches("tabby-1.0.235-portable-arm64.zip", "org.tabby"))
}

@Test func moonlightRuleExcludesSteamLinkAndPortable() {
    #expect(extract("v6.1.0", "com.moonlight-stream.Moonlight") == "6.1.0")
    #expect(matches("Moonlight-6.1.0.dmg", "com.moonlight-stream.Moonlight"))
    #expect(!matches("Moonlight-SteamLink-6.1.0.zip", "com.moonlight-stream.Moonlight"))
    #expect(!matches("MoonlightPortable-arm64-6.1.0.zip", "com.moonlight-stream.Moonlight"))
}

@Test func handyRulePinsAarch64() {
    #expect(extract("v0.9.5", "com.pais.handy") == "0.9.5")
    #expect(matches("Handy_0.9.5_aarch64.dmg", "com.pais.handy"))
    #expect(!matches("Handy_0.9.5_x64.dmg", "com.pais.handy"))
}

@Test func batteryRulePinsArm64Dmg() {
    #expect(extract("v1.4.0", "co.palokaj.battery") == "1.4.0")
    #expect(matches("battery-1.4.0-mac-arm64.dmg", "co.palokaj.battery"))
    #expect(!matches("battery-1.4.0-mac-arm64.zip", "co.palokaj.battery"))
}

@Test func anotherRedisRulePinsMacArm64() {
    #expect(extract("v1.7.2", "me.qii404.another-redis-desktop-manager") == "1.7.2")
    #expect(matches("Another-Redis-Desktop-Manager-mac-1.7.2-arm64.dmg",
                    "me.qii404.another-redis-desktop-manager"))
    #expect(!matches("Another-Redis-Desktop-Manager-mac-1.7.2-x64.dmg",
                     "me.qii404.another-redis-desktop-manager"))
    #expect(!matches("Another-Redis-Desktop-Manager-win-1.7.2-x64.zip",
                     "me.qii404.another-redis-desktop-manager"))
}

@Test func gooseRuleTakesDesktopZipNotCLI() {
    #expect(extract("v1.46.0", "com.electron.goose") == "1.46.0")
    #expect(matches("Goose.zip", "com.electron.goose"))
    #expect(matches("Goose_intel_mac.zip", "com.electron.goose"))
    // The CLI tarballs, the source drop and the Windows builds share the release.
    #expect(!matches("goose-aarch64-apple-darwin.tar.gz", "com.electron.goose"))
    #expect(!matches("goose-source-v1.46.0.zip", "com.electron.goose"))
    #expect(!matches("Goose-win32-x64.zip", "com.electron.goose"))
}

/// Two rules pin an Apple-silicon-only artifact whose FILENAME carries no token
/// `installableAsset` reads as an architecture (`Goose.zip`, `anki-…-mac-apple.dmg`).
/// Matching only those would classify them as arch-neutral and install an arm64
/// build on an Intel Mac — which the install gate cannot catch, since it checks
/// signature, Team and bundle id but never architecture. Both rules therefore match
/// the Intel sibling too, and these are the assertions that keep it that way.
@Test func archNeutralNamesStillResolvePerArchitecture() {
    func picked(_ bundleID: String, _ names: [String], _ arch: HostArch) -> String? {
        let assets = names.map {
            (name: $0, url: URL(string: "https://example.invalid/\($0)")!, size: Int64?.none)
        }
        // Not `try! #require`: a deleted registry entry should fail this test, not
        // crash the suite — the same reason `rule()` stopped force-unwrapping.
        guard let pattern = rule(bundleID).installAssetPattern else {
            Issue.record("\(bundleID) has no installAssetPattern")
            return nil
        }
        return GitHubReleaseRule.installableAsset(
            from: assets, matching: pattern, preferring: arch)?.url.lastPathComponent
    }
    // Real v1.46.0 macOS assets.
    let goose = ["Goose.zip", "Goose_intel_mac.zip"]
    #expect(picked("com.electron.goose", goose, .arm64) == "Goose.zip")
    #expect(picked("com.electron.goose", goose, .x86_64) == "Goose_intel_mac.zip")
    // Real 26.08.1 macOS assets.
    let anki = ["anki-26.08.1-mac-apple.dmg", "anki-26.08.1-mac-intel.dmg"]
    #expect(picked("net.ankiweb.anki", anki, .arm64) == "anki-26.08.1-mac-apple.dmg")
    #expect(picked("net.ankiweb.anki", anki, .x86_64) == "anki-26.08.1-mac-intel.dmg")
}

/// The repo slug is the one part of a rule no other test touches: a typo leaves
/// every pattern fixture green while detection is dead in production. Pinned
/// against the slugs verified live on 2026-08-16, re-pinned 2026-08-29.
///
/// ⚠️ **This does NOT catch an upstream rename, and the comment used to claim it
/// did.** It compares our string to our own pinned copy, so a repo renamed on
/// GitHub's side leaves both sides equal and this test green — which is exactly
/// what happened: `block/goose`, `containers/podman-desktop` and
/// `headlamp-k8s/headlamp` were all renamed with nothing here noticing, and each
/// one silently dropped to the anonymous rate-limit budget because URLSession
/// drops `Authorization` while following GitHub's 301. What this test does catch
/// is *us* changing a slug without meaning to. Catching the other direction
/// needs a live comparison against the repo's `full_name`; see #135.
@Test func batchRuleSlugsArePinned() {
    let expected: [String: String] = [
        "com.ccswitch.desktop": "farion1231/cc-switch",
        "com.usebruno.app": "usebruno/bruno",
        "org.localsend.localsendApp": "localsend/localsend",
        "com.utmapp.UTM": "utmapp/UTM",
        "net.kovidgoyal.kitty": "kovidgoyal/kitty",
        "net.sourceforge.sqlitebrowser": "sqlitebrowser/sqlitebrowser",
        "com.jgraph.drawio.desktop": "jgraph/drawio-desktop",
        // Renamed upstream; re-pinned 2026-08-29 (was containers/podman-desktop). #135
        "io.podmandesktop.PodmanDesktop": "podman-desktop/podman-desktop",
        "com.bitwarden.desktop": "bitwarden/clients",
        "com.vscodium": "VSCodium/vscodium",
        "com.vscodium.VSCodiumInsiders": "VSCodium/vscodium-insiders",
        "io.balena.etcher": "balena-io/etcher",
        "com.intelliscapesolutions.caffeine": "IntelliScape/caffeine",
        "org.godotengine.godot": "godotengine/godot",
        "org.keepassxc.keepassxc": "keepassxreboot/keepassxc",
        "com.sequel-ace.sequel-ace": "Sequel-Ace/Sequel-Ace",
        "com.ameba.SwiftBar": "swiftbar/SwiftBar",
        "io.ganeshrvel.openmtp": "ganeshrvel/openmtp",
        // Renamed upstream; re-pinned 2026-08-29 (was headlamp-k8s/headlamp). #135
        "com.microsoft.Headlamp": "kubernetes-sigs/headlamp",
        "com.objective-see.lulu.app": "objective-see/LuLu",
        "digital.twisted.noTunes": "tombonez/noTunes",
        "app.cyan.markedit": "MarkEdit-app/MarkEdit",
        "io.github.clash-verge-rev.clash-verge-rev": "clash-verge-rev/clash-verge-rev",
        "app.freelens.Freelens": "freelensapp/freelens",
        "info.marcel-dierkes.KeepingYouAwake": "newmarcel/KeepingYouAwake",
        "com.federicoterzi.espanso": "espanso/espanso",
        "org.tabby": "Eugeny/tabby",
        "com.moonlight-stream.Moonlight": "moonlight-stream/moonlight-qt",
        "com.pais.handy": "cjpais/Handy",
        "co.palokaj.battery": "actuallymentor/battery",
        "me.qii404.another-redis-desktop-manager": "qishibo/AnotherRedisDesktopManager",
        // Renamed upstream; re-pinned 2026-08-29 (was block/goose). #135
        "com.electron.goose": "aaif-goose/goose",
        "com.puremac.app": "momenbasel/PureMac",
        "art.ginzburg.MiddleClick": "artginzburg/MiddleClick",
        "com.theron.UnnaturalScrollWheels": "ther0n/UnnaturalScrollWheels",
        "net.ankiweb.anki": "ankitects/anki",
        "com.raspberrypi.rpi-imager": "raspberrypi/rpi-imager",
        "com.electron.open-lens": "MuhammedKalkan/OpenLens",
        "org.alacritty": "alacritty/alacritty",
        "org.flameshot.Flameshot": "flameshot-org/flameshot",
        "com.github.marktext.marktext": "marktext/marktext",
        "org.darktable": "darktable-org/darktable",
        "org.zaproxy.zap.ZAP": "zaproxy/zaproxy",
        "com.BlueBubbles.BlueBubbles-Server": "BlueBubblesApp/bluebubbles-server",
        "org.winehq.wine-staging.wine": "Gcenx/macOS_Wine_builds",
        // 2026-08-16, second pass.
        "io.rancherdesktop.app": "rancher-sandbox/rancher-desktop",
        "com.kangfenmao.CherryStudio": "CherryHQ/cherry-studio",
        "org.RedisLabs.RedisInsight-V2": "redis/RedisInsight",
        "org.upscayl.Upscayl": "upscayl/upscayl",
        "io.github.wickenico.wailbrew": "wickenico/WailBrew",
    ]
    for (bundleID, slug) in expected {
        #expect(rule(bundleID).slug == slug, "slug drifted for \(bundleID)")
    }
}

@Test func pureMacRuleTakesDmgOverZip() {
    #expect(extract("v2.9.7", "com.puremac.app") == "2.9.7")
    #expect(matches("PureMac-2.9.7.dmg", "com.puremac.app"))
    #expect(!matches("PureMac-2.9.7.zip", "com.puremac.app"))
}

@Test func middleClickRuleMatchesVersionlessZip() {
    #expect(extract("3.2.0", "art.ginzburg.MiddleClick") == "3.2.0")
    #expect(matches("MiddleClick.zip", "art.ginzburg.MiddleClick"))
    #expect(rule("art.ginzburg.MiddleClick").installerKind == .zip)
}

@Test func unnaturalScrollWheelsRuleExtractsBareTag() {
    #expect(extract("1.4.2", "com.theron.UnnaturalScrollWheels") == "1.4.2")
    #expect(matches("UnnaturalScrollWheels-1.4.2.dmg", "com.theron.UnnaturalScrollWheels"))
    #expect(rule("com.theron.UnnaturalScrollWheels").installerKind == .dmg)
}

@Test func ankiZeroPaddedTagComparesEqualToInstalled() {
    #expect(extract("26.08.1", "net.ankiweb.anki") == "26.08.1")
    // The app reports `26.8.1`; digit runs compare numerically, so this is the SAME
    // version, not an update. This is the assertion that keeps the zero padding from
    // becoming a permanent phantom update.
    #expect(VersionComparator.compare("26.08.1", "26.8.1") == .orderedSame)
    #expect(!VersionComparator.isNewer("26.08.1", than: "26.8.1"))
    // BOTH macOS dmgs must match, so the arch preference can do its job: pinning
    // only `-mac-apple` (a name with no arch token) reads as arch-neutral and would
    // put the Apple-silicon build on an Intel Mac.
    #expect(matches("anki-26.08.1-mac-apple.dmg", "net.ankiweb.anki"))
    #expect(matches("anki-26.08.1-mac-intel.dmg", "net.ankiweb.anki"))
    #expect(!matches("anki-26.08.1-windows-qt6.exe", "net.ankiweb.anki"))
    // Pins the known gap so it can't be mistaken for a rule bug later: Anki stamps
    // CFBundleVersion "1" on every build, and evaluate()'s folded-build fallback
    // turns installed 26.8 + build 1 into "26.8.1", which equals the real 26.08.1
    // release — so that one patch step reads as up-to-date. Documented on the rule.
    let installed = InstalledApp(
        name: "Anki", bundleID: "net.ankiweb.anki",
        shortVersion: "26.8", buildVersion: "1",
        path: URL(fileURLWithPath: "/Applications/Anki.app"),
        isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    let remote = RemoteVersion(
        shortVersion: "26.08.1", version: nil, downloadURL: nil,
        sourceName: "GitHub", requiresManualInstaller: false)
    // Recorded as a KNOWN issue, so the day someone tightens the fallback this test
    // reports "known issue was not recorded" — a prompt to delete the wrapper and
    // the note on the rule, rather than a failure blaming the fix.
    withKnownIssue("evaluate()'s folded-build fallback reads installed 26.8 + build 1 as 26.8.1, hiding the real 26.08.1 release") {
        guard case .updateAvailable = UpdateChecker.evaluate(installed: installed, remote: remote) else {
            Issue.record("26.08.1 not offered over installed 26.8")
            return
        }
    }
}

@Test func rpiImagerRuleKeepsTheVPrefix() {
    // This app's own CFBundleShortVersionString is `v2.0.11` — the `v` must survive
    // so the comparison is against the string the app actually reports.
    #expect(extract("v2.0.11", "com.raspberrypi.rpi-imager") == "v2.0.11")
    // A release candidate tag must not read as stable.
    #expect(extract("v2.0.11-rc1", "com.raspberrypi.rpi-imager") == nil)
    #expect(matches("rpi-imager-v2.0.11.dmg", "com.raspberrypi.rpi-imager"))
}

@Test func openLensRuleKeepsBuildSuffix() {
    // `-366` is part of the installed version; dropping it would make every release
    // look like a downgrade.
    #expect(extract("v6.5.2-366", "com.electron.open-lens") == "6.5.2-366")
    #expect(matches("OpenLens-6.5.2-366-arm64.dmg", "com.electron.open-lens"))
    #expect(!matches("OpenLens-6.5.2-366.dmg", "com.electron.open-lens"))
    #expect(!matches("OpenLens-6.5.2-366-arm64-mac.zip", "com.electron.open-lens"))
}

@Test func unsignedBuildsStayDetectionOnly() {
    // Their artifacts are ad-hoc signed or unsigned, so the install gate would
    // refuse them; the rules must not carry an install spec at all.
    for id in ["org.alacritty", "org.flameshot.Flameshot", "com.github.marktext.marktext",
               "org.darktable", "org.zaproxy.zap.ZAP",
               "com.BlueBubbles.BlueBubbles-Server", "org.winehq.wine-staging.wine"] {
        #expect(rule(id).installAssetPattern == nil, "\(id) must stay detection-only")
        #expect(rule(id).installerKind == nil, "\(id) must stay detection-only")
    }
    #expect(extract("release-5.6.0", "org.darktable") == "5.6.0")
    #expect(extract("11.15", "org.winehq.wine-staging.wine") == "11.15")
}

@Test func registryHasNoDuplicateBundleChannelPairs() {
    // Two rules for the same (bundle id, channel) would make which one applies
    // depend on registry order.
    var seen = Set<String>()
    for r in GitHubReleaseRegistry.rules {
        let key = "\(r.bundleID)|\(r.channel.rawValue)"
        #expect(!seen.contains(key), "duplicate rule for \(key)")
        seen.insert(key)
    }
}

// MARK: - 2026-08-16, second pass

/// RedisInsight tags without a leading `v` — the pattern must not require one,
/// and must still reject a tag that is only a bare number.
@Test func redisInsightRuleReadsAnUnprefixedTag() {
    #expect(extract("3.8.0", "org.RedisLabs.RedisInsight-V2") == "3.8.0")
    #expect(extract("v3.8.0", "org.RedisLabs.RedisInsight-V2") == nil)
    #expect(matches("Redis-Insight-mac-arm64.dmg", "org.RedisLabs.RedisInsight-V2"))
    #expect(!matches("Redis-Insight-mac-x64.dmg", "org.RedisLabs.RedisInsight-V2"))
}

/// Cherry Studio publishes Linux and Windows artifacts that also carry `arm64`
/// in their names, so the dmg extension is what separates them.
@Test func cherryStudioRulePicksTheDmgAmongArm64Siblings() {
    #expect(extract("v2.0.5", "com.kangfenmao.CherryStudio") == "2.0.5")
    #expect(matches("Cherry-Studio-2.0.5-arm64.dmg", "com.kangfenmao.CherryStudio"))
    for sibling in ["Cherry-Studio-2.0.5-arm64.AppImage", "Cherry-Studio-2.0.5-arm64.deb",
                    "Cherry-Studio-2.0.5-arm64-setup.exe", "Cherry-Studio-2.0.5-aarch64.rpm"] {
        #expect(!matches(sibling, "com.kangfenmao.CherryStudio"), "\(sibling) is not a Mac app")
    }
}

/// Rancher Desktop ships both a dmg and a `-mac.aarch64.zip`; the rule takes the
/// dmg, which is the artifact whose signature was verified.
@Test func rancherDesktopRuleTakesTheDmg() {
    #expect(extract("v1.24.0", "io.rancherdesktop.app") == "1.24.0")
    #expect(matches("Rancher.Desktop-1.24.0.aarch64.dmg", "io.rancherdesktop.app"))
    #expect(!matches("Rancher.Desktop-1.24.0-mac.aarch64.zip", "io.rancherdesktop.app"))
    #expect(!matches("Rancher.Desktop-1.24.0.x86_64.dmg", "io.rancherdesktop.app"))
}

/// Upscayl ships ONE universal dmg — no architecture token to match on. The
/// pattern must not grow one, and must still reject the zip beside it.
@Test func upscaylRuleMatchesTheUniversalDmg() {
    #expect(extract("v2.15.0", "org.upscayl.Upscayl") == "2.15.0")
    #expect(matches("upscayl-2.15.0-mac.dmg", "org.upscayl.Upscayl"))
    #expect(!matches("upscayl-2.15.0-mac.zip", "org.upscayl.Upscayl"))
    #expect(!matches("upscayl-2.15.0-mac.dmg.blockmap", "org.upscayl.Upscayl"))
}

/// WailBrew ships the app as a zip whose name repeats the `v` from the tag.
@Test func wailBrewRuleMatchesItsVersionedZip() {
    #expect(extract("v0.10.4", "io.github.wickenico.wailbrew") == "0.10.4")
    #expect(matches("wailbrew-v0.10.4.zip", "io.github.wickenico.wailbrew"))
    #expect(!matches("wailbrew-v0.10.4.zip.blockmap", "io.github.wickenico.wailbrew"))
}

/// Every rule added in this pass installs — none of them is detection-only —
/// and each one's kind matches the artifact that was actually verified.
@Test func secondPassRulesAllInstall() {
    let expected: [String: VendorInstallerKind] = [
        "io.rancherdesktop.app": .dmg,
        "com.kangfenmao.CherryStudio": .dmg,
        "org.RedisLabs.RedisInsight-V2": .dmg,
        "org.upscayl.Upscayl": .dmg,
        "io.github.wickenico.wailbrew": .zip,
    ]
    for (bundleID, kind) in expected {
        let r = rule(bundleID)
        #expect(r.installAssetPattern != nil, "\(bundleID) lost its asset pattern")
        #expect(r.installerKind == kind, "\(bundleID) installer kind drifted")
    }
}

/// The macOS-asset fallback added in 0.3.44 reaches for the releases *list* when
/// the latest release carries no macOS build. That endpoint is not "latest with
/// more rows": GitHub computes `/releases/latest` with prereleases excluded, and
/// every stable rule leans on that. Walked raw, the list would hand a stable
/// install a `-beta`/`-rc`/`-pre` build the first time a stable release shipped
/// without its dmg — the cross-channel mixing the channel gate exists to stop.
///
/// SwiftBar's real tag shapes: 22 of its recent releases are betas sitting above
/// older stables, so it is the registry entry this would have bitten first.
@Test func theListFallbackNeverContributesPrereleasesToAStableRule() throws {
    let json = """
    [
      {"tag_name":"v2.1.2-beta-3","prerelease":true,"draft":false,"assets":[]},
      {"tag_name":"v2.1.2-wip","prerelease":false,"draft":true,"assets":[]},
      {"tag_name":"v2.1.1","prerelease":false,"draft":false,"assets":[]},
      {"tag_name":"v2.1.0","prerelease":false,"draft":false,"assets":[]}
    ]
    """.data(using: .utf8)!

    let all = GitHubReleasesSource.releases(from: json, list: true)
    #expect(all.count == 4)
    // The decode has to carry the flags at all — reading them as false by
    // omission is how the filter silently becomes a no-op.
    #expect(all[0].isPrerelease)
    #expect(all[1].isDraft)

    let stable = GitHubReleasesSource.stableOnly(all)
    #expect(stable.map(\.tag) == ["v2.1.1", "v2.1.0"])
}

/// A release object that simply omits the flags (some proxies and older API
/// shapes do) must default to "released", not be dropped.
@Test func releasesMissingTheFlagsAreTreatedAsStable() throws {
    let json = #"[{"tag_name":"v1.0.0","assets":[]}]"#.data(using: .utf8)!
    let all = GitHubReleasesSource.releases(from: json, list: true)
    #expect(GitHubReleasesSource.stableOnly(all).map(\.tag) == ["v1.0.0"])
}
