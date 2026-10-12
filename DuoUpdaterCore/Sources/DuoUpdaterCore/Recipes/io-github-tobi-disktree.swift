import Foundation

enum io_github_tobi_disktree {
    static let set = AppRecipeSet(
        family: "io-github-tobi-disktree",
        githubRules: [
        // Shared rationale for digest-only: Recipes/org-alacritty.swift.

        // disktree — Rust + GPUI disk-usage viewer. No Sparkle and no updater of
        // its own (no update check anywhere in its source). v-tags; the release
        // workflow refuses a tag that is not `v` + Cargo.toml's version, and
        // `cargo xtask bundle` writes that version into both
        // CFBundleShortVersionString and CFBundleVersion.
        //
        // Ad-hoc signed, no Team ID: the workflow signs with a Developer ID and
        // notarizes only when the repository has those secrets, and so far it
        // has not. `codesign --sign -` takes the identifier from Info.plist, so
        // the signed identifier is the bundle id; the seal verifies
        // (`--deep --strict`), and GitHub publishes a sha256 for every asset.
        // Hence `.publishedDigestOnly`. If the vendor starts signing with a
        // Developer ID, an ad-hoc copy is refused once (`teamIdentifierAppeared`)
        // and this rule has to move to the Team-ID route.
        //
        // One release carries Linux, Windows and macOS builds for two arches,
        // each with a `.sha256` sidecar: `disktree-<v>-{aarch64,x86_64}-macos.zip`.
        // The pattern takes both macOS zips and nothing else, and the asset
        // selector reads `aarch64` / `x86_64` as the arch markers. v0.9.x are
        // Linux-only releases; a release without a matching zip is walked past,
        // never offered.
        GitHubReleaseRule(
            bundleID: "io.github.tobi.disktree",
            owner: "tobi", repo: "disktree",
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^disktree-[0-9]+\.[0-9]+\.[0-9]+-(?:aarch64|x86_64)-macos\.zip$"#,
            installerKind: .zip,
            installTrust: .publishedDigestOnly),
        ])
}
