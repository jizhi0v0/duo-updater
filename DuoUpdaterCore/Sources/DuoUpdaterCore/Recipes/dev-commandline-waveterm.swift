import Foundation

enum dev_commandline_waveterm {
    static let set = AppRecipeSet(
        family: "dev-commandline-waveterm",
        probes: [
        // MARK: - 2026-08-16 vendor batch
        //
        // Mainstream Homebrew casks with no Sparkle feed of their own. Every line
        // states what was read off the artifact the install spec actually
        // resolves to, on a mounted/expanded copy of the real download — bundle
        // id, `CFBundleShortVersionString` and `codesign`/`spctl` — because the
        // trap in this batch is never "no version anywhere", it is a version that
        // is not the same KIND of string the installed bundle reports.

        // Wave Terminal — electron-builder feed. Verified 2026-08-16: the zip
        // holds `Wave.app`, dev.commandline.waveterm, 0.14.5, Team M4LA8V687Y,
        // notarized — the same string the feed's `version:` carries.
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
                kind: .zip)),
        ])
}
