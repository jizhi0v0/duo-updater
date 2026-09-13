import Foundation

enum com_bombich_ccc {
    static let set = AppRecipeSet(
        family: "com-bombich-ccc",
        probes: [
        // Carbon Copy Cloner — THREE independently maintained major-version
        // generations (5, 6, 7) all report the SAME bundle id `com.bombich.ccc`,
        // confirmed 2026-08-29 by downloading and expanding all three real zips:
        // `com.bombich.ccc` 5.1.28/6213, `com.bombich.ccc` 6.1.13/7699,
        // `com.bombich.ccc` 7.1.6/8368 — same Team `L4F2DED5Q7`. Bombich still
        // ships point releases to all three (bombich.com/download lists
        // `?v=ccc5`/`?v=ccc6`/`?v=ccc7` as live download links alongside
        // `?v=latest`, which is a permanent alias for whichever is newest —
        // currently ccc7) and crossing generations is a PAID upgrade, not a free
        // update: "We do not sell CCC 4 or CCC 5 licenses. To use CCC 4 or 5,
        // please purchase a CCC 6 license" (bombich.com/en/kb/ccc/6). CCC 7 also
        // requires Ventura+ (bombich.com/download's own compatibility table),
        // which a CCC 5 install on High Sierra–Big Sur or a CCC 6 install on
        // Catalina–Monterey cannot run at all.
        //
        // Each generation therefore gets its own recipe, gated with
        // `installedVersionPattern` so `VendorProbeSource` only offers a
        // same-generation point release — never routes a CCC 5/6 install through
        // `?v=latest`'s CCC 7 answer just because "7.1.6" sorts numerically
        // above "5.1.28"/"6.1.13". Without this gate every CCC 5/6 install in
        // this registry would have been a phantom cross-generation "update"
        // forever, silently, the same shape of bug `VersionComparator`'s
        // "never compare across namespaces" rule exists to prevent — just one
        // this registry had not modeled before because no other vendor here
        // keeps multiple ACTIVELY maintained generations under one bundle id.
        //
        // stable (CCC 7) — the app DOES ship a Sparkle
        // `SUFeedURL` (`https://api.bombich.com/updates/ccc`, confirmed reading
        // the real Info.plist inside the vendor's own download), so it is not the
        // "no Sparkle at all" case it first looks like. But that feed answers
        // every request we tried — plain GET, several User-Agents including a
        // Sparkle-shaped one, an `appVersion` query param, and the same
        // `URLSession`/UA `SparkleAppcastSource` itself sends — with HTTP 200 and
        // a ZERO-BYTE body (verified 2026-08-29, five variants, all `Content-Length: 0`).
        // `SparkleAppcastSource` would parse that into an empty item list and
        // report "no update" forever: a silent dead source, not a missing one.
        // Homebrew's cask carries `auto_updates: true`, so `HomebrewCaskSource`
        // correctly refuses it too — there is no standard source left to answer.
        //
        // The endpoint that DOES work is the `download_ccc.php` one the cask's own
        // `livecheck` block relies on — but this recipe probes `?v=ccc7`, NOT the
        // `?v=latest` the cask uses. Both 302 (through a second hop at
        // `api.bombich.com/download/ccc?v=…`) to the same versioned filename on the
        // CDN today — `ccc-7.1.6.8368.zip`, both confirmed 2026-08-30 with plain
        // HEAD requests (the exact request `.redirectFilename` issues), which
        // follow both hops and land on the CDN URL without downloading the 27 MB
        // body. They stop being the same file the day CCC 8 ships: `?v=latest` is
        // a permanent alias for whichever generation is NEWEST, so it would then
        // answer this CCC-7-scoped recipe with a CCC 8 artifact and hand every CCC
        // 7 install a phantom paid major-version "update" — the exact bug
        // `installedVersionPattern` exists to prevent, arriving through the URL
        // instead of through the version comparison. `?v=ccc7` is a
        // per-generation alias like the `?v=ccc5`/`?v=ccc6` the two recipes below
        // use, and those are the evidence it will keep pointing at CCC 7: both are
        // still live and still serving their own generation's last build years
        // after they stopped being "latest".
        //
        // `versionPattern` is anchored to major 7 for the same reason, as a second
        // independent guard: if Bombich ever repoints `?v=ccc7` (or drops it), an
        // `ccc-8.…` filename fails to match and the probe reports nothing rather
        // than a cross-generation version. Failing closed here is right — a recipe
        // that goes quiet shows up in the nightly `duo verify` sweep, a recipe
        // that reports a paid upgrade as a point release does not. `7.1.6` matches the installed app's `CFBundleShortVersionString`
        // exactly (`8368` matches `CFBundleVersion`), and CCC bumps its marketing
        // version on every release (7.0 → 7.0.4 → 7.1 → … → 7.1.6, roughly
        // quarterly per `https://bombich.com/software/updates/ccc7_rn.html`) — not
        // a frozen-marketing app — so the default marketing-only comparison
        // (`versionIsBuild: false`) is correct, no build-number routing needed.
        // The filename's marketing segment is 2 OR 3 dot-groups depending on era
        // (`ccc-7.1.1234.zip` for a bare `7.1` release vs `ccc-7.1.6.8368.zip`),
        // which is exactly why the cask's own `livecheck` comment calls out a
        // "variable number of parts" — the pattern below accepts both, always
        // taking everything before the trailing 3+ digit build segment.
        //
        // No `install`: this is detection-only. CCC installs a privileged helper
        // (`com.bombich.ccchelper`), a LaunchDaemon and an XPC service alongside
        // the `.app`, so an in-place bundle swap is a materially bigger claim than
        // the zip-swap one-clicks already in this registry; adding it is a
        // separate decision.
        //
        // `hostRequirement.minimumSystemVersion`: read from the real 7.1.6 binary's
        // `LSMinimumSystemVersion` (13.1), which agrees with Bombich's own
        // published requirement for this generation ("macOS 13 Ventura (13.1+)").
        // This is safe to pin as a STATIC floor — unlike a per-release value that
        // could drift, Bombich documents system requirements per MAJOR VERSION as
        // its own standing KB article and a Wayback snapshot of CCC 6's equivalent
        // page from 2022-05 (a year after its 2021 launch) already stated the same
        // floor CCC 6 still states today, 2023-11 — i.e. the floor is a fixed
        // per-generation commitment for that generation's whole lifetime, the same
        // shape `hostRequirement` already models for Raycast v2 (macOS 26+,
        // permanent for that track), not the shape Sparkle's per-item
        // `minimumSystemVersion` exists for (a value that legitimately varies
        // release to release, and is read fresh from each item for that reason).
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc7")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-(7\.[0-9]+(?:\.[0-9]+)?)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc7"),
            changelogURL: URL(string: "https://bombich.com/software/updates/ccc7_rn.html"),
            variant: "ccc7",
            hostRequirement: VendorHostRequirement(minimumSystemVersion: "13.1"),
            installedVersionPattern: #"^7\."#),

        // beta (CCC 7) — same bundle id, opted into from
        // CCC's own Settings → Software Update → "Inform me of beta releases".
        // The blocker recorded on 2026-08-29 (needs the user's own packet
        // capture — `?v=beta` redirects to the plain download page, and
        // `?v=latest-beta` just resolves to the stable zip) turned out to be a
        // wrong guess at the query param spelling, not a real auth wall:
        // `?v=latestbeta` (no hyphen) 302s through the same two-hop chain as
        // stable to a genuine beta artifact —
        // `ccc-7.1.7-b7.8389.zip` — confirmed 2026-08-29 by downloading and
        // expanding the real zip: `CFBundleShortVersionString="7.1.7-b7"
        // CFBundleVersion="8389" CFBundleIdentifier="com.bombich.ccc"`, Team
        // `L4F2DED5Q7`, notarized. Marketing matches the probed capture group
        // exactly, so `versionIsBuild` stays the default `false`, same as
        // stable.
        //
        // CHANNEL SIGNAL: `CFBundleShortVersionString` carries a short `-b<N>`
        // suffix ("7.1.7-b7") that `ReleaseChannel.detect()` needed a new
        // bundle-id-scoped rule for (step 0.8) — it is neither the Mozilla
        // `b<N>` shape (requires exactly one dot, no dash) nor the full-word
        // `-beta<N>` shape (GitHub Desktop's), so without that rule this would
        // silently read as `.stable`.
        //
        // No `changelogURL` beyond what's already public: the same
        // `ccc7_rn_beta.html` page the stable investigation already found
        // (lists "CCC 7.1.7-b7 (pre-release)") is reused here directly rather
        // than re-verified as a separate discovery.
        //
        // `?v=latestbeta` is itself a "latest" alias, and unlike stable there is
        // no per-generation twin to switch to: probed 2026-08-30, `?v=ccc7beta`
        // and `?v=ccc7-beta` both answer with the STABLE ccc7 zip (the endpoint
        // prefix-matches `ccc7` and ignores the rest) and `?v=beta7` falls back to
        // the plain download page. So the anchor on `versionPattern` — major 7,
        // same as stable's — is the only guard available here, and it fails closed:
        // the first CCC 8 beta produces an `ccc-8.…-b<N>.…zip` filename this
        // pattern does not match, so the probe reports nothing (and surfaces in the
        // nightly sweep) instead of offering a CCC 7 install a CCC 8 beta.
        //
        // No `install`, same reasoning as stable — the privileged-helper
        // footprint applies equally to both channels. `installedVersionPattern`
        // scopes this to CCC 7 for the same reason stable's does — there is no
        // evidence CCC 5/6 currently ship a beta at all (`?v=beta`/`?v=latestbeta`
        // only ever answered with a CCC 7 artifact, 2026-08-29), so this is
        // scoped to what was actually observed, not assumed to generalize.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=latestbeta")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-(7(?:\.[0-9]+)+-b[0-9]+)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=latestbeta"),
            changelogURL: URL(string: "https://bombich.com/software/updates/ccc7_rn_beta.html"),
            channel: .beta,
            hostRequirement: VendorHostRequirement(minimumSystemVersion: "13.1"),
            installedVersionPattern: #"^7\."#),

        // stable (CCC 6) — DOES carry a Sparkle `SUFeedURL`
        // (`https://update.bombich.com/software/updates/ccc.php`, read from the
        // mounted 6.1.13 bundle) — a DIFFERENT literal URL than CCC 7's
        // (`api.bombich.com/updates/ccc`), so this is not simply "same feed,
        // different app". But it 301s → 302s straight into that exact CCC 7
        // feed URL and returns the identical HTTP 200 + zero-byte body (verified
        // 2026-08-29 following the full redirect chain) — so Bombich's whole
        // Sparkle update backend is dead across all three generations, not a
        // CCC-7-specific outage, and `SparkleAppcastSource` is a dead end here
        // too. No MAS listing, no GitHub repo. Same `download_ccc.php` endpoint
        // as detection, `v=ccc6`
        // instead of `latest`/`latestbeta` — confirmed 2026-08-29 with a plain
        // HEAD request: two-hop redirect to `ccc-6.1.13.7699.zip`, matching the
        // mounted bundle's `CFBundleShortVersionString`/`CFBundleVersion`
        // exactly. Same filename shape as CCC 7 (`ccc-<marketing>.<build>.zip`),
        // so the same pattern applies, anchored to major 6 the way CCC 7's is to
        // major 7 — a per-generation endpoint that ever answered with another
        // generation's file would be a vendor-side change, and this recipe should
        // go quiet and get triaged rather than quietly report it.
        //
        // `installedVersionPattern` pins this to CCC 6 — without it this recipe
        // and CCC 7's would both match a CCC 6 install (nothing else
        // distinguishes them structurally) and `VendorProbeSource.best(of:)`
        // would report whichever answered a higher version, which is CCC 7's,
        // recreating the exact bug this whole three-recipe split exists to fix.
        //
        // `variant` is required here too, separately from that: three recipes
        // share (bundleID, channel) = (`com.bombich.ccc`, `.stable`), and
        // `channelProofsCoverEveryChannelRecipe` requires every recipe in such a
        // group to carry a distinct `variant` — otherwise they'd collide onto
        // one `recipeID` and share a verify baseline / issue history despite
        // being three different endpoints.
        //
        // changelogURL: CCC 6's own release-notes page (distinct from CCC 7's
        // `ccc7_rn.html`) — verified 200 with real per-version content
        // 2026-08-29, titled "CCC 6 Release Notes".
        //
        // No `install`: same privileged-helper footprint as CCC 7 (confirmed by
        // the same category of components in the mounted 6.1.13 app), so
        // detection-only for the same reason.
        //
        // `hostRequirement.minimumSystemVersion`: 10.15, read from the real 6.1.13
        // binary's `LSMinimumSystemVersion` and independently confirmed against a
        // Wayback Machine snapshot of Bombich's own CCC 6 system-requirements page
        // from 2022-05-18 (a year after CCC 6's 2021 launch) — it already stated
        // "macOS 10.15 Catalina" as the floor back then, and the current page
        // (last updated 2023-11-06) still does. Two-plus years with no floor
        // movement is why this is safe as a static value — see the longer
        // reasoning on the CCC 7 stable recipe above.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc6")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-(6\.[0-9]+(?:\.[0-9]+)?)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc6"),
            changelogURL: URL(string: "https://bombich.com/en/kb/ccc/6/release-notes"),
            variant: "ccc6",
            hostRequirement: VendorHostRequirement(minimumSystemVersion: "10.15"),
            installedVersionPattern: #"^6\."#),

        // stable (CCC 5) — same reasoning as CCC 6 above, one generation older.
        // `v=ccc5` confirmed 2026-08-29: two-hop redirect to
        // `ccc-5.1.28.6213.zip`, matching the mounted bundle's
        // `CFBundleShortVersionString`/`CFBundleVersion` exactly (Team
        // `L4F2DED5Q7`, same as 6 and 7). Same filename shape, same pattern,
        // anchored to major 5 for the same reason CCC 6's is to major 6.
        // `installedVersionPattern` pins this to CCC 5 for the identical reason
        // CCC 6's does. changelogURL is CCC 5's own release-notes page, verified
        // 200 2026-08-29. No `install`, same reasoning as the other two.
        //
        // `hostRequirement.minimumSystemVersion`: 10.10, read from the real
        // 5.1.28 binary's `LSMinimumSystemVersion` — and this one has a second,
        // independent witness: Bombich's own CCC 5 system-requirements KB page
        // (last updated 2021-02-16, effectively frozen since — CCC 5's
        // development ceased when CCC 6 shipped in May 2021) states "OS X 10.10
        // Yosemite" as the floor verbatim. Two sources, same number.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc5")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-(5\.[0-9]+(?:\.[0-9]+)?)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=ccc5"),
            changelogURL: URL(string: "https://bombich.com/en/kb/ccc/5/release-notes"),
            variant: "ccc5",
            hostRequirement: VendorHostRequirement(minimumSystemVersion: "10.10"),
            installedVersionPattern: #"^5\."#),
        ])
}
