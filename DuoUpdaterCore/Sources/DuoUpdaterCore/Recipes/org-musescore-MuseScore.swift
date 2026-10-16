import Foundation

/// MuseScore Studio 4 (`musescore/MuseScore`, Team 6EPAF2X3PR, notarized).
/// No SUFeedURL; the app's own checker reads `updates.musescore.org/feed/*.xml`,
/// which the vendor's `update_release_info.yml` fills from the GitHub release,
/// so GitHub is where the versions come from.
///
/// One bundle id, `org.musescore.MuseScore`, spans two majors that the vendor
/// ships as two apps meant to sit side by side: `MuseScore 3.app` (3.x, its
/// version reads `3.6.2.548020600`) and `MuseScore 4.app` (4.0 onward). The
/// packaging script names the app `MuseScore <major>`, and `version.cmake` on
/// `main` (5.0 in development) moves the next major to its own id,
/// `org.musescore.MuseScoreStudio5`. See docs/app-audits/org-musescore-MuseScore.md.
enum org_musescore_MuseScore {
    static let set = AppRecipeSet(
        family: "org-musescore-MuseScore",
        githubRules: [
        // MuseScore 4. Stable tags are `v4.7.5`, and two of them are two-part
        // (`v4.0`, `v4.5`). Prereleases are flagged on GitHub and carry a suffix
        // (`v4.6.0-beta`, `v4.0_rc`, `v4.2.0-beta.2`), which the anchored
        // pattern refuses as well.
        //
        // The major is pinned (exempt in `GitHubNextMajorTests.majorIsTheProduct`):
        // a 5.x release is a different app under a different bundle id, so a
        // 4.x copy must keep being served 4.x patch releases after 5.0 becomes
        // `/releases/latest`. Then the pinned version pattern refuses the 5.x
        // tag, the asset pattern finds no 4.x dmg on it, and the source walks
        // the stable list to the newest 4.x release. Re-check when 5.0 ships:
        // if it kept `org.musescore.MuseScore`, unpin.
        //
        // One-click: one universal dmg per release (`MuseScore-4.x.y.<build>.dmg`
        // through 4.2.1, `MuseScore-Studio-4.x.y.<build>.dmg` from 4.3.0), all
        // Developer ID 6EPAF2X3PR from 4.0.0 to 4.7.5. GitHub publishes a
        // `digest` for the recent assets.
        //
        // A MuseScore 3 copy has this same bundle id, so this rule answers for
        // it too and offers it the newest 4.x — as 3.6.2's own update feeds do
        // (`update.musescore.org/update_mac_stable.xml` says 4.0.0, the 3.x
        // Sparkle appcast 4.0.1, both saying installing 4 keeps 3). Detection
        // only for it (the `oneClickGates` entry below): the one-click would pass the bundle-id and Team gates
        // (same id, same Team 6EPAF2X3PR) and put MuseScore 4 in place of
        // `MuseScore 3.app`, while the vendor ships 4 beside 3 because 4 lays
        // old scores out differently. 3.x gets no more releases (3.6.2 is the
        // last, 2021-02-08), so there is nothing within 3.x to offer.
        //
        // Testing builds (the GitHub prereleases) also share the id, name the
        // app `MuseScore <x.y.z.build> Testing.app` and report a bare `4.6.0`;
        // they are detected as stable and offered the newest stable release.
        GitHubReleaseRule(
            bundleID: "org.musescore.MuseScore",
            owner: "musescore", repo: "MuseScore",
            versionPattern: #"^v(4(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^MuseScore(?:-Studio)?-4\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\.dmg$"#,
            installerKind: .dmg),
        ],
        oneClickGates: [
            OneClickGate(
                bundleID: "org.musescore.MuseScore",
                requirement: .installedVersion(pattern: #"^4\."#),
                reason: "MuseScore 4 installs beside MuseScore 3, not over it; download it from musescore.org"),
        ])
}
