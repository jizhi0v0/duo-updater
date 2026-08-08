import Testing
import Foundation
@testable import DuoUpdaterCore

// Each rule's versionPattern is applied to a release `tag_name` exactly like the
// pure helper VendorProbeRecipe.extractVersion (capture group 1, else whole
// match). These fixtures pin the pattern against the REAL tag formats observed
// on each repo, so a future pattern edit that breaks extraction fails loudly.

private func rule(_ bundleID: String) -> GitHubReleaseRule {
    GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID }!
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
