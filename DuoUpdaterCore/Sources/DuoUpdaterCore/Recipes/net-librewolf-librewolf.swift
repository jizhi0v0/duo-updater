import Foundation

enum net_librewolf_librewolf {
    static let set = AppRecipeSet(
        family: "net-librewolf-librewolf",
        probes: [
        // LibreWolf — release tags, newest first; tag is "<firefox-version>-<packaging>"
        // (e.g. "151.0.3-1") and we capture only the upstream Firefox version so it
        // compares equal to the installed app's `CFBundleShortVersionString` (keeping
        // "-1" would read as a perpetual update). No auto-updater — genuinely useful.
        // Real installed bundle id is `net.librewolf.librewolf` (NOT
        // `org.mozilla.librewolf` — LibreWolf re-brands the Mozilla source). Version
        // source is **Codeberg**, not GitLab: LibreWolf migrated, and the old GitLab
        // repos are abandoned (project 44042130/bsys6 caps at 147.0.4 while current
        // is 151.x → a stale probe). The brew cask's own livecheck reads this same
        // Codeberg `releases/latest`. Verified 2026-06-04 against an installed cask:
        // app reports `151.0.3-1`; `tag_name` is `151.0.3-1` → captures `151.0.3`.
        //
        // DETECTION ONLY, and not for lack of a URL — the release does publish
        // `librewolf-<ver>-macos-arm64-package.dmg`. Checked it on 2026-08-09: the
        // `LibreWolf.app` inside is ad-hoc signed (`TeamIdentifier=not set`) and
        // Gatekeeper rejects it outright ("code has no resources but signature
        // indicates they must be present"). `VendorInstaller`'s same-Team gate would
        // refuse it anyway, and rightly: there is no signing identity to compare the
        // installed copy against. Don't wire one-click here unless LibreWolf starts
        // shipping a Developer ID build.
        VendorProbeRecipe(
            bundleID: "net.librewolf.librewolf",
            url: URL(string: "https://codeberg.org/api/v1/repos/librewolf/bsys6/releases/latest")!,
            mode: .responseBody,
            versionPattern: #""tag_name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"#,
            downloadURL: URL(string: "https://librewolf.net/installation/macos/"),
            changelogURL: URL(string: "https://codeberg.org/librewolf/bsys6/releases")),
        ])
}
