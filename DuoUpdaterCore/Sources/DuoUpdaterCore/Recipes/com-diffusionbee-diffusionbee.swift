import Foundation

enum com_diffusionbee_diffusionbee {
    static let set = AppRecipeSet(
        family: "com-diffusionbee-diffusionbee",
        githubRules: [
        // DiffusionBee — local Stable Diffusion / Flux image generation, an
        // Electron app (divamgupta/diffusionbee-stable-diffusion-ui). No
        // Sparkle, no electron-updater: its "update check" only compares a
        // build number from checkupdates.diffusionbee.com and offers to open
        // diffusionbee.com, and that endpoint still answers 1.7.4, so GitHub
        // Releases is the only route that sees 2.x. No login items or helpers
        // beyond Electron's own Frameworks helpers.
        //
        // Tags are bare `2.5.3`, equal to CFBundleShortVersionString. The one
        // tag the pattern does not read, `weights`, is model weights
        // (`clip_tokenizer.zip`, `clip_transformer.zip`), not an app release:
        // left out on purpose.
        //
        // Each 2.x release ships `DiffusionBee_MPS_arm64-<v>.dmg` and an
        // `_Intel` twin; DuoUpdater runs on arm64 only, so the rule installs
        // the arm64 one. 1.7.4 through 2.5.3 are com.diffusionbee.diffusionbee,
        // Team 6QF6Z7X8UW, notarized. Up to 1.5.2 the app was
        // `com.linerai.liner` — the bundle id of the same developer's Liner.ai
        // too, same Team and overlapping versions — so those copies are not
        // filed here (no BundleIDMigration); see the audit doc.
        GitHubReleaseRule(
            bundleID: "com.diffusionbee.diffusionbee",
            owner: "divamgupta", repo: "diffusionbee-stable-diffusion-ui",
            versionPattern: #"^([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^DiffusionBee_MPS_arm64-[0-9]+(?:\.[0-9]+)+\.dmg$"#,
            installerKind: .dmg),
        ])
}
