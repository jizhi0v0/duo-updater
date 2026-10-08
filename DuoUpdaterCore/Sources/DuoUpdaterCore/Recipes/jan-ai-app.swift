import Foundation

enum jan_ai_app {
    static let set = AppRecipeSet(
        family: "jan-ai-app",
        githubRules: [
        // Jan ships a universal macOS zip whose app reports the release tag's
        // version verbatim. Mounted/extracted zip: jan.ai.app, Team F8AH6NHVY5,
        // notarized. Pin the desktop asset; the same release carries source and
        // dependency archives plus Linux/Windows builds.
        //
        // From 0.8.5 the bundled local-model engine
        // (`Contents/Resources/resources/bin/jan-llama-worker`) is arm64-only
        // while the main executable stays universal, so neither the asset name
        // nor install-time gate 5 sees it. The vendor's 0.8.5 notes tell Intel
        // users who rely on local models to stay on v0.8.4, so an Intel Mac is
        // offered the newest release below 0.8.5 instead.
        GitHubReleaseRule(
            bundleID: "jan.ai.app",
            owner: "janhq", repo: "jan",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^jan-mac-universal-[0-9.]+\.zip$"#,
            installerKind: .zip,
            architectureRequirement: GitHubArchitectureRequirement(
                fromVersion: "0.8.5", architectures: [.arm64])),
        ])
}
