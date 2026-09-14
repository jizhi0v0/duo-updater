import Foundation

enum net_librewolf_librewolf {
    static let set = AppRecipeSet(
        family: "net-librewolf-librewolf",
        probes: [
        // History: docs/app-audits/net-librewolf-librewolf.md#历史与实测
        // LibreWolf — release tags, newest first; tag is "<firefox-version>-<packaging>"
        // (e.g. "151.0.3-1") and we capture only the upstream Firefox version so it
        // compares equal to the installed app's `CFBundleShortVersionString` (keeping
        // "-1" would read as a perpetual update). No auto-updater — genuinely useful.
        // Real installed bundle id is `net.librewolf.librewolf` (NOT
        // `org.mozilla.librewolf` — LibreWolf re-brands the Mozilla source). Version
        // source is **Codeberg**, not GitLab: LibreWolf migrated, and the old GitLab
        // repos are abandoned (project 44042130/bsys6 stopped releases behind the
        // current line → a stale probe; History has the versions). The brew cask's
        // own livecheck reads this same Codeberg `releases/latest` (History has the
        // dated check of an installed copy against a tag).
        //
        // DETECTION ONLY, and not for lack of a URL — the release does publish
        // `librewolf-<ver>-macos-arm64-package.dmg`, but when checked (2026-08-09;
        // History has Gatekeeper's message) the `LibreWolf.app` inside was ad-hoc
        // signed (`TeamIdentifier=not set`) and Gatekeeper rejected it outright.
        // `VendorInstaller`'s same-Team gate would
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
