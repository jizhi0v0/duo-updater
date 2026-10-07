import Foundation

enum app_getmoshi_desktop {
    static let set = AppRecipeSet(
        family: "app-getmoshi-desktop",
        probes: [
        // History: docs/app-audits/app-getmoshi-desktop.md#历史与实测
        // Moshi Go — the native (Go + Metal) rewrite of the Moshi desktop app. It
        // took over the bundle id `app.getmoshi.desktop`; the Tauri app it replaces
        // is `app.getmoshi.desktop.tauri` (`Recipes/app-getmoshi-desktop-tauri.swift`)
        // and has carried that id since its first build, so this recipe never
        // matches a Tauri install. The vendor's page labels Moshi Go "Alpha", but
        // it is its own product with its own feed and no second track: the
        // channel is stable for this bundle id.
        //
        // No Sparkle, no electron-builder config. The address is the one the app's
        // own updater reads (`desktop-go/update-darwin-<arch>.json`); only arm64
        // is published (the amd64 name 404s) and the build is arm64-only.
        //
        // The body is one release followed by `deltas[]` and `previous[]`, and
        // `previous[]` repeats `version`/`url` for older builds. Every pattern is
        // tempered so it cannot cross `"deltas"` or `"previous"`: version, date and
        // download all come from the top-level release, whatever order the keys
        // come in ahead of those two arrays.
        //
        // No rollout field: every install reads the same file, so the newest build
        // on the track is the one this machine is allocated.
        //
        // ONE-CLICK: the top-level `.tar.gz` holds `Moshi Go.app` alone (no
        // helpers, no login items), signed by Team FL442366Y7 and notarized. The
        // body's `signature` is the vendor's own ed25519 over the archive, not a
        // digest, so there is no `checksumPattern`; the Team-ID gate is the check.
        //
        // DELTAS: `deltas[]` are MyGo's `mygo delta 1` patches, read out of this
        // same body by `MyGoManifestDeltas` and applied by `MyGoDelta`. They are
        // cut against the `.tar.gz` build, which carries a stray
        // `Contents/CodeResources` the vendor's `.dmg` build lacks, and every patch
        // rebuilds that file from the installed one. So a copy installed from the
        // dmg cannot take a patch: it fails on that file and the install retries
        // with the full archive. A copy that came from the `.tar.gz` (this
        // recipe's one-click, or the app's own updater) takes the patch.
        //
        // `myGoPublicKey` is Moshi's MyGo update key, the string MyGo links into
        // the binary (`-X github.com/egoist/mygo.packageUpdateKey`). Every
        // `signature` in the feed, deltas and archives alike, verifies against it
        // over the file's SHA-256, so a patch whose signature does not is refused
        // and the install takes the full archive.
        VendorProbeRecipe(
            bundleID: "app.getmoshi.desktop",
            url: URL(string: "https://cdn.getmoshi.app/desktop-go/update-darwin-arm64.json")!,
            mode: .responseBody,
            versionPattern:
                #"\A(?:(?!"deltas"|"previous")[\s\S])*?"version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://getmoshi.app/desktop"),
            publishedAtPattern:
                #"\A(?:(?!"deltas"|"previous")[\s\S])*?"date"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"\A(?:(?!"deltas"|"previous")[\s\S])*?"url"\s*:\s*"(https://[^"]+\.tar\.gz)""#),
                kind: .tarGz,
                myGoPublicKey: "iXWMulHl+4m/dByqrJ8a1YOzcDIBeUOPiZ/AFj6k4VI=")),
        ],
        changelogs: [
        // Moshi Go — the vendor's release manifest, `desktop-go/latest/manifest.json`:
        // `releases[]` of `{version, notes, date}`, newest first, `notes` being
        // Markdown under a generic `## What's Changed` heading (dropped: it says
        // nothing). The update feed above carries the same notes for one release
        // only.
        //
        // Items run up to the next escaped newline (`\\n`), and the capture is
        // `(?:\\[^rn]|[^"\\])`, not `[^\\]`: it runs BEFORE the JSON unescape, so a
        // note containing `\"` or `\u2318` (⌘, which the notes use) would otherwise
        // be cut at the backslash. A bold lead-in (`- **Drawn on the GPU.** The
        // whole window…`) is consumed rather than shown with literal asterisks;
        // the sentence after it is the change.
        ChangelogRecipe(
            bundleID: "app.getmoshi.desktop",
            source: URL(string: "https://cdn.getmoshi.app/desktop-go/latest/manifest.json")!,
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
