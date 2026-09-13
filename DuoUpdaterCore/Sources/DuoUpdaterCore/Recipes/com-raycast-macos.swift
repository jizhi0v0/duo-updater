import Foundation

enum com_raycast_macos {
    static let set = AppRecipeSet(
        family: "com-raycast-macos",
        probes: [
        // Raycast keeps TWO trains open, and which one a Mac belongs to is decided
        // by the machine, not by a user preference — so both are stable-channel
        // recipes separated by `hostRequirement`, not by `channel`.
        //
        //   v1 (this recipe): `releases.raycast.com`, universal, still shipping
        //      (1.104.25 on 2026-08-18). This is the train for every Mac that
        //      cannot run v2.
        //   v2 (below): `x.raycast-releases.com`, arm64-only, macOS 26+.
        //
        // Neither endpoint gates: both answer any client the same way regardless
        // of the UA's OS/architecture (measured 2026-08-27 across Intel/Sequoia/
        // browser agents), which is precisely why the split is recorded in the
        // recipes. `best(of:)` then takes the higher version among whichever
        // recipes this Mac is eligible for — v2 on Apple silicon + Tahoe, v1
        // everywhere else.

        // Raycast v1 — official "latest release" endpoint; `version` is first.
        // Carries an explicit `variant` for the same reason v2 does: a duplicated
        // (bundleID, channel) group must declare every member deliberately. Its
        // verify baseline entry was renamed with it (`…:stable` → `…:stable:v1`)
        // rather than left to start over.
        // One-click: the same JSON's `downloadURL` is the dmg (a
        // worker.raycast-releases.com proxy URL wrapping a presigned R2 object;
        // resolved fresh from each probe so its signed expiry is never stale).
        VendorProbeRecipe(
            bundleID: "com.raycast.macos",
            url: URL(string: "https://releases.raycast.com/releases/latest?build=universal")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.raycast.com/"),
            // /changelog now serves the V2 notes; the v1 archive moved to
            // /changelog/macos ("Raycast - macOS V1 Changelog"). This is the page
            // a v1 user's notes actually live on, so it is the one linked here.
            changelogURL: URL(string: "https://www.raycast.com/changelog/macos"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""downloadURL"\s*:\s*"(https://[^"]+)""#),
                kind: .dmg),
            variant: "v1"),

        // Raycast v2 — the endpoint the v2 app's own updater calls. Requirements
        // are macOS Tahoe + Apple silicon (https://www.raycast.com/new), and the
        // macOS half of `builds` carries exactly one entry, `macos/arm64`; hence
        // the `hostRequirement`. On a Mac that fails it this recipe is dropped
        // before the merge and the v1 recipe above answers instead.
        //
        // `version` is DELIBERATELY absent from the query. The endpoint is a
        // "should I update?" call, not a "what is latest?" one: given the caller's
        // version it answers **204 No Content** when that version is already
        // current (which is what a packet capture of the running app shows, and
        // what would make this probe fail exactly when it should say "up to
        // date"). Omitting the parameter returns 200 + the newest release
        // unconditionally. Passing a v1-shaped 3-segment version is not an option
        // either — the parameter validates as 4 segments and 400s below that.
        //
        // Shape: {"id":…,"version":"2.0.6.0","title":…,"changelog":…,
        //   "commit_sha":…,"created_at":"2026-08-25T07:34:17.976Z","updated_at":…,
        //   "builds":[{…,"url":…}],"download_url":"https://x-r2.…arm64.dmg",
        //   "checksum":"<md5>"}
        // `version` is the marketing string the installed bundle reports verbatim
        // (2.0.6.0 == CFBundleShortVersionString, verified on this machine), so no
        // `versionIsBuild`. The install URL is the top-level `download_url` — a
        // plain, unsigned R2 object, unlike v1's presigned link — and the `.dmg`
        // suffix in the pattern keeps it off the Windows `.msix` builds listed in
        // `builds`. `checksum` is an MD5 hex digest, which `checksumPattern`
        // (SHA-512, base64) cannot consume, so it is left unused; Team SY64MV22J9
        // gates the swap.
        VendorProbeRecipe(
            bundleID: "com.raycast.macos",
            url: URL(string: "https://x.raycast-releases.com/releases/latest?platform=macos&architecture=arm64")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.raycast.com/"),
            changelogURL: URL(string: "https://www.raycast.com/changelog"),
            publishedAtPattern: #""created_at"\s*:\s*"([0-9T:.\-]+Z?)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""download_url"\s*:\s*"(https://[^"]+\.dmg)""#),
                kind: .dmg),
            variant: "v2",
            hostRequirement: VendorHostRequirement(
                minimumSystemVersion: "26.0", architectures: [.arm64])),
        ],
        changelogs: [
        // Raycast v2 — www.raycast.com/changelog, server-rendered (the full notes
        // are in the initial HTML; no hydration step to chase). Since v2 shipped
        // this URL is the **v2** macOS changelog and the v1 archive moved to
        // /changelog/macos — the opposite of what the paths suggest, and the reason
        // this recipe points at the bare /changelog.
        //
        // Both trains keep the one bundle id and the one `.stable` channel, so the
        // pair is separated by a version window instead — and this recipe is the
        // one WITHOUT a window, deliberately. This page carries the whole v2 train:
        // 2.0 at GA and the 0.63–0.71 builds that were the v2 beta before it. Those
        // numbers sit BELOW v1's 1.95–1.104, so v2's range is not one side of a
        // line and cannot be written as `2+` — doing so sent a 0.71 install to the
        // v1 archive, the single page that does not carry its notes. Instead the
        // archive claims exactly `[1, 2)` and everything else falls here.
        //
        // One entry per `<article>`:
        //   <span id="2.0"></span>
        //   <div class="…changelogMeta"><a …>v<!-- -->2.0</a>
        //       <span class="…changelogDate">August 25, 2026</span></div>
        //   <div class="markdown …changelogBody"> <p><img …></p> <p>intro…</p>
        //       <h2>✨ New</h2><ul><li>…</li></ul> <h2>💎 Improvements</h2>… </div>
        //
        // The `id` span is the version anchor rather than the visible pill text,
        // whose "v<!-- -->2.0" carries a comment node between the `v` and the
        // number. Class names are CSS-module-hashed
        // (`ChangelogEntry-module__p4g-ca__changelogBody`) so the patterns anchor
        // on the readable SUFFIX, which survives a rebuild; the hash does not.
        //
        // Versions here are the vendor's own MINOR labels — "2.0", "0.71" — while
        // the app reports a four-segment build (2.0.6.0). That is not a mismatch to
        // fix: Raycast publishes one set of notes per minor train and ships several
        // builds under it (the JSON API confirms this from the other side — its
        // /releases list hands 2.0.6.0, 2.0.5.0, 2.0.4.0 and 2.0.3.0 byte-identical
        // changelog text). The 0.6x–0.71 entries are the v2 BETA train, which is
        // what preceded the 2.0 GA number.
        //
        // The single itemPattern deliberately matches `h2` and `li` together rather
        // than listing them as fallbacks: itemPatterns are tried in order and the
        // FIRST to yield anything wins, so a bullets-only pattern would silently
        // drop the New/Improvements/Fixes headings that give 30 flat bullets their
        // shape. Folding the section titles in as items is the same thing
        // `decodeAlcoveChangelog` does with its Features/Fixes labels.
        //
        // NOT sourced from the JSON API next door (x.raycast-releases.com/releases)
        // even though it serves clean markdown: that list endpoint ignores its own
        // `platform` parameter (macos and windows return byte-identical bodies,
        // measured 2026-08-27) and answers with the Windows-flavoured copy of a
        // release note whose macOS twin differs. `…/releases/latest?platform=macos`
        // IS platform-correct, but it is one release deep — no history to show.
        ChangelogRecipe(
            bundleID: "com.raycast.macos",
            source: URL(string: "https://www.raycast.com/changelog")!,
            entryPattern:
                #"<span id="(?<version>[0-9][0-9.]*)"></span>.*?"#
                + #"changelogDate">(?<date>[^<]+)</span>.*?"#
                + #"changelogBody">(?<body>.*?)</article>"#,
            itemPatterns: [#"<(?:h2|li)\b[^>]*>(?<item>.*?)</(?:h2|li)>"#],
            maxEntries: 20,
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#),

        // Raycast v1 archive — /changelog/macos, the page titled "Raycast - macOS
        // V1 Changelog". Byte-for-byte the same component as the v2 page above, so
        // the patterns are the same three strings; only `source` and the version
        // window differ. Verified against the live page 2026-08-27: 10 entries,
        // 1.104.0 back to 1.95.0, all parsing.
        //
        // The window is `[1, 2)`, and the LOWER bound is the load-bearing half: a
        // bare `belowAppVersion: "2"` would also swallow the 0.63–0.71 v2 beta
        // builds, whose notes are on the v2 page above, not here.
        //
        // Its newest entry is 1.104.0 (December 16, 2025) while the v1 endpoint is
        // serving 1.104.25 — not a stale page. Raycast publishes one set of notes
        // per MINOR and ships patches under it, and v1 has been on patches alone
        // since v2 development took over; 1.104.x installs belong under the 1.104.0
        // entry. (The same grouping is visible on the v2 side, where 2.0.6.0
        // through 2.0.3.0 share one note.)
        ChangelogRecipe(
            bundleID: "com.raycast.macos",
            source: URL(string: "https://www.raycast.com/changelog/macos")!,
            entryPattern:
                #"<span id="(?<version>[0-9][0-9.]*)"></span>.*?"#
                + #"changelogDate">(?<date>[^<]+)</span>.*?"#
                + #"changelogBody">(?<body>.*?)</article>"#,
            itemPatterns: [#"<(?:h2|li)\b[^>]*>(?<item>.*?)</(?:h2|li)>"#],
            maxEntries: 20,
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#,
            minimumAppVersion: "1", belowAppVersion: "2"),
        ])
}
