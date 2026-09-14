import Foundation

enum com_henrikruscon_Alcove {
    static let set = AppRecipeSet(
        family: "com-henrikruscon-Alcove",
        probes: [
        // History: docs/app-audits/com-henrikruscon-Alcove.md#历史与实测
        // Alcove — the PUBLIC, no-credential fallback. The authoritative source is
        // `AlcoveUpdateSource` (the licensed api.tryalcove.com channel the app's own
        // "Reworked update manager" uses), wired ahead of this probe so it answers
        // first whenever the user's license credentials are seeded; this recipe is
        // what everyone else gets.
        //
        // The old endpoint (update.tryalcove.com) is GONE — it stopped resolving
        // (NXDOMAIN; History has the dates). Its replacement is the download host's
        // own metadata endpoint, `download.tryalcove.com/latest` — a small
        // unauthenticated JSON doc, e.g.:
        //   {"version":"1.7.9","build":203,"published_at":"…","assets":[…],
        //    "minimum_system_version":"15 Sequoia"}
        // `version` is the marketing string (== CFBundleShortVersionString — no build
        // trap; `build` is carried separately and we ignore it). When checked against
        // the licensed channel on 2026-07-29 it matched build-for-build — unlike every
        // mirror before it, IN SYNC rather than trailing (History has the check) — which
        // is why this document is trusted for detection while the public binaries
        // below are not. Single-channel as far as it has been probed: `?channel=beta`
        // answered 404 ("No releases available") and an `X-Channel` header changed
        // nothing (History has both checks).
        //
        // The pattern requires `{` or `,` before the key so it can never drift onto
        // the sibling `minimum_system_version` (whose value, "15 Sequoia", isn't
        // version-shaped anyway) if the vendor reorders fields.
        //
        // DETECTION-ONLY, deliberately — do NOT re-attach an install spec. The public
        // binaries at download.tryalcove.com/{Alcove.dmg,Alcove.zip} are the *trial*
        // build and have lagged this metadata badly (History has both checks).
        // Installing it while claiming the
        // metadata's version would leave a permanent phantom "update available" that
        // no install can ever clear. There is no versioned public download path either
        // (e.g. `/1.7.9/Alcove.dmg`, `?version=…` all 404 or serve the same stale
        // trial build), so users without a license key are sent to the download page
        // by hand — and Alcove's own updater keeps them current regardless.
        //
        // Notes come from the `api.tryalcove.com/changelog` ChangelogRecipe below;
        // `changelogURL` is the page the notes pane falls back to, and links out
        // to, when no recipe applies (`ChangelogRecipeSelection.fallbackPage`).
        // That page is not what gets parsed: neither shape www.tryalcove.com/changelog
        // has served offered scrapable notes — most recently its HTML carried no
        // version text at all (History has both shapes, with dates).
        VendorProbeRecipe(
            bundleID: "com.henrikruscon.Alcove",
            url: URL(string: "https://download.tryalcove.com/latest")!,
            mode: .responseBody,
            versionPattern: #"(?:^|[{,])\s*"version"\s*:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)*)""#,
            downloadURL: URL(string: "https://www.tryalcove.com/download")!,
            changelogURL: URL(string: "https://www.tryalcove.com/changelog"),
            // Single-release document, so the first (only) `published_at` is
            // unambiguously this version's — ISO8601 with fractional seconds
            // (e.g. "2026-06-30T20:57:57.000Z"), which ReleaseDate parses. Gives the
            // Release Log an exact time instead of an estimated "≈" window, even
            // without a license key.
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#),

        // Alcove — handled by `AlcoveUpdateSource` (licensed api.tryalcove.com), with
        // the public `download.tryalcove.com/latest` VendorProbeRecipe above as the
        // no-credential fallback. There is no GitHub rule: the
        // `henrikruscon/alcove-releases` mirror one used to read LAGS the real release.
        // Only the licensed channel is authoritative; see `AlcoveUpdateSource`.
        ],
        changelogs: [
        // Alcove — its own changelog API. Public and unauthenticated, unlike the
        // update endpoint on the same host, which is license-gated (see
        // `AlcoveUpdateSource`). Structured JSON: majors, each holding its point
        // releases with date, note, features and fixes.
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
