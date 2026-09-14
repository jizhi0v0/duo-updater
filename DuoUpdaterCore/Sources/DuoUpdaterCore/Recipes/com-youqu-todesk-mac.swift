import Foundation

enum com_youqu_todesk_mac {
    static let set = AppRecipeSet(
        family: "com-youqu-todesk-mac",
        probes: [
        // History: docs/app-audits/com-youqu-todesk-mac.md#历史与实测
        // ToDesk (远程控制) — Hainan Youqu's remote-desktop app. No standard source
        // resolves it; its in-app appcast sits behind a JS bot-challenge (the reason
        // it was long left "unknown"). The public download page is the way in: a
        // Nuxt/Vue SPA whose macOS pkg URL is SERVER-RENDERED into the inline data
        // blob (no JS needed). ANCHOR ON THE `macos/` pkg FILENAME `ToDesk_<ver>.pkg`.
        // The vendor's macOS version fields are bare variables (e.g. `mac_version:l`,
        // no quoted digits), so the pkg filename is the one durable literal (History
        // has the quoted literal an earlier recipe keyed off, and when it went).
        // The DaaS (enterprise) pkg links on the page read `ToDesk_D…`, so
        // anchoring on `ToDesk_<digit>` excludes them. NB the positional-arg block
        // also carries release DATES (e.g. `2026.7.10`) ahead of the pkg URL —
        // never anchor on them; the real marketing version (==
        // CFBundleShortVersionString) lives in the filename. Non-build recipe,
        // first match, no selectHighest.
        // Gray channel: first-match takes whichever consumer `ToDesk_<digits>.pkg`
        // comes first in the body. When this anchor was written (2026-07-14) the GA
        // build was the only one. When checked again (2026-09-14; History has both
        // versions and the original note) the gray link (`mac_link_gray`) also
        // pointed at a `…/macos/ToDesk_<digits>.pkg` and came before GA, so the
        // recipe read the gray build — which was NEWER than GA, not the
        // stale-but-safe case an earlier version of this note assumed.
        // One-click pkg install rebuilds the URL from the captured filename version
        // (template), on the vendor's own dl.todesk.com, signed by the same Team
        // KM56KD59W4 (Hainan Youqu Technology) as the installed app — the
        // VendorInstaller signature gate enforces it.
        // No `changelogURL`: the vendor's macOS log page
        // (`update.todesk.com/macos/uplog.html`) was abandoned when checked
        // (2026-08-22, 2026-09-14) — its newest entry sat
        // releases behind the shipping app, while the same host's
        // `windows/uplog.html` was current (History has the versions). Pointing
        // the pane at it would show notes for a version the user passed releases
        // ago, which is the version-mismatch failure the Notion and Figma
        // changelogs were just moved away from.
        VendorProbeRecipe(
            bundleID: "com.youqu.todesk.mac",
            url: URL(string: "https://www.todesk.com/download.html")!,
            mode: .responseBody,
            versionPattern: #"ToDesk_([0-9]+(?:\.[0-9]+)+)\.pkg"#,
            downloadURL: URL(string: "https://www.todesk.com/download.html"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://dl.todesk.com/macos/ToDesk_{0}.pkg",
                    fields: [#"ToDesk_([0-9]+(?:\.[0-9]+)+)\.pkg"#]),
                kind: .pkg)),
        ])
}
