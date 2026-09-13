import Foundation

enum com_electron_ollama {
    static let set = AppRecipeSet(
        family: "com-electron-ollama",
        changelogs: [
        // Ollama — GitHub releases page. Each release is a <section> with an
        // sr-only h2 (version tag, e.g. "v0.30.0"), a <relative-time> element
        // (ISO datetime), and a <div class="markdown-body …"> with the release
        // body. The version group strips the leading "v" by not capturing it.
        // Only <h2> values matching v+digits are captured so nav sections skip.
        //
        // Most releases are a bullet list, but some are written as prose with no
        // <li> at all — v0.34.0 and v0.32.12 on the live page, 2026-09-11. An entry
        // that yields no items is dropped, so the newest release vanished from the
        // pane and `duo verify` read the changelog as a whole release behind
        // (#507). Item patterns are tried in order and the first that yields
        // anything wins, so the paragraph fallback only ever speaks for a release
        // with no bullets. It skips the "Full Changelog: vA...vB" compare-link line
        // (all ten releases on the page that day end with it), which would
        // otherwise be a prose release's last item.
        ChangelogRecipe(
            bundleID: "com.electron.ollama",
            source: URL(string: "https://github.com/ollama/ollama/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>v(?<version>[\d.]+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [
                #"<li>(?<item>.*?)</li>"#,
                #"<p>(?!<strong>Full Changelog</strong>)(?<item>.*?)</p>"#,
            ]),
        ],
        githubRules: [
        // Ollama — Electron app distributed via an `auto_updates` Homebrew cask,
        // which falls through `HomebrewCaskSource` and leaves no `SUFeedURL`, so
        // the installed copy drifts (0.24.0 while GitHub ships v0.30.6) with no
        // detection source — only a changelog recipe. The macOS app is the same
        // GitHub `/releases/latest`: ollama.com/install.sh and ollama.com/download
        // both 307→ github releases/latest/download (`Ollama-darwin.zip` / the
        // `Ollama.dmg` asset). Tags carry a `v` prefix (`v0.30.6`), stripped by the
        // default pattern → `0.30.6`. Verified end-to-end 2026-06-06: the .app inside
        // the latest zip self-reports CFBundleShortVersionString 0.30.6 (homogeneous,
        // no ghost update). Stable channel, no prereleases (`/releases/latest`).
        //
        // Best-effort one-click: the `Ollama-darwin.zip` asset IS a notarized
        // Developer ID build, Team 3MU9H2V9Y9 (Infra Technologies) matching the
        // install, so the in-place swap passes the VendorInstaller Team-ID gate.
        // Ollama ships its own updater, but it drifts in practice (seen stuck on
        // 0.24.0 while GitHub was on v0.30.6), so rather than refuse to act we offer
        // the swap as a fallback when its updater hasn't kept up. The zip wraps
        // `Ollama.app`, swapped in place like the other zip recipes. Ollama runs a
        // background `ollama serve`, so after the swap the live process is still the
        // old build and the row lands in `needsRestart` → the standard Restart action
        // quits every `com.electron.ollama` instance and reopens it on the new build.
        GitHubReleaseRule(
            bundleID: "com.electron.ollama",
            owner: "ollama", repo: "ollama",
            installAssetPattern: #"^Ollama-darwin\.zip$"#,
            installerKind: .zip),
        ],
        changelogPages: [
        // Ollama — auto_updates cask, Electron app; GitHub releases.
        "com.electron.ollama": URL(string: "https://github.com/ollama/ollama/releases")!,
        ])
}
