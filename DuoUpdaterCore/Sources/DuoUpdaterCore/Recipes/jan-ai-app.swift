import Foundation

enum jan_ai_app {
    static let set = AppRecipeSet(
        family: "jan-ai-app",
        probes: [
        // Jan nightly — its own bundle id (`jan-nightly.ai.app`, app name
        // `Jan-nightly`), so it never shares a key with stable. Nightlies are not
        // published on GitHub; the feed is the Tauri updater endpoint the nightly
        // build carries, `delta.jan.ai/nightly/latest.json`: one top-level
        // `version`, one `pub_date`, and a `platforms` map. The `version`
        // (`<release>-<build>`) is the bundle's `CFBundleShortVersionString`
        // verbatim; the pattern requires the `-<build>` suffix so a stable-shaped
        // value is not read as a nightly.
        //
        // One-click: each `darwin-<arch>` entry names a `.app.tar.gz` (the archive
        // Jan's own updater installs), notarized and signed by Team F8AH6NHVY5 like
        // stable. One recipe per architecture, split by `hostRequirement` so
        // exactly one runs on any Mac and each reads only its own entry. The
        // `signature` is Tauri's minisign over the archive, not a digest, so
        // there is no `checksumPattern`.
        nightlyRecipe(arch: .arm64),
        nightlyRecipe(arch: .x86_64),
        ],
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
        ],
        channelProofs: [
        // The archive's own path and name carry the channel.
        ChannelProofKey("jan-nightly.ai.app", .nightly): .artifact(#"/nightly/Jan-nightly_"#),
        ])

    /// The nightly recipe for one architecture's `platforms` entry.
    static func nightlyRecipe(arch: HostArch) -> VendorProbeRecipe {
        let platform = arch == .arm64 ? "darwin-aarch64" : "darwin-x86_64"
        return VendorProbeRecipe(
            bundleID: "jan-nightly.ai.app",
            url: URL(string: "https://delta.jan.ai/nightly/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+-[0-9]+)""#,
            downloadURL: URL(string: "https://app.jan.ai/download/nightly/mac-universal"),
            publishedAtPattern: #""pub_date"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""\#(platform)"\s*:\s*\{[^{}]*?"url"\s*:\s*"(https://delta\.jan\.ai/nightly/Jan-nightly_[^"/]+\.app\.tar\.gz)""#),
                kind: .tarGz),
            channel: .nightly,
            variant: arch == .arm64 ? "arm64" : "x86_64",
            hostRequirement: VendorHostRequirement(architectures: [arch]))
    }
}
