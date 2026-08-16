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

@Test func localSendRuleStaysDetectionOnly() {
    #expect(extract("v1.18.1", "org.localsend.localsendApp") == "1.18.1")
    // Upstream marks a release latest while attaching only Android .apk artifacts
    // to it, so there is no macOS artifact to install from; the rule must stay
    // detection-only rather than resolve some other tag's dmg.
    #expect(rule("org.localsend.localsendApp").installAssetPattern == nil)
    #expect(rule("org.localsend.localsendApp").installerKind == nil)
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
/// pattern matches more than one asset and `installableAsset`'s first-arch-native-
/// match rule decides. This does NOT pin upstream's ordering (it can't — the list
/// is a fixture): it pins the *selection semantics* against the real 2.7.11 asset
/// list in the order GitHub returns it, alphabetical. The second respin case is
/// recorded below as a known issue rather than asserted away.
@Test func keepassxcRespinIsTheAssetSelected() {
    func assets(_ names: [String]) -> [(name: String, url: URL, size: Int64?)] {
        names.map { (name: $0, url: URL(string: "https://example.invalid/\($0)")!,
                     size: Int64?.none) }
    }
    let pattern = try! #require(rule("org.keepassxc.keepassxc").installAssetPattern)
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
    // Known gap: alphabetical order puts `-1-` before `-2-`, so a SECOND respin
    // would be passed over in favour of the first. Not reachable today (no release
    // has ever gone past `-1`), and bounded — same version, same Team, notarized —
    // but recorded so it reads as a known gap rather than as covered.
    withKnownIssue("installableAsset takes the first match, so a -2 respin loses to -1") {
        #expect(picked(["KeePassXC-2.7.11-1-arm64.dmg", "KeePassXC-2.7.11-2-arm64.dmg",
                        "KeePassXC-2.7.11-arm64.dmg"]) == "KeePassXC-2.7.11-2-arm64.dmg")
    }
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
        let pattern = try! #require(rule(bundleID).installAssetPattern)
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

/// The repo slug is the one part of a rule no other test touches: a typo or an
/// upstream rename leaves every pattern fixture green while detection is dead in
/// production. Pinned against the slugs verified live on 2026-08-16.
@Test func batchRuleSlugsArePinned() {
    let expected: [String: String] = [
        "com.ccswitch.desktop": "farion1231/cc-switch",
        "com.usebruno.app": "usebruno/bruno",
        "org.localsend.localsendApp": "localsend/localsend",
        "com.utmapp.UTM": "utmapp/UTM",
        "net.kovidgoyal.kitty": "kovidgoyal/kitty",
        "net.sourceforge.sqlitebrowser": "sqlitebrowser/sqlitebrowser",
        "com.jgraph.drawio.desktop": "jgraph/drawio-desktop",
        "io.podmandesktop.PodmanDesktop": "containers/podman-desktop",
        "com.bitwarden.desktop": "bitwarden/clients",
        "com.vscodium": "VSCodium/vscodium",
        "io.balena.etcher": "balena-io/etcher",
        "com.intelliscapesolutions.caffeine": "IntelliScape/caffeine",
        "org.godotengine.godot": "godotengine/godot",
        "org.keepassxc.keepassxc": "keepassxreboot/keepassxc",
        "com.sequel-ace.sequel-ace": "Sequel-Ace/Sequel-Ace",
        "com.ameba.SwiftBar": "swiftbar/SwiftBar",
        "io.ganeshrvel.openmtp": "ganeshrvel/openmtp",
        "com.microsoft.Headlamp": "headlamp-k8s/headlamp",
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
        "com.electron.goose": "block/goose",
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
