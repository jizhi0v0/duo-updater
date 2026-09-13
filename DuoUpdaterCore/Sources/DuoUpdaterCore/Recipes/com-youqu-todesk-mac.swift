import Foundation

enum com_youqu_todesk_mac {
    static let set = AppRecipeSet(
        family: "com-youqu-todesk-mac",
        probes: [
        // ToDesk (远程控制) — Hainan Youqu's remote-desktop app. No standard source
        // resolves it; its in-app appcast sits behind a JS bot-challenge (the reason
        // it was long left "unknown"). The public download page is the way in: a
        // Nuxt/Vue SPA whose macOS pkg URL is SERVER-RENDERED into the inline data
        // blob (no JS needed). ANCHOR ON THE `macos/` pkg FILENAME `ToDesk_<ver>.pkg`.
        // History: we used to key off a quoted `mac_version:"4.9.7.2"` literal, but
        // 2026-07-13 the vendor variable-ized every macOS version field
        // (`mac_version:l`, `mac_version_gray:l` — bare vars, no quoted digits), so
        // that anchor stopped matching → "probe resolved no version". The GA marketing
        // version now survives only in the positional-arg block
        // (`("",false,"-1","2026.7.10","…/macos/ToDesk_4.9.7.4.pkg",…`); the pkg
        // filename is the one durable literal. Two other pkg links share the page —
        // the DaaS (enterprise) GA `…/daas/mac/ToDesk_DaaS_v1.1.0.1.pkg` and its gray
        // `ToDesk_DaaS-v1.1.0.1_392.pkg` — but both read `ToDesk_D…`, so anchoring on
        // `ToDesk_<digit>` excludes them; the only `ToDesk_<digits>.pkg` on the page
        // is the consumer GA build. NB `2026.7.10` is a release DATE that precedes the
        // pkg URL — never anchor on it; the real marketing version (==
        // CFBundleShortVersionString) lives in the filename. Non-build recipe, first
        // match, no selectHighest.
        // Residual risk: if the vendor ever moves the consumer GRAY channel back to a
        // `ToDesk_<digits>.pkg` name that precedes GA in the body, first-match would
        // grab the (older) gray build — a stale-but-real version, i.e. under-reporting
        // rather than inventing an update (safe direction). Revisit then.
        // One-click pkg install rebuilds the GA URL from the captured filename version
        // (template), on the vendor's own dl.todesk.com, signed by the same Team
        // KM56KD59W4 (Hainan Youqu Technology) as the installed app — the
        // VendorInstaller signature gate enforces it.
        // No `changelogURL`: the vendor's macOS log page exists but is abandoned.
        // `update.todesk.com/macos/uplog.html` is server-rendered with 30 real
        // versions, and its newest is 4.8.1.0 (2025.9.5) — while the installed
        // copy here is 4.10.0.0. It is not the whole site going stale: the same
        // host's `windows/uplog.html` was current to 2026.8.18 on the same day.
        // Pointing the pane at it would show notes for a version the user passed
        // two minor releases ago, which is the version-mismatch failure the
        // Notion and Figma changelogs were just moved away from.
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
