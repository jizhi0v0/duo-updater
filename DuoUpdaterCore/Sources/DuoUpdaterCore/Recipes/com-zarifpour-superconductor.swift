import Foundation

enum com_zarifpour_superconductor {
    static let set = AppRecipeSet(
        family: "com-zarifpour-superconductor",
        probes: [
        // super.engineering (Superconductor) — `latest.json` is the manifest the
        // app's own updater reads (the URL, the `superconductor-updater` UA and
        // "nightly entry missing valid sha" all sit in its binary). Shape,
        // 2026-09-10:
        //   {"nightly": {"sha": "<40 hex>", "url": "https://releases.superconductor.so/
        //     nightly/Superconductor-nightly-<sha8>-arm64.dmg", "sha256": "<hex>",
        //     "date": "2026-09-10"}}
        //
        // The version IS a commit hash. The bundle reports its first eight hex
        // digits as both `CFBundleShortVersionString` and `CFBundleVersion`
        // ("8545a7d8"), so the pattern captures exactly those eight: all forty would
        // never equal the bundle's string and would read as newer forever. Hashes
        // have no order, so `buildLineage` reads it from `changelog.json` — every
        // published build, newest first, and the same document the release notes
        // come from. See `BuildLineage` for what `VersionComparator` does instead.
        //
        // Channel: `.nightly`, the app's own name for it. The vendor retired its
        // stable track (#711 in its own changelog, 2026-04-05) and the app's Settings
        // say "Nightly is currently the only release track available" — but the
        // picker is still there, and its choice is `update_channel` in
        // `~/.superconductor/settings.json`. `SuperconductorChannel` reads it, so a
        // copy set to anything but nightly resolves to a channel with no recipe and
        // is never offered this build. Every pattern below is anchored inside the
        // manifest's `"nightly"` object for the same reason: the updater looks its
        // entry up by channel name ("nightly entry missing from release manifest"),
        // so a second track would arrive as a sibling key, and first-match would
        // take whichever the vendor happened to list first.
        //
        // One-click: the dmg `url` names, Developer ID Team MR38E36N26, notarized
        // (the 2026-09-10 build, mounted and checked). `sha256` is a hex SHA-256,
        // which `checksumPattern` (base64 SHA-512) cannot consume, so the Team gate
        // stands in. arm64-only (the filename says so and `lipo` agrees);
        // `LSMinimumSystemVersion` 14.0.
        //
        // Reads the newest build on the only track — the dmg the site's own
        // Download button (`super.engineering/api/download`, a 302 to the same URL
        // on 2026-09-10) and the app's updater hand every user.
        VendorProbeRecipe(
            bundleID: "com.zarifpour.superconductor",
            url: URL(string: "https://releases.superconductor.so/latest.json")!,
            mode: .responseBody,
            versionPattern:
                #""nightly"\s*:\s*\{[^{}]*?"sha"\s*:\s*"([0-9a-f]{8})[0-9a-f]{32}""#,
            downloadURL: URL(string: "https://super.engineering/"),
            publishedAtPattern:
                #""nightly"\s*:\s*\{[^{}]*?"date"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2})""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""nightly"\s*:\s*\{[^{}]*?"url"\s*:\s*"(https://releases\.superconductor\.so/[^"]+-arm64\.dmg)""#),
                kind: .dmg),
            channel: .nightly,
            hostRequirement: VendorHostRequirement(
                minimumSystemVersion: "14.0", architectures: [.arm64]),
            buildLineage: .init(
                url: URL(string: "https://releases.superconductor.so/changelog.json")!,
                entryPattern: #""version"\s*:\s*"([0-9a-f]{8})[0-9a-f]*""#)),
        ],
        changelogs: [
        // super.engineering — the same `changelog.json` the app's own "What's New
        // in Nightly" reads (that URL sits next to the string in the binary), and
        // the same document the vendor probe reads its release ORDER from. Every
        // release lists its commits under the vendor's section titles; see
        // `StructuredFormat.superconductorChangelog`.
        ChangelogRecipe(
            bundleID: "com.zarifpour.superconductor",
            source: URL(string: "https://releases.superconductor.so/changelog.json")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .superconductorChangelog),
        ],
        channelProofs: [
        // super.engineering: the dmg lives under `/nightly/` and is named
        // `Superconductor-nightly-<sha8>-arm64.dmg` — the vendor's own track name,
        // twice, in the URL `latest.json`'s `"nightly"` entry gives (2026-09-10).
        ChannelProofKey("com.zarifpour.superconductor", .nightly):
            .artifact(#"/nightly/Superconductor-nightly-[0-9a-f]{8}-arm64\.dmg$"#),
        ])
}
