import Foundation

enum com_youqu_todesk_mac {
    static let set = AppRecipeSet(
        family: "com-youqu-todesk-mac",
        probes: [
        // History: docs/app-audits/com-youqu-todesk-mac.md#历史与实测
        // ToDesk (远程控制) — Hainan Youqu's remote-desktop app. No standard source
        // resolves it; its in-app appcast sits behind a JS bot-challenge (the reason
        // it was long left "unknown"). The way in is the config API the public
        // download page itself renders from: `getConfig?type=1` answers JSON, a flat
        // list of `{"id":…,"type":1,"name":…,"value":…}` rows, one per client field.
        // ANCHOR ON THE EXACT ROW NAME `"name":"mac_version"`, both quotes: the
        // closing one keeps out `mac_version_gray`, the opening one keeps out
        // `daas_mac_version` (enterprise). Its value is the marketing version
        // (== CFBundleShortVersionString). Non-build recipe, one match, no
        // selectHighest.
        // GA vs gray: `mac_version` / `mac_link` is the release everyone gets.
        // `mac_version_gray` / `mac_link_gray` is a percentage rollout
        // (`mac_gray_percent`) that the page hands out per visitor by cookie, and
        // it can be NEWER than GA. Reading it would offer every install a build
        // the vendor gives only to that slice, so this recipe never reads a
        // `_gray` row.
        // Why not the download page: its Nuxt payload hoists repeated values into
        // positional arguments, so `mac_version:l` / `mac_link:n` are bare variables
        // and whether the GA pkg URL appears as a literal depends on whether some
        // other field happens to share it, while the gray link stayed a literal
        // ahead of it (History has the page as it was when this moved).
        // An unanchored `ToDesk_<digits>.pkg` pattern looks like it works on this
        // API too — its rows come in `id` order, and GA's `mac_link` happens to
        // precede `mac_link_gray` — but that is betting on document order again.
        // Copies already ahead of GA: an install that took a gray build compares
        // newer than this feed, so it is offered nothing until GA passes it, and
        // `duo verify` on that machine warns that the remote is behind the
        // installed copy (#628; History has how such copies came about).
        // One-click pkg install fills the URL from the RESOLVED version
        // (`versionTemplate`), so the pkg is always the release that was compared;
        // the template has the same shape as the API's `mac_link` value, and the
        // fixture test holds the two together. On the vendor's own dl.todesk.com,
        // signed by the same Team KM56KD59W4 (Hainan Youqu Technology) as the
        // installed app — the VendorInstaller signature gate enforces it.
        // No `changelogURL`: the vendor's macOS log page
        // (`update.todesk.com/macos/uplog.html`) was abandoned when checked
        // (2026-08-22, 2026-09-14) — its newest entry sat releases behind the
        // shipping app, while the same host's `windows/uplog.html` was current
        // (History has the versions). Pointing the pane at it would show notes for
        // a version the user passed releases ago, which is the version-mismatch
        // failure the Notion and Figma changelogs were just moved away from.
        VendorProbeRecipe(
            bundleID: "com.youqu.todesk.mac",
            url: URL(string: "https://www.todesk.com/api/config/getConfig?type=1")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"mac_version"\s*,\s*"value"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.todesk.com/download.html"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://dl.todesk.com/macos/ToDesk_{version}.pkg"),
                kind: .pkg)),
        ])
}
