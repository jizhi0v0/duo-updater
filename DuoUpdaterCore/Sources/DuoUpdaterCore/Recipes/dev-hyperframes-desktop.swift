import Foundation

enum dev_hyperframes_desktop {
    /// The channel's release folder, as the app's own `shared/channel.mjs` names it
    /// (`releases`): prod at the root, Canary under `canary/`.
    static func folder(_ channel: ReleaseChannel) -> String {
        channel == .canary
            ? "https://static.heygen.ai/hyperframes-oss/desktop/canary"
            : "https://static.heygen.ai/hyperframes-oss/desktop"
    }

    // HyperFrames (HeyGen) — an Electron app that updates itself without Squirrel's
    // feed or electron-updater: its `main/releaseUpdates.mjs` reads `latest.json`
    // from the channel's folder, takes the build it names, checks it (Team
    // 2VW993BDT8, notarized, this channel's bundle id) and swaps it in. No
    // `SUFeedURL` and no `app-update.yml`, so no generic source covers it; this
    // probe reads that same file.
    //
    // HyperFrames and HyperFrames Canary are two apps (`dev.hyperframes.desktop`,
    // `dev.hyperframes.desktop.canary`), each with its own folder, so each recipe
    // reads only its own channel's builds.
    //
    // The version is the BUILD, in the vendor namespace. Every build says `0.1.0`
    // in both `CFBundleShortVersionString` and `CFBundleVersion`; what changes is
    // the `HFBuildLabel` Info.plist key (`b271`), which `AppScanner` reads into
    // `vendorBuildVersion` as its number (`271`) — the number is what the app's
    // own updater orders by. A copy without the key compares as "cannot tell",
    // never against `0.1.0`.
    //
    // The patterns take the TOP-LEVEL build, the one followed by `"sha"`. The
    // file also names a `build` inside its `linux` and `deb` blocks, which "may be
    // an earlier build than the release that names it" (the app's own comment on
    // a recovery release); those are followed by `}`, so the patterns cannot land
    // on them. The top level is the universal app, which is what the app's older
    // updaters install too; the `arm64`/`x64` blocks are thinner copies of the same
    // build and are not used.
    //
    // There is one file per channel and no per-device key, so this reads what
    // every copy on the channel is offered, which is also what the vendor's
    // download page serves.
    //
    // One-click: the zip holds only this channel's `HyperFrames.app` (the app's
    // installer refuses anything else). The zip is checked against the sha256
    // `latest.json` names for it (hex, the same check the app's own installer
    // makes), on top of the mandatory Team-ID gate. The checksum pattern walks the
    // same top-level chain as the URL (`build`, `sha`, `url`, `bytes`, `sha256`),
    // so it cannot pick up the `delta`, `dmg`, per-architecture or Linux digests
    // that follow. The vendor's own delta (`delta/manifest-<build>.json` and
    // `blobs/`) is its own format, not Sparkle's, and is not read.
    static func probe(_ channel: ReleaseChannel) -> VendorProbeRecipe {
        let folder = folder(channel)
        let escaped = NSRegularExpression.escapedPattern(for: folder)
        return VendorProbeRecipe(
            bundleID: channel == .canary ? "dev.hyperframes.desktop.canary" : "dev.hyperframes.desktop",
            url: URL(string: "\(folder)/latest.json")!,
            mode: .responseBody,
            versionPattern: #""build"\s*:\s*"b([0-9]+)"\s*,\s*"sha""#,
            downloadURL: URL(string: channel == .canary
                ? "https://dev.hyperframes.dev/studio/download"
                : "https://hyperframes.dev/studio/download"),
            versionIsBuild: true,
            buildNamespace: .vendor,
            displayVersionPattern: #""build"\s*:\s*"(b[0-9]+)"\s*,\s*"sha""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""build"\s*:\s*"b[0-9]+"\s*,\s*"sha"\s*:\s*"[0-9a-f]{40}"\s*,\s*"url"\s*:\s*"("#
                        + escaped + #"/HyperFrames-b[0-9]+-[0-9a-f]+\.zip)""#),
                kind: .zip,
                checksumPattern:
                    #""build"\s*:\s*"b[0-9]+"\s*,\s*"sha"\s*:\s*"[0-9a-f]{40}"\s*,\s*"url"\s*:\s*""#
                        + escaped + #"/HyperFrames-b[0-9]+-[0-9a-f]+\.zip"\s*,\s*"bytes"\s*:\s*[0-9]+\s*,\s*"sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex),
            channel: channel)
    }

    // The notes are the app's own What's New, one JSON file per build beside
    // `latest.json` (see `StructuredFormat.hyperFramesWhatsNew`). `source` is
    // `latest.json` only as the fixed fallback a template recipe needs; it is not
    // a notes document and decodes to nothing.
    static func changelog(_ channel: ReleaseChannel) -> ChangelogRecipe {
        let folder = folder(channel)
        return ChangelogRecipe(
            bundleID: channel == .canary ? "dev.hyperframes.desktop.canary" : "dev.hyperframes.desktop",
            source: URL(string: "\(folder)/latest.json")!,
            mode: .json,
            maxEntries: 1,
            channel: channel == .canary ? .canary : nil,
            sourceTemplate: "\(folder)/whats-new-{version}.json",
            structuredFormat: .hyperFramesWhatsNew)
    }

    static let set = AppRecipeSet(
        family: "dev-hyperframes-desktop",
        probes: [probe(.stable), probe(.canary)],
        changelogs: [changelog(.stable), changelog(.canary)],
        channelProofs: [
        ChannelProofKey("dev.hyperframes.desktop.canary", .canary):
            .artifact(#"/hyperframes-oss/desktop/canary/HyperFrames-b"#),
        ])
}
