import Foundation

enum com_windscribe_client {
    static let set = AppRecipeSet(
        family: "com-windscribe-client",
        probes: [
        // MARK: - 2026-09-07 Windscribe

        // Windscribe — VPN client (Qt, vendor's own updater; no Sparkle, no
        // electron-builder). `feed-discover` has nothing to find: the real bundle
        // (extracted from the 2.24.12 dmg, see below) declares no `SUFeedURL` and
        // ships no `app-update.yml`, and the cask (`windscribe`) is
        // `auto_updates true`, so `HomebrewCaskSource` defers. Without this recipe
        // the row is `.unknown`.
        //
        // THE ENDPOINT IS THE ONE THE VENDOR'S OWN WEBSITE CALLS. `windscribe.com`
        // is a Next.js app whose download and changelog pages are client-rendered
        // — the HTML carries no version at all — and both call
        // `api.windscribe.com` with a literal `Authorization: Bearer 1234` baked
        // into the public JS bundle. That header is a PRESENCE check, not a
        // credential: measured 2026-09-07, omitting it returns 403 "Missing client
        // authentication values" while `Bearer 9999` returns the same 200 body as
        // `Bearer 1234`. We send the vendor's own value because it is the one
        // combination proven to be exercised in production every day.
        //
        // WHY `/ChangeLogs/summary` AND NOT `/CheckUpdate`, which is the smaller
        // and more obvious endpoint. `CheckUpdate?platform=osx&beta=<n>` takes a
        // track number (0 release / 1 beta / 2 guinea pig, the same numbering as
        // the client's own `UPDATE_CHANNEL` enum) and answers with one artifact
        // URL to read the version off. The problem is that on 2026-09-07 `beta=0`,
        // `1`, `2` and `3` all returned BYTE-IDENTICAL bodies, so "the parameter
        // selects the release track" and "the parameter is ignored" could not be
        // told apart — the beta track (2.24.10) happened to sit behind stable
        // (2.24.12), which makes every value's correct answer the same.
        //
        // That ambiguity is not academic, and its risky branch is the NORMAL state
        // of this vendor. Counting the release dates in `/ChangeLogs?platform=osx`
        // (149 macOS entries): over the last 819 days the newest PRERELEASE
        // outranked the newest release on 618 of them — 75%, in 14 windows of
        // 27–75 days. If the parameter is ignored, then throughout every one of
        // those windows `CheckUpdate` names a `…_beta_universal.dmg` and a recipe
        // reading that filename would report `versionPatternNoMatch` — the app
        // `.unknown` and `duo verify` BROKEN, for weeks at a time, four times a
        // day. (Measured, by making the pattern unsatisfiable against the real
        // body: `✗ BROKEN … versionPatternNoMatch — no match in 395-byte body`.)
        //
        // `/ChangeLogs/summary` sidesteps the question instead of betting on it.
        // It states all three tracks as SEPARATELY NAMED fields, so the release
        // track is selected by a key rather than by a request parameter whose
        // semantics we cannot observe:
        //
        //   "platform": "osx",
        //   "release_version": "2.24", "release_build": 12,
        //   "release_date": "2026-09-02",
        //   "release_full_version": "2.24.12",
        //   "beta_full_version": "2.24.10",
        //   "guinea_pig_full_version": "2.24.6"
        //
        // THE EXACT KEY NAME IS THE CHANNEL GATE — but be precise about what it
        // is buying, because it is not what does the work today. The two
        // prerelease versions sit in the adjacent lines of the same object, and
        // the lazy run stops at the first `…_full_version` it reaches, which is
        // the release one: a pattern relaxed to `[a-z_]*full_version` reads the
        // same 2.24.12 and looks perfectly healthy. What the whole key buys is
        // that the answer stops depending on the vendor's field order, which is
        // the one way this could turn into a prerelease being served to every
        // stable install. `theAdjacentPrereleaseFieldsAreNotWhatIsRead` reorders
        // the real excerpt so the two patterns actually disagree, since a
        // mutation nothing can distinguish is not a test.
        //
        // `"release_version"` is a different trap in the same object: it holds
        // only `"2.24"`, two of the three segments, with the third in
        // `release_build`. Compared against the installed `2.24.12` that reads as
        // a permanent DOWNGRADE and hides every future update. So `_full_` is
        // load-bearing for a second, unrelated reason.
        //
        // THE `(?:(?!"platform")…)` BOUNDARY IS ALSO LOAD-BEARING. The document
        // carries 28 platforms (desktop, extension, mobile, tv), each an object of
        // the same shape, and macOS is in the middle of it. A plain lazy `[\s\S]*?`
        // from `"platform": "osx"` would, the day the osx entry stops carrying
        // `release_full_version`, run on into the NEXT platform's copy of the key
        // and report Windows' version as the Mac's. Measured on the real body with
        // that field deleted from the osx entry: the bounded pattern matches
        // nothing (correct), the unbounded one returns `2.24.12` — which is the
        // right answer today ONLY because Windows and macOS ship in lockstep, so
        // the bug would look like a pass. `publishedAtPattern` carries the same
        // anchor for the same reason.
        //
        // Costs 14 KB per scan against `CheckUpdate`'s 395 B. Bought with it: the
        // release date, which `CheckUpdate` does not state at all, so the Release
        // Log places this app exactly instead of on an estimated "≈" window.
        //
        // NO ONE-CLICK, and this is a structural refusal rather than a TODO. This
        // endpoint names no artifact, but `CheckUpdate` does and it resolves to
        // `Windscribe_<version>_universal.dmg` — a dmg holding
        // `WindscribeInstaller.app` (`com.windscribe.installer.macos`) and nothing
        // else; the app itself lives inside it as
        // `Contents/Resources/windscribe.tar.lzma`, which `ArchiveExtractor`
        // cannot open (it dispatches on extension — `lzma` is not among
        // dmg/zip/gz/bz2/xz/tar/tbz/tgz) and which unpacks to a bare `Contents/`
        // with no `.app` wrapper for `firstApp` to find. Both are fixable; the
        // third thing is not. An install is not a bundle swap here: it also writes
        // `/Library/LaunchDaemons/com.windscribe.helper.macos.plist`, a privileged
        // helper, a system extension, a login item and `/usr/local/bin/
        // windscribe-cli`. Swapping only the bundle would leave a VPN talking to a
        // stale root helper — and the vendor's own changelog records four local
        // privilege-escalation fixes on the install/update path in 2026-08 alone:
        // two named "staged updater bundle" verbatim (2.24.12 #1987, 2.24.10
        // #1964) and two in the installer archive / bootstrapper extraction flow
        // (2.24.8 #1949, #1816). Detection only.
        //
        // CROSS-CHANNEL, both directions, because only one of them is prevented.
        // A stable install can never be walked onto a prerelease: the release
        // track is selected by key. The reverse is NOT prevented and is what
        // actually happens — the three tracks share `com.windscribe.client`, a
        // display name and an unsuffixed version string (proven by extracting both
        // the 2.24.12 stable and the 2.24.10 beta bundles), so `detect()` has no
        // signal and calls every copy stable. `channel-verify` on the real beta
        // bundle reports `UPDATE 2.24.10 → 2.24.12` through the full production
        // chain. That is accepted rather than overlooked: the version moves
        // forward, Windscribe's own client on the Beta channel offers the same
        // build (its API answers "this track or better"), and the install is
        // manual — we hand the user the vendor's download page. It cannot be
        // gated, either, since the gate would need the channel we cannot read.
        //
        // Verified 2026-09-07 against the real bundle, extracted from
        // `Windscribe_2.24.12_universal.dmg` without installing: `com.windscribe.
        // client`, `CFBundleShortVersionString` == `CFBundleVersion` == `2.24.12`
        // (the plist template writes one value into both, so no `versionIsBuild`),
        // universal (x86_64 + arm64), "Developer ID Application: Windscribe
        // Limited (GYZJYS7XUG)".
        //
        // EXPECTED WARNING, so nobody files an issue against a working recipe.
        // `duo verify` runs `RecipeSanity.remoteBehindInstalled` whenever it finds
        // an installed copy, and Windscribe's build numbers climb ACROSS tracks
        // inside a cycle (2.24.3/2.24.6 guinea pig → 2.24.8/2.24.10 beta →
        // 2.24.12 release). A machine carrying a prerelease build is therefore
        // routinely newer than the newest release-track build — measured, that
        // state holds on 618 of the last 819 days — and this recipe, which reads
        // the release track by design, then reads behind the installed copy and
        // draws a warning, four times a day for weeks. That is one of the honest
        // causes that check's own doc lists, not a fault here; it goes away once
        // the channel recipes land and such a copy is compared against its own
        // track.
        //
        // The vendor states an OS floor per release (`min_version`, 13.0 today)
        // and it MOVES — across the 149 macOS entries in `/ChangeLogs?platform=osx`
        // it runs 10.8 → 13.0 — so it is deliberately not frozen into a
        // `hostRequirement`. Nothing is lost today: DuoUpdater's own deployment
        // target is macOS 14.0, so every host that can run this check already
        // clears the app's floor.
        VendorProbeRecipe(
            bundleID: "com.windscribe.client",
            url: URL(string: "https://api.windscribe.com/ChangeLogs/summary")!,
            mode: .responseBody,
            versionPattern: #""platform"\s*:\s*"osx""#
                + #"(?:(?!"platform")[\s\S])*?"#
                + #""release_full_version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://windscribe.com/download"),
            changelogURL: URL(string: "https://windscribe.com/changelog"),
            publishedAtPattern: #""platform"\s*:\s*"osx""#
                + #"(?:(?!"platform")[\s\S])*?"#
                + #""release_date"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2})""#,
            requestHeaders: ["Authorization": "Bearer 1234"]),
        ] + [ReleaseChannel.beta, .guineaPig].compactMap(windscribeTrackRecipe),
        changelogs: [
        // Windscribe — the version comes from the vendor's own API (see
        // `VendorProbeRegistry`), but the notes come from GitHub, and that split
        // is the point rather than an accident.
        //
        // The vendor DOES publish structured notes:
        // `api.windscribe.com/ChangeLogs?platform=osx` carries 149 entries with a
        // markdown `changelog` field and a `beta` track number. It is unreachable
        // from here: that endpoint 403s without an `Authorization` header, and
        // `ChangelogRecipe` has no `requestHeaders` (`VendorProbeRecipe` does).
        // The GitHub releases carry the same prose — 11,480 characters on
        // v2.24.12 — need no header at all, and land in a format this registry
        // already decodes.
        //
        // `.gitHubReleases` keeps stable releases only, which is exactly the split
        // this vendor publishes: measured 2026-09-07 across every release since
        // 2024, all 19 of the versions the vendor's own API names on its release
        // track are `prerelease: false` on GitHub, and NONE of the 51 it names on
        // the beta / guinea-pig tracks are — so nothing from a track the user did
        // not opt into can reach the panel.
        //
        // Tag shape is `vX.Y.Z` against the probe's bare `X.Y.Z`; `GitHubMarkdownParser`
        // is the same one the GitHub *version* source uses and already handles the
        // prefix. One caveat worth knowing before trusting this list as history:
        // GitHub is missing 2.15.9 entirely (the vendor's API has it), so the
        // releases are the vendor's notes but not provably ALL of them.
        //
        // ⚠️ `channel: .stable` covers ONLY copies that detect as stable, and
        // channel detection for this app has since landed (`WindscribeChannel`),
        // so beta and guinea-pig copies are real. They are covered by the two
        // recipes declared just below, NOT by this one — and the reason this
        // warning had to become those recipes is that
        // `recipe(forBundleID:channel:)` does not return nil for an uncovered
        // channel: it walks exact match → channel-agnostic → `.stable` → any, so
        // without them a beta copy landed here, on a list `.gitHubReleases` has
        // filtered to `prerelease: false` only, while the row beside it offered a
        // prerelease build (2.24.10, say). The pane would show 2.24.12 / 2.23.11 /
        // 2.22.10 and omit the exact entry being offered — the failure
        // `includesPromotedStable` exists for; see CotEditor above.
        // Windscribe's tracks are a ladder (level N is served the newest build from
        // tracks 0…N), which is why those recipes set `includesPromotedStable`; the
        // precise fix remains the vendor's own `ChangeLogs?platform=osx` and its
        // per-entry `beta` number, not this feed.
        ChangelogRecipe(
            bundleID: "com.windscribe.client",
            source: URL(string: windscribeReleases)!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),
        ] + [ReleaseChannel.beta, .guineaPig].map { channel in
            ChangelogRecipe(
                bundleID: "com.windscribe.client",
                source: URL(string: windscribeReleases)!,
                mode: .json,
                maxEntries: 20,
                channel: channel,
                includesPromotedStable: true,
                structuredFormat: .gitHubReleases)
        })

    private static func windscribeTrackRecipe(_ channel: ReleaseChannel) -> VendorProbeRecipe? {
        // `(?![0-9])` rather than `\b` after the class: the values are 0/1/2
        // today and a bare `[01]` would also match the first digit of a
        // hypothetical `10`, which is the kind of thing a vendor adds without
        // announcing it.
        guard let tracks = VendorProbeRegistry.windscribeTrackSet(channel) else { return nil }
        return VendorProbeRecipe(
            bundleID: "com.windscribe.client",
            url: URL(string: "https://api.windscribe.com/ChangeLogs?platform=osx")!,
            mode: .responseBody,
            versionPattern: #""beta"\s*:\s*\#(tracks)(?![0-9])[\s\S]*?"#
                + #"Windscribe_([0-9]+(?:\.[0-9]+)+)_"#,
            downloadURL: URL(string: "https://windscribe.com/download"),
            changelogURL: URL(string: "https://windscribe.com/changelog"),
            selectHighest: true,
            publishedAtPattern: #""release_date"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2})""#,
            entryStartPattern: #""id"\s*:\s*[0-9]+"#,
            requestHeaders: ["Authorization": "Bearer 1234"],
            channel: channel)
    }

    /// Declared once because the three Windscribe recipes must never drift onto
    /// different pages of the same feed — `per_page` decides how far back every
    /// one of them can see.
    private static let windscribeReleases =
        "https://api.github.com/repos/Windscribe/Desktop-App/releases?per_page=40"
}
