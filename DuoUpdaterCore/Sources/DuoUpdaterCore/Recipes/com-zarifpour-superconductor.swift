import Foundation

enum com_zarifpour_superconductor {
    static let set = AppRecipeSet(
        family: "com-zarifpour-superconductor",
        probes: [
        // History: docs/app-audits/com-zarifpour-superconductor.md#历史与实测
        // super.engineering (Superconductor) — `latest.json` is the manifest the
        // app's own updater reads (the URL, the `superconductor-updater` UA and
        // "nightly entry missing valid sha" all sit in its binary). Shape
        // (checked 2026-09-23):
        //   {"nightly": {"sha": "<40 hex>", "url": "<dmg>", "sha256": "<hex>",
        //     "date": "2026-09-23", "bundles": {"<bundle id>": {"url":
        //     "https://releases.superconductor.so/nightly/super.engineering-nightly-
        //     <sha8>-arm64[-legacy-id].dmg", "sha256": "<hex>"}, …}}}
        // (The file prefix was `Superconductor-nightly-` through 5dab43b4; b4ff1a8d,
        // 2026-09-23, is the first build published only as `super.engineering-`.)
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
        // One-click: the dmg this bundle id's `bundles` entry names, Developer ID
        // Team MR38E36N26, notarized (mounted and checked, 2026-09-23). `sha256` is a hex SHA-256,
        // which `checksumPattern` (base64 SHA-512) cannot consume, so the Team gate
        // stands in. arm64-only (the filename says so and `lipo` agrees);
        // `LSMinimumSystemVersion` 14.0.
        //
        // Reads the newest build on the only track — the dmg the site's own
        // Download button (`super.engineering/api/download`, a 302 to the same URL
        // when checked, 2026-09-10 and 2026-09-14) and the app's updater hand every
        // user.
        VendorProbeRecipe(
            bundleID: "com.zarifpour.superconductor",
            url: URL(string: "https://releases.superconductor.so/latest.json")!,
            mode: .responseBody,
            versionPattern:
                #""nightly"\s*:\s*\{[^{}]*?"sha"\s*:\s*"([0-9a-f]{8})[0-9a-f]{32}""#,
            downloadURL: URL(string: "https://super.engineering/"),
            publishedAtPattern:
                #""nightly"\s*:\s*\{[^{}]*?"date"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2})""#,
            // The installer is the entry's `bundles` member for THIS bundle id. The
            // manifest lists one build per bundle id there: the vendor now ships
            // `engineering.super.app` too, and its dmg would change the installed
            // app's identity. The top-level `url` is not read — which id it names is
            // the vendor's choice, not something the manifest states. `(?:[^{}]|\{[^{}]*\})*?`
            // steps over whole one-level objects, so the match cannot leave the
            // `"nightly"` object and does not depend on key order. No entry for this
            // id resolves no installer.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""nightly"\s*:\s*\{(?:[^{}]|\{[^{}]*\})*?"bundles"\s*:\s*\{(?:[^{}]|\{[^{}]*\})*?"com\.zarifpour\.superconductor"\s*:\s*\{[^{}]*?"url"\s*:\s*"(https://releases\.superconductor\.so/[^"]+-arm64[^"/]*\.dmg)""#),
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
        // `super.engineering-nightly-<sha8>-arm64<suffix>.dmg` — the vendor's own
        // track name, twice, in the URL `latest.json`'s `"nightly"` entry gives. The
        // suffix names the bundle id, not the track (`-legacy-id` for this one).
        // Builds through 5dab43b4 were `Superconductor-nightly-…` and are still
        // served under that name; both prefixes carry the same `-nightly-` marker.
        ChannelProofKey("com.zarifpour.superconductor", .nightly):
            .artifact(#"/nightly/(?:super\.engineering|Superconductor)-nightly-[0-9a-f]{8}-arm64[^/]*\.dmg$"#),
        ])
}
