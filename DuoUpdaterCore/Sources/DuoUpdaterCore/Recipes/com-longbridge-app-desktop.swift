import Foundation

enum com_longbridge_app_desktop {
    static let set = AppRecipeSet(
        family: "com-longbridge-app-desktop",
        probes: [
        // MARK: - 2026-08-25 Longbridge Desktop

        // History: docs/app-audits/com-longbridge-app-desktop.md#历史与实测
        // Longbridge Desktop — the vendor's compact stable JSON is the same
        // manifest used by its release-notes site. `version` matches the mounted
        // app's CFBundleShortVersionString exactly (e.g. 0.19.1); CFBundleVersion is
        // a timestamp-like build (e.g. 20260820.080114) and must not be compared.
        //
        // Use the manifest's top-level release. Its optional gray object has
        // separate versions and assets selected by Longbridge's own updater.
        // The matching arm64 DMG is self-contained, notarized, and signed by
        // Team 45NG8MW7WK. Filenames may include a build's git hash.
        // Use the selected asset's own SHA-256 when present.
        VendorProbeRecipe(
            bundleID: "com.longbridge.app.desktop",
            url: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/stable/latest.json")!,
            mode: .longbridgeManifest,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,4})""#,
            downloadURL: URL(string: "https://longbridge.com/desktop/")!,
            changelogURL: URL(string: "https://longbridge.com/desktop/release-notes/")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://assets\.lbkrs\.com/github/release/longbridge-desktop/stable/longbridge-v[0-9.]+(?:-g[0-9a-f]+)?-macos-aarch64\.dmg)""#),
                kind: .dmg,
                checksumPattern:
                    #"\A(?:(?!longbridge-v[0-9.]+(?:-g[0-9a-f]+)?-macos-aarch64\.dmg)[\s\S])*?\{(?=[^{}]*"url"\s*:\s*"https://assets\.lbkrs\.com/github/release/longbridge-desktop/stable/longbridge-v[0-9.]+(?:-g[0-9a-f]+)?-macos-aarch64\.dmg")[^{}]*?"sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex)),

        // Longbridge Desktop Preview — a SEPARATE bundle id
        // (`com.longbridge.app.desktop.preview`, "Longbridge Preview.app"), so
        // `ReleaseChannel.detect` resolves it via the `.preview` bundle-id suffix
        // and the two trains cannot be confused by bundle id alone.
        //
        // The channel's website presence has come and gone: `/desktop/preview/` has
        // been 404 when checked — no download landing page — and the preview
        // release-notes index has at times rendered an EMPTY version list while the per-version
        // notes pages, this manifest, and the artifacts stayed published (History
        // has both states). So a user who already runs Preview can be updated in
        // place even when the website offers no way to discover it. `changelogURL`
        // still names the preview index although that URL now redirects to the
        // Longbridge Pro product listing (see the preview changelog below).
        //
        // Preview requires a -preview.N version and its own CDN track.
        // Older preview assets omitted sha256. In that case the install still
        // uses the Team ID gate and the probe reports the missing checksum.
        //
        // The preview artifact is com.longbridge.app.desktop.preview, arm64,
        // Team 45NG8MW7WK — the SAME team as stable, which is what
        // `VendorInstaller`'s signature gate requires — notarized Developer ID.
        VendorProbeRecipe(
            bundleID: "com.longbridge.app.desktop.preview",
            url: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/latest.json")!,
            mode: .longbridgeManifest,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,4}-preview\.[0-9]+)""#,
            changelogURL: URL(string: "https://longbridge.com/desktop/release-notes/preview/")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://assets\.lbkrs\.com/github/release/longbridge-desktop/preview/longbridge-v[0-9.]+-preview\.[0-9]+(?:-g[0-9a-f]+)?-macos-aarch64\.dmg)""#),
                kind: .dmg,
                checksumPattern:
                    #"\A(?:(?!longbridge-v[0-9.]+-preview\.[0-9]+(?:-g[0-9a-f]+)?-macos-aarch64\.dmg)[\s\S])*?\{(?=[^{}]*"url"\s*:\s*"https://assets\.lbkrs\.com/github/release/longbridge-desktop/preview/longbridge-v[0-9.]+-preview\.[0-9]+(?:-g[0-9a-f]+)?-macos-aarch64\.dmg")[^{}]*?"sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex),
            channel: .preview),
        ],
        changelogs: [
        // History: docs/app-audits/com-longbridge-app-desktop.md#历史与实测
        // The English changelog RSS mixes Longbridge Pro and LongbridgeAI.
        // Read only numeric Pro releases whose item link identifies the same
        // version. Each description is a short summary; the release article
        // and its media are outside the feed.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop",
            source: URL(string: "https://longbridge.com/en/changelog/rss.xml")!,
            entryPattern:
                #"<item>\s*<title>Longbridge Pro (?<version>[0-9]+(?:\.[0-9]+){2})\s+·\s+(?<title>[^<]+)</title>\s*"#
                + #"<link>https://longbridge\.com/en/changelog/longbridge-pro/v[0-9]+\.[0-9]+#v\k<version></link>\s*"#
                + #"<guid\b[^>]*>[^<]*</guid>\s*"#
                + #"<description>(?<body>[^<]*)</description>\s*"#
                + #"<pubDate>[A-Za-z]{3},\s+(?<date>[0-9]{1,2} [A-Za-z]{3} [0-9]{4}) [^<]+</pubDate>\s*</item>"#,
            itemPatterns: [#"(?<item>.+)"#],
            channel: .stable),

        // Longbridge Desktop Preview — no HTML page to read any more. The vendor's
        // preview release-notes URLs (`/desktop/release-notes/preview/` and
        // `…/preview/v<version>`) now redirect to the Longbridge Pro product listing,
        // which carries no preview build; the preview manifest is the only place the
        // preview notes are still published. So this reads the manifest's
        // `release_notes.en` through `StructuredChangelogDecoder`. The decoder
        // returns the manifest's own version (the newest preview build), so it has
        // no per-version URL to resolve and no `sourceTemplate`.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop.preview",
            source: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/latest.json")!,
            mode: .json,
            channel: .preview,
            structuredFormat: .longbridgeDesktopManifest),
        ],
        channelProofs: [
        // Longbridge splits the two trains by CDN path — `/longbridge-desktop/
        // preview/` vs `/stable/` — and the artifact filename carries the
        // `-preview.N` suffix on top of that, so the URL names the channel twice.
        // Unusually for a copied-from-stable recipe, the two manifests cannot even
        // match each other's version pattern (stable's requires a closing quote
        // straight after the numeric version; preview's requires the suffix), so a
        // cross-train resolve fails closed rather than silently succeeding.
        ChannelProofKey("com.longbridge.app.desktop.preview", .preview):
            .artifact(#"/longbridge-desktop/preview/"#),
        ],
        changelogPages: [
        // Longbridge Desktop — the structured recipe follows the exact version
        // page. Keep the English release-notes index as a web fallback while an
        // update result or a freshly added recipe has not populated yet.
        "com.longbridge.app.desktop": URL(string: "https://longbridge.com/desktop/release-notes/")!,
        ])

    /// Scope resolution to the top-level release and its first eligible ARM
    /// asset. Project that one object so URL and digest extraction share it.
    static func releaseBody(from body: String, channel: ReleaseChannel) -> String? {
        guard let manifest = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let version = manifest["version"] as? String else { return nil }

        let assetPrefix = "https://assets.lbkrs.com/github/release/longbridge-desktop/"
            + "\(channel.rawValue)/longbridge-v\(version)"
        let suffixPattern = #"\A(?:-g[0-9a-f]+)?-macos-aarch64\.dmg\z"#
        let asset = (manifest["assets"] as? [Any] ?? []).lazy.compactMap { entry -> [String: String]? in
            guard let fields = entry as? [String: Any], let url = fields["url"] as? String,
                  url.hasPrefix(assetPrefix),
                  url.dropFirst(assetPrefix.count).range(of: suffixPattern, options: .regularExpression) != nil
            else { return nil }
            var selected = ["url": url]
            selected["sha256"] = (fields["sha256"] as? String)?.lowercased()
            return selected
        }.first
        var release: [String: Any] = ["version": version, "assets": asset.map { [$0] } ?? []]
        release["published_at"] = manifest["published_at"] as? String
        guard let data = try? JSONSerialization.data(
            withJSONObject: release, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
