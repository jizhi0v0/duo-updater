import Foundation

enum net_archagon_sensible_side_buttons {
    static let set = AppRecipeSet(
        family: "net-archagon-sensible-side-buttons",
        githubRules: [
        // SensibleSideButtons — menu-bar utility (LSUIElement) that turns mouse
        // side buttons into three-finger swipes through a CGEvent tap, so it
        // needs Accessibility. No updater of its own: no SUFeedURL, no Sparkle,
        // no network code in its source (its only URLs open the vendor's site
        // in the browser). No nested apps or login items: users add it to
        // Login Items by hand. Audit: docs/app-audits/net-archagon-sensible-side-buttons.md
        //
        // Tags read `1.0.7`; the bundle says 1.0.7 (build 5). Tags are plain
        // dotted, two-part `1.0` included. `SensibleSideButtons-1.0.7.dmg`,
        // the only asset in 1.0.7, is universal, Team R4MX2B96J2, notarized.
        // 1.0.6, 1.0.5 and 1.0 have the same id and Team (x86_64 only), so the
        // Team-ID gate serves every old copy. The designated requirement is
        // identical across 1.0.6, 1.0.7 and the 1.0.9 prerelease; that is what
        // a stored Accessibility grant is checked against.
        //
        // 1.0.9 is a GitHub prerelease on the same bundle id, shipped as
        // `SensibleSideButtons.app.zip`: /releases/latest skips it and the
        // install pattern does not match its name. A 1.0.9 copy reads as up to
        // date against 1.0.7 (no downgrade).
        GitHubReleaseRule(
            bundleID: "net.archagon.sensible-side-buttons",
            owner: "archagon", repo: "sensible-side-buttons",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^SensibleSideButtons-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
