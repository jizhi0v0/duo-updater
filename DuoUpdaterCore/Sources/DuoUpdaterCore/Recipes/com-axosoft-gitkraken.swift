import Foundation

enum com_axosoft_gitkraken {
    static let set = AppRecipeSet(
        family: "com-axosoft-gitkraken",
        probes: [
        // History: docs/app-audits/com-axosoft-gitkraken.md#历史与实测
        // GitKraken Desktop — Electron, self-updating through Electron's own
        // `autoUpdater` (Squirrel.Mac: `Squirrel.framework` in the bundle, ShipIt
        // caches under `com.axosoft.gitkraken.ShipIt`). No `SUFeedURL`, no
        // `app-update.yml`, no GitHub releases; the Homebrew cask is
        // `auto_updates true`, so `HomebrewCaskSource` declines it by design.
        //
        // THE ENDPOINT is the one the app builds for itself (main bundle, read from
        // `app.asar`): base `https://release.gitkraken.com`, path
        // `darwin` + `-arm64` on Apple silicon + `/RELEASES`, query
        // `?v=<running version>&darwin=<os.release()>`. Squirrel's JSON answer is
        // `{"name":"<version>","url":"…/GitKraken-v<version>.zip"}`, or 204 when
        // the asked-for version is current. The probe leaves the query off: the
        // bare path answers the same JSON for everyone (no 204, no version in the
        // URL for `RecipeSanity` to trip on), and nothing device-specific is ever
        // sent, so this is the build every copy is offered — the same zip the
        // cask and the website download. `name` is the marketing version and
        // equals `CFBundleShortVersionString`; the bundle has no
        // `CFBundleVersion` at all, so this is not `versionIsBuild`.
        //
        // The pattern ends at the closing quote after digits and dots, so a
        // `-beta`/`-rc` string in `name` matches nothing (unknown, not a false
        // stable). The updater has no channel switch: the URL carries no channel
        // and `darwin-arm64-beta/RELEASES` is 404.
        //
        // ONE-CLICK installs the arm64 zip from a template on the compared string
        // (the same path the body's `url` names), so what was compared is what
        // gets downloaded. Developer ID, Team T7QVVUTZQ8, notarized, arm64 only.
        // The four `GitKraken Helper*.app` (`LSUIElement`) are Electron's stock
        // renderer/GPU/plugin child processes, started by the main process and
        // gone with it — no login item, LaunchAgent or daemon ships in the zip.
        // The body publishes no digest; the Team gate is the integrity check.
        //
        // EDITION CAVEAT: the vendor's on-premise "Serverless" (STANDALONE)
        // edition ships under the SAME bundle id, name, Info.plist and Team; only
        // `src/main/static/clientType.js` inside `app.asar` differs (`'NORMAL'` vs
        // `'STANDALONE'`). Detection answers both (the lines share version
        // numbers); one-click is withheld from any copy not provably NORMAL (the
        // `oneClickGates` entry below), since this build would swap its edition.
        VendorProbeRecipe(
            bundleID: "com.axosoft.gitkraken",
            url: URL(string: "https://release.gitkraken.com/darwin-arm64/RELEASES")!,
            mode: .responseBody,
            versionPattern: #""name"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.gitkraken.com/download"),
            changelogURL: URL(string: "https://help.gitkraken.com/gitkraken-desktop/current/"),
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://api.gitkraken.dev/releases/production/darwin/arm64/"
                    + "{version}/GitKraken-v{version}.zip"),
                kind: .zip)),
        ],
        changelogs: [
        // The help site's release-notes page (WordPress, server-rendered),
        // newest first. Each release is `<h2>…Version X.Y.Z</h2>`, optionally
        // followed by `<p><kbd>Weekday, Month Dth, YYYY</kbd></p>` (the newest
        // entry can lack it), then `<h3>` category headings (New ✨ /
        // Improvements 🙌 / Bug Fixes 🐛 / Known Issues) over `<ul>` lists, and
        // an `<hr />` before the next release. The body stops at the next `<h2>`
        // or `<hr`, so the page footer never becomes items.
        //
        // Some items nest a `<ul>` under a bold lead-in ("Live agent status
        // support for GitHub Copilot CLI:"). The item pattern stops each item at
        // the next `<li`, `</li>` or nested list, so the lead-in and every child
        // come out as separate lines instead of the lead-in swallowing the first
        // child. `<h3>`s are kept as headings.
        ChangelogRecipe(
            bundleID: "com.axosoft.gitkraken",
            source: URL(string: "https://help.gitkraken.com/gitkraken-desktop/current/")!,
            entryPattern:
                #"<h2[^>]*>(?:<a\b[^>]*>.*?</a>)?\s*Version\s+(?<version>[0-9]+(?:\.[0-9]+)+)\s*</h2>"#
                + #"\s*(?:<p>\s*<kbd>(?<date>[^<]+)</kbd>\s*</p>)?"#
                + #"(?<body>.*?)(?=<h2[\s>]|<hr\b|\z)"#,
            itemPatterns: [#"<li\b[^>]*>(?<item>(?:(?!<li\b|</li>|<ul\b|<ol\b).)+)"#],
            maxEntries: 20,
            headingPattern: #"<h3[^>]*>(?:<a\b[^>]*>.*?</a>)?\s*(?<heading>[^<]+?)\s*</h3>"#),
        ],
        oneClickGates: [
            // `src/main/static/clientType.js` is `module.exports = 'NORMAL';` in
            // the normal edition and `'STANDALONE'` in On-Premise Serverless
            // (both 12.6.0 packages, 2026-10-16); the download above is NORMAL.
            OneClickGate(
                bundleID: "com.axosoft.gitkraken",
                requirement: .asarEntry(
                    path: "src/main/static/clientType.js",
                    pattern: #"module\.exports\s*=\s*['"]NORMAL['"]"#),
                reason: "this is not the normal edition; On-Premise copies update from GitKraken's On-Premise download"),
        ])
}
