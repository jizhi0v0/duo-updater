import Foundation

enum dev_commandline_waveterm {
    static let set = AppRecipeSet(
        family: "dev-commandline-waveterm",
        probes: [
        // MARK: - 2026-08-16 vendor batch
        //
        // Mainstream Homebrew casks with no Sparkle feed of their own. Every line
        // (this file, `Recipes/com-electron-kontena-lens.swift`, Termius stable in
        // `Recipes/com-termius-dmg-mac.swift`, `Recipes/com-unity3d-unityhub.swift`,
        // `Recipes/com-bjango-istatmenus.swift`, `Recipes/org-inkscape-Inkscape.swift`)
        // states what was read off the artifact the install spec actually
        // resolves to, on a mounted/expanded copy of the real download — bundle
        // id, `CFBundleShortVersionString` and `codesign`/`spctl` — because the
        // trap in this batch is never "no version anywhere", it is a version that
        // is not the same KIND of string the installed bundle reports.

        // Wave Terminal — electron-builder feed. Verified 2026-08-16: the zip
        // holds `Wave.app`, dev.commandline.waveterm, 0.14.5, Team M4LA8V687Y,
        // notarized — the same string the feed's `version:` carries.
        // snapshot-lint:allow — this dated verification stays in code: the batch block above says every named file states what was read off the artifact.
        //
        // The download is checked against the `sha512` (base64) of the `files:`
        // item whose `url:` is the arm64 zip the URL pattern reads — not the dmg
        // or x64 items (the feed repeats some of them). The checksum pattern stays
        // inside that one item whatever its key order; if the item has no
        // `sha512` it matches nothing rather than a neighbouring item's or the
        // top-level one. Unlike Signal's, this feed's digest describes the bytes
        // the CDN serves.
        // History: docs/app-audits/dev-commandline-waveterm.md#历史与实测
        VendorProbeRecipe(
            bundleID: "dev.commandline.waveterm",
            url: URL(string: "https://dl.waveterm.dev/releases-w2/latest-mac.yml")!,
            mode: .responseBody,
            versionPattern: #"^version:\s*([0-9][^\s]*)"#,
            downloadURL: URL(string: "https://waveterm.dev/download"),
            changelogURL: URL(string: "https://github.com/wavetermdev/waveterm/releases"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(Wave-darwin-arm64-[^\s]+\.zip)"#,
                    base: URL(string: "https://dl.waveterm.dev/releases-w2/")!),
                kind: .zip,
                checksumPattern:
                    #"\A(?:(?!Wave-darwin-arm64-[^\s]+\.zip)[\s\S])*?\n[ \t]*-[ \t](?=[^\n]*(?:\n[ \t]+(?![\s-])[^\n]*)*?Wave-darwin-arm64-[^\s]+\.zip)(?:[^\n]*\n[ \t]+(?![\s-]))*?sha512:[ \t]*([A-Za-z0-9+/=]+)"#)),
        ])
}
