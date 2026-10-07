import Foundation

enum app_getmoshi_desktop_tauri {
    static let set = AppRecipeSet(
        family: "app-getmoshi-desktop-tauri",
        probes: [
        // History: docs/app-audits/app-getmoshi-desktop-tauri.md#历史与实测
        // Moshi — the Tauri desktop app (`app.getmoshi.desktop.tauri` since its
        // first build). Its native rewrite, Moshi Go, is a separate bundle id with
        // its own feed (`Recipes/app-getmoshi-desktop.swift`).
        //
        // No Sparkle, no electron-builder config. The address is the Tauri
        // updater endpoint baked into the binary, `desktop/latest.json`: one
        // `version`, one `pub_date`, and a `platforms` map. Only the top level
        // carries a version, so a plain first match is the release.
        //
        // No rollout field: every install reads the same file, so the newest build
        // on the track is the one this machine is allocated.
        //
        // ONE-CLICK: the `darwin-aarch64` entry's `Moshi.app.tar.gz` (the
        // `darwin-x86_64` entry sits beside it, and Windows/Linux after), bound to
        // its own object. Signed by Team FL442366Y7 and notarized; the
        // `moshi-desktop-bridge` sidecar sits in `Contents/MacOS` and is started by
        // the app, not a login item. The `signature` is Tauri's minisign over the
        // archive, not a digest, so there is no `checksumPattern`.
        VendorProbeRecipe(
            bundleID: "app.getmoshi.desktop.tauri",
            url: URL(string: "https://cdn.getmoshi.app/desktop/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://getmoshi.app/desktop"),
            publishedAtPattern: #""pub_date"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""darwin-aarch64"\s*:\s*\{[^{}]*?"url"\s*:\s*"([^"]+)""#),
                kind: .tarGz)),
        ],
        changelogs: [
        // Moshi — `desktop/latest/manifest.json`, the same `{latest, releases[]}`
        // shape as Moshi Go's and read the same way; see
        // `Recipes/app-getmoshi-desktop.swift` for why the item capture is
        // `(?:\\[^rn]|[^"\\])` and why a bold lead-in is consumed.
        ChangelogRecipe(
            bundleID: "app.getmoshi.desktop.tauri",
            source: URL(string: "https://cdn.getmoshi.app/desktop/latest/manifest.json")!,
            entryPattern:
                #"\{\s*"version"\s*:\s*"(?<version>[0-9][^"]*)""#
                + #"(?:(?!"version"\s*:)[\s\S])*?"notes"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#
                + #"(?:(?!"version"\s*:)[\s\S])*?"date"\s*:\s*"(?<date>[^"]+)""#,
            itemPatterns: [
                #"\\n[-*] (?:\*\*(?:\\[^rn]|[^"\\*])+\*\*\s*)?(?<item>(?:\\[^rn]|[^"\\])+)"#,
            ],
            mode: .json,
            stripTags: false,
            markdownSource: true,
            maxEntries: 20),
        ])
}
