import Foundation

enum io_github_obelus_editor_obelus {
    static let set = AppRecipeSet(
        family: "io-github-obelus-editor-obelus",
        githubRules: [
        // Shared rationale for digest-only: Recipes/org-alacritty.swift.

        // Obelus — Rust code editor (`obg` in a window; `ob` is the terminal
        // twin and ships as a separate archive). No Sparkle and no updater of
        // its own: `crates/obelus-app/src/app/project/releases.rs` only asks
        // GitHub's `releases/latest` once a day and says so on the welcome
        // screen. v-tags; the release workflow refuses a tag that is not `v` +
        // Cargo.toml's version, and the bundle carries that version in both
        // CFBundleShortVersionString and CFBundleVersion.
        //
        // Ad-hoc signed, no Team ID, from v0.9.0 (the first release) on;
        // `codesign --sign -` takes the identifier from Info.plist, so the
        // signed identifier is the bundle id, the seal verifies
        // (`--deep --strict`), and GitHub publishes a sha256 for every asset.
        // Hence `.publishedDigestOnly`. If the vendor starts signing with a
        // Developer ID, an ad-hoc copy is refused once (`teamIdentifierAppeared`)
        // and this rule has to move to the Team-ID route.
        //
        // One universal2 `.app.zip` per release next to the `ob-`/`obg-`
        // tar.xz archives, Linux packages and Windows MSIs; the pattern takes
        // only the `.app.zip`. The anchored version pattern leaves out a
        // `-rc`/`-beta` tag (the workflow allows a suffixed tag).
        GitHubReleaseRule(
            bundleID: "io.github.obelus-editor.obelus",
            owner: "obelus-editor", repo: "obelus",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^Obelus-[0-9]+\.[0-9]+\.[0-9]+-universal2-apple-darwin\.app\.zip$"#,
            installerKind: .zip,
            installTrust: .publishedDigestOnly),
        ])
}
