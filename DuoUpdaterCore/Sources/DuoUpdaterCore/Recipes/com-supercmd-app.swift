import Foundation

enum com_supercmd_app {
    static let set = AppRecipeSet(
        family: "com-supercmd-app",
        githubRules: [
        // SuperCmd v1 — the open-source Electron launcher (`SuperCmdLabs/SuperCmd`,
        // `com.supercmd.app`). Its `app-update.yml` says only `provider: github`,
        // which `ElectronManifestSource` deliberately does not turn into an address,
        // so without this rule a v1 copy reads as unknown. The vendor's tap cask is
        // `auto_updates true` and defers.
        //
        // v2 is a DIFFERENT app: closed-source, native, `com.supercmd.SuperCmd`, with
        // its own `SUFeedURL` into `SuperCmdLabs/supercmd-v2-releases`, so the generic
        // Sparkle source covers it and nothing here applies to it. The two version
        // lines overlap (both have a `1.0.7`), which is harmless only because they
        // never share a bundle id. See docs/app-audits/com-supercmd-SuperCmd.md.
        //
        // Anchored because the tags are bare `X.Y.Z` (every one of the 27, 2026-09-17)
        // and equal the bundle's `CFBundleShortVersionString`; the unanchored registry
        // default would also read a number out of any other tag shape.
        //
        // Detection-only, and not because it has to be: the 1.0.26 arm64 dmg is
        // Developer ID signed (Team T7HT4U4666) and notarized. The line has had no
        // release since 2026-06-20, so an install pattern was left for when someone
        // asks. `SupercmdGitHubRuleTests` pins the current shape.
        GitHubReleaseRule(
            bundleID: "com.supercmd.app",
            owner: "SuperCmdLabs", repo: "SuperCmd",
            versionPattern: #"^([0-9]+\.[0-9]+\.[0-9]+)$"#),
        ])
}
