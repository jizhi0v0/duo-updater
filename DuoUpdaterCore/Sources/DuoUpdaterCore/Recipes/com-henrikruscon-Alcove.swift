import Foundation

enum com_henrikruscon_Alcove {
    static let set = AppRecipeSet(
        family: "com-henrikruscon-Alcove",
        probes: [
        // Alcove — the PUBLIC, no-credential fallback. The authoritative source is
        // `AlcoveUpdateSource` (the licensed api.tryalcove.com channel the app's own
        // "Reworked update manager" uses), wired ahead of this probe so it answers
        // first whenever the user's license credentials are seeded; this recipe is
        // what everyone else gets.
        //
        // The old endpoint (update.tryalcove.com) is GONE — verified 2026-07-29 it no
        // longer resolves at all (NXDOMAIN), so the previous recipe silently produced
        // no version and left uncredentialed users with ZERO Alcove detection (the
        // henrikruscon/alcove-releases GitHub mirror had already been retired for
        // lagging; see GitHubReleasesSource). Its replacement is the download host's
        // own metadata endpoint, `download.tryalcove.com/latest` — a small
        // unauthenticated JSON doc:
        //   {"version":"1.7.9","build":203,"published_at":"…","assets":[…],
        //    "minimum_system_version":"15 Sequoia"}
        // `version` is the marketing string (== CFBundleShortVersionString — no build
        // trap; `build` is carried separately and we ignore it). Verified 2026-07-29
        // it reported exactly 1.7.9 (203), matching the installed licensed build
        // build-for-build — so unlike every mirror before it, this one is IN SYNC with
        // the licensed channel rather than trailing it. Single-channel: `?channel=beta`
        // 404s ("No releases available") and an `X-Channel` header changes nothing.
        //
        // The pattern requires `{` or `,` before the key so it can never drift onto
        // the sibling `minimum_system_version` (whose value, "15 Sequoia", isn't
        // version-shaped anyway) if the vendor reorders fields.
        //
        // DETECTION-ONLY, deliberately — do NOT re-attach an install spec. The public
        // binaries at download.tryalcove.com/{Alcove.dmg,Alcove.zip} are the *trial*
        // build and lag this metadata badly: on 2026-07-29 the dmg was 1.7.7 (199)
        // (`x-alcove-version: 1.7.7`, confirmed by mounting it and reading the
        // bundle's Info.plist) while /latest already said 1.7.9. Installing it while
        // claiming 1.7.9 would leave a permanent phantom "update available" that no
        // install can ever clear. There is no versioned public download path either
        // (`/1.7.9/Alcove.dmg`, `?version=…` etc. all 404 or serve the same stale
        // trial build), so users without a license key are sent to the download page
        // by hand — and Alcove's own updater keeps them current regardless.
        //
        // Notes come from the `api.tryalcove.com/changelog` ChangelogRecipe below;
        // `changelogURL` is the page the notes pane falls back to, and links out
        // to, when no recipe applies (`ChangelogRecipeSelection.fallbackPage`).
        // That page is not what gets parsed:
        // www.tryalcove.com/changelog is a real page — it server-renders every version
        // and date, newest 1.7.9 — but it is not scrapable: each entry's body is an
        // empty placeholder, with the actual features/fixes arrays inlined in a
        // content-hashed minified route chunk (`/assets/ChangelogPage-<hash>.js`)
        // whose filename changes on every deploy.
        VendorProbeRecipe(
            bundleID: "com.henrikruscon.Alcove",
            url: URL(string: "https://download.tryalcove.com/latest")!,
            mode: .responseBody,
            versionPattern: #"(?:^|[{,])\s*"version"\s*:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)*)""#,
            downloadURL: URL(string: "https://www.tryalcove.com/download")!,
            changelogURL: URL(string: "https://www.tryalcove.com/changelog"),
            // Single-release document, so the first (only) `published_at` is
            // unambiguously this version's — ISO8601 with fractional seconds
            // ("2026-06-30T20:57:57.000Z"), which ReleaseDate parses. Gives the
            // Release Log an exact time instead of an estimated "≈" window, even
            // without a license key.
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#),

        // Alcove — handled by `AlcoveUpdateSource` (licensed api.tryalcove.com), with
        // the public `download.tryalcove.com/latest` VendorProbeRecipe above as the
        // no-credential fallback. There is no GitHub rule: the
        // `henrikruscon/alcove-releases` mirror one used to read LAGS the real release
        // (2026-06-14: stuck at 1.7.2 while the vendor served 1.7.3). Only the
        // licensed channel is authoritative; see `AlcoveUpdateSource`.
        ],
        changelogs: [
        // Alcove — its own changelog API. Public and unauthenticated, unlike the
        // update endpoint on the same host, which is license-gated (see
        // `AlcoveUpdateSource`). Structured JSON: majors, each holding its point
        // releases with date, note, features and fixes. Newest is 1.7.9, matching
        // the installed copy on 2026-08-22.
        //
        // This replaces a web view on `tryalcove.com/changelog`, whose text lives
        // in hash-named JS chunks — the reason that page was only ever linked, not
        // read. The API is a different surface and a far better one.
        ChangelogRecipe(
            bundleID: "com.henrikruscon.Alcove",
            source: URL(string: "https://api.tryalcove.com/changelog")!,
            mode: .json,
            maxEntries: 30,
            structuredFormat: .alcoveChangelog),
        ])
}
