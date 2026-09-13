import Foundation

enum bot_cline_app {
    static let set = AppRecipeSet(
        family: "bot-cline-app",
        probes: [
        // MARK: - 2026-09-12 Cline Desktop

        // Cline — Tauri (`tauri-plugin-updater 2.10.1`), not Electron and not
        // Sparkle, so nothing generic reaches it: `feed-discover` on the real
        // 0.0.26 bundle prints `noKnownUpdater` (no `SUFeedURL`, no
        // `app-update.yml`), and there is no Homebrew cask at all
        // (`brew search --cask cline` → clion / font-karla-tamil-inclined /
        // sonic-lineup). Without these two recipes both rows are `.unknown`,
        // which is what `channel-verify` showed before they existed.
        //
        // THE ENDPOINT IS THE ONE THE APP ITSELF READS, and that is not inferred
        // from the URL shape — each channel's own executable names it. `strings`
        // on `Contents/MacOS/cline-app` (the real binary; `Contents/MacOS/Cline`
        // does not exist — the bundle ships `cline-app` plus a 181 MB
        // `code-sidecar`) yields exactly one `releases/download/…` address per
        // build:
        //
        //     stable → …/download/desktop-latest/latest.json
        //     beta   → …/download/desktop-beta/latest.json
        //
        // So a probe here resolves the same build Cline's own updater would
        // install, for everyone on that track. Tauri's manifest is static — no
        // device id, no rollout bucket — so "newest on the track" and "the build
        // allocated to this machine" are the same object, and the vendor's own
        // download button (cline.bot/desktop, measured 2026-09-12, links
        // `…/desktop-v0.0.26/Cline_0.0.26_universal.dmg`) hands over that same
        // release by hand.
        //
        // WHY NOT `GitHubReleaseRule`, which this otherwise looks like a case for.
        // `cline/cline` is a MONOREPO publishing four trains from one Releases
        // list — measured 2026-09-12 over its newest 100 releases: 33 `desktop-*`,
        // 24 `v*` (the VS Code extension), 22 `sdk/sdk/v*`, 21 `cli-v*` — and the
        // non-desktop three are all non-prerelease. `/releases/latest` therefore
        // answers with whichever product shipped last; it returns
        // `desktop-v0.0.26` today only because desktop shipped 2026-09-11 and the
        // other three last shipped 2026-09-02. The list endpoint avoids that but
        // costs 52,732 gzipped bytes at `per_page=40` and, per
        // `GitHubConditionalCache`, carries NO `Last-Modified` and an `ETag` that
        // rotates with `assets[].download_count`. These two manifests are 7,847
        // and 2,525 bytes and DO serve `Last-Modified` (measured the same day).
        // What is given up is the release-history backfill only GitHub and
        // Sparkle sources produce; `publishedAtPattern` below still dates the
        // release each round.
        //
        // TWO CHANNELS, TWO BUNDLE IDS — pattern A, so nothing has to be inferred
        // from a preference or a version suffix. Mounted both real disk images
        // (2026-09-12): stable is `bot.cline.app` / `0.0.26`, beta is
        // `bot.cline.app.beta` / `0.0.23-beta.1`, both short and build version
        // fields identical per copy (hence no `versionIsBuild`), both
        // `LSMinimumSystemVersion` 10.13, both universal (x86_64 + arm64), both
        // `spctl` accepted as Notarized Developer ID under Team 6F2AYU54ZH.
        // `detect()` has two independent signals and needs neither recipe's help:
        // the `.beta` bundle-id suffix and the `-beta.1` full-semver version.
        //
        // A BETA COPY IS NEVER WALKED ONTO STABLE, unlike CotEditor's cyclical
        // train where taking the graduation is the point. The two ids are
        // different apps on disk, so a stable artifact is not this row's app at
        // all — hence the beta `versionPattern` REQUIRES `-beta.<N>` rather than
        // also accepting a plain tag, and `ChannelProofRegistry` pins the
        // `Cline-Beta_` artifact name.
        //
        // THE CLOSING QUOTE IN `versionPattern` IS LOAD-BEARING. `"version"` is
        // the manifest's first key and its value is bare semver on stable; without
        // the trailing `"` the stable pattern would match the `0.0.23` PREFIX of a
        // `0.0.23-beta.1` value and silently report a version that was never
        // published to this track. Verified on the real beta body: the stable
        // pattern matches nothing there (and the beta pattern matches nothing in
        // the stable body).
        //
        // ONE-CLICK installs the `.app.tar.gz` — the artifact Tauri's own updater
        // consumes, not the dmg, because the manifest names only the tarball and
        // rebuilding a dmg URL from the version would be a guess this vendor has
        // already invalidated once (assets were `Cline-Code_*` through 0.0.14 and
        // `Cline_*` from 0.0.15). Both tarballs were downloaded and unpacked
        // 2026-09-12: each holds exactly one `.app` at the archive root, notarized,
        // Team 6F2AYU54ZH. `platforms` also carries a `windows-x86_64` entry whose
        // `url` is a `.exe`, so both install patterns anchor `_universal.app.tar.gz`
        // — the two darwin keys name the SAME universal tarball, which is why
        // first-match is correct here rather than an ordering bet.
        VendorProbeRecipe(
            bundleID: "bot.cline.app",
            url: URL(string:
                "https://github.com/cline/cline/releases/download/desktop-latest/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://cline.bot/desktop"),
            changelogURL: URL(string: "https://github.com/cline/cline/releases"),
            publishedAtPattern:
                #""pub_date"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[^"]*)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""(https://github\.com/cline/cline/releases/download/desktop-v[0-9][^"]*/Cline_[0-9][^"]*_universal\.app\.tar\.gz)""#),
                kind: .tarGz)),

        VendorProbeRecipe(
            bundleID: "bot.cline.app.beta",
            url: URL(string:
                "https://github.com/cline/cline/releases/download/desktop-beta/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3}-beta\.[0-9]+)""#,
            // NOT cline.bot/desktop, which the stable recipe uses: that page
            // publishes only the stable dmg and the Windows exe (measured
            // 2026-09-12 — a scan for any beta artifact URL returns nothing),
            // while it mentions the word "beta" in prose. Sending a beta user
            // there for a manual download hands them a DIFFERENT bundle id that
            // installs alongside their copy instead of updating it. The beta
            // artifacts exist only on the releases the install spec below reads.
            downloadURL: URL(string: "https://github.com/cline/cline/releases"),
            changelogURL: URL(string: "https://github.com/cline/cline/releases"),
            publishedAtPattern:
                #""pub_date"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[^"]*)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""(https://github\.com/cline/cline/releases/download/desktop-v[0-9][^"]*/Cline-Beta_[0-9][^"]*-beta\.[0-9]+_universal\.app\.tar\.gz)""#),
                kind: .tarGz),
            channel: .beta),
        ],
        changelogs: [
        // Cline — the release bodies are the changelog (plain `- ` bullet lists, no
        // `##` headings, which `GitHubMarkdownParser`'s bullet pass handles before
        // it ever reaches the prose fallback). Version detection does NOT come from
        // here: it reads Cline's own Tauri manifest, for the reasons in
        // `VendorProbeRegistry`. This endpoint is fetched only when the workbench
        // opens a Cline row — `ChangelogService` is on-demand and never runs during
        // a check round — so the monorepo's page size is not on the scan path.
        //
        // `tagPattern` IS THE WHOLE POINT HERE, and both halves of it earn their
        // keep. `cline/cline` publishes four products from one Releases list, so
        // measured on the real `per_page=40` page (2026-09-12): the stable rail
        // keeps 13 entries and WITHOUT the pattern would additionally have rendered
        // **20 foreign ones** — `v4.1.17` (the VS Code extension), `cli-v3.0.61`,
        // `sdk/sdk/v0.0.82` and so on. More noise than signal, and none of it
        // malformed enough to look wrong. The capture group is the second half:
        // `stripLeadingV` only removes a leading `v`, so every entry would have been
        // titled `desktop-v0.0.26` and none would have matched the version the row
        // shows.
        //
        // The rolling feed tags the updater points at (`desktop-latest`,
        // `desktop-beta`) are releases in this list too; the `$`-anchored pattern
        // drops both, which is what keeps a permanently-present tag from rendering
        // as an entry whose version never changes.
        //
        // `per_page=40` / `maxEntries: 20` is the registry's house shape (Yaak,
        // CotEditor, Zed). Both rails fit inside it today: 13 stable and 6 beta.
        //
        // `includesPromotedStable` is absent (false) on the beta recipe, taking
        // Yaak's side of that split rather than CotEditor's, and here the reason is
        // stronger than either: Cline's tracks are two DIFFERENT BUNDLE IDS
        // (`bot.cline.app` vs `bot.cline.app.beta`). A stable release is not a
        // build this row can ever be offered — it is a different app on disk — so
        // a promoted-stable entry would describe something the beta rail cannot
        // install.
        ChangelogRecipe(
            bundleID: "bot.cline.app",
            source: URL(string: "https://api.github.com/repos/cline/cline/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^desktop-v([0-9]+(?:\.[0-9]+){1,3})$"#),

        ChangelogRecipe(
            bundleID: "bot.cline.app.beta",
            source: URL(string: "https://api.github.com/repos/cline/cline/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            structuredFormat: .gitHubReleases,
            tagPattern: #"^desktop-v([0-9]+(?:\.[0-9]+){1,3}-beta\.[0-9]+)$"#),
        ],
        channelProofs: [
        // Cline Beta ships its own product name into the artifact — `Cline-Beta_…`
        // where stable is `Cline_…` — so the URL alone carries the channel and the
        // ordinary `.artifact` form applies; no `.endpointKeyed` reasoning needed
        // even though the two tracks DO also read separate endpoints. Both halves
        // are anchored because each fails differently: `Cline-Beta_` is the product
        // (a stable tarball can never match it) and `-beta\.[0-9]+` is the tag's
        // own prerelease counter. Verified against the live manifest 2026-09-12 —
        // the resolved URL was
        // `…/desktop-v0.0.23-beta.1/Cline-Beta_0.0.23-beta.1_universal.app.tar.gz`,
        // and the stable manifest's URL matches neither half.
        ChannelProofKey("bot.cline.app.beta", .beta):
            .artifact(#"/Cline-Beta_[0-9][^/]*-beta\.[0-9]+_universal\.app\.tar\.gz$"#),
        ])
}
