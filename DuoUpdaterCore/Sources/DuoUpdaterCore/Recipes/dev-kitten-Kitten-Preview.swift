import Foundation

enum dev_kitten_Kitten_Preview {
    static let set = AppRecipeSet(
        family: "dev-kitten-Kitten-Preview",
        probes: [
        // History: docs/app-audits/dev-kitten-Kitten-Preview.md#历史与实测
        // Kitten Preview — an API client built on Zed's GPUI, and it updates the
        // way Zed does: one bundle id per channel (`dev.kitten.Kitten`,
        // `dev.kitten.Kitten-Preview`, `dev.kitten.Kitten-Dev` are all named in
        // the binary), no Sparkle, and its own updater asks the vendor's release
        // service for the newest asset of its channel. `ReleaseChannel.detect`
        // reads the `-Preview` suffix as `.preview`, so this recipe is
        // channel-gated to match.
        //
        // THE ENDPOINT is the updater's own request: it sends
        // `GET …/releases/preview/latest/asset?asset=kitten-macos-aarch64.dmg&os=macos&arch=aarch64`
        // with User-Agent `Kitten Auto Updater` (seen by pointing its
        // `KITTEN_UPDATE_API_URL` hook at a local server), and the service answers
        // `{"version":"0.1.0","url":"…/releases/preview/0.1.0/download?asset=…"}`.
        // `version` is the marketing string, equal to the bundle's
        // `CFBundleShortVersionString` (and `CFBundleVersion`). No device id is
        // sent, so this is the newest build on the track — the same one the
        // download page links. The arm64 query is fine for an Intel copy too: the
        // service versions a release, not an asset.
        //
        // DETECTION ONLY, no install spec, and none is possible today: the macOS
        // builds are ad-hoc linker-signed (no Team ID, signed identifier `kitten`,
        // no sealed resources, so `codesign --verify` itself fails), and the
        // service publishes no digest. That fails gate 2 and gate 3, and the
        // digest-only route has nothing to check against. The vendor's release
        // notes say the macOS builds are unsigned.
        //
        // Stable answers `404 {"error":"release channel \"stable\" is not
        // available"}` — there is no stable track yet, so no stable recipe.
        VendorProbeRecipe(
            bundleID: "dev.kitten.Kitten-Preview",
            url: URL(string: "https://api.kittenapi.com/releases/preview/latest/asset?asset=kitten-macos-aarch64.dmg&os=macos&arch=aarch64")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.kittenapi.com/download"),
            changelogURL: URL(string: "https://www.kittenapi.com/releases/preview"),
            channel: .preview),
        ],
        changelogs: [
        // The Preview releases page, server-rendered by SvelteKit: one
        // `<article class="release" id="kitten-<version>">` per release, the
        // version and date in its `<header>`, then the asset links, then
        // `<div class="notes">` — an intro `<p>` and `<h2>`-headed `<ul>` lists.
        // The body stops at the notes' own `</div></article>`, so the asset links
        // never become items. Paragraphs and list items are both items, and the
        // `<h2>`s are kept as headings.
        ChangelogRecipe(
            bundleID: "dev.kitten.Kitten-Preview",
            source: URL(string: "https://www.kittenapi.com/releases/preview")!,
            entryPattern:
                #"<article class="release[^"]*"[^>]*>\s*<header[^>]*>\s*"#
                + #"<span class="ver[^"]*">(?<version>[^<]+)</span>\s*"#
                + #"(?:<span[^>]*>(?<date>[^<]*)</span>)?"#
                + #".*?<div class="notes[^"]*">(?<body>.*?)</div>\s*</article>"#,
            itemPatterns: [#"<(li|p)\b[^>]*>(?<item>.*?)</\1>"#],
            maxEntries: 15,
            channel: .preview,
            headingPattern: #"<h2[^>]*>(?<heading>[^<]*)</h2>"#),
        ])
}
