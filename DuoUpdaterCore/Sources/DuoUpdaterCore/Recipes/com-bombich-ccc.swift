import Foundation

enum com_bombich_ccc {
    static let set = AppRecipeSet(
        family: "com-bombich-ccc",
        probes: [
        // History: docs/app-audits/com-bombich-ccc.md#历史与实测
        // Carbon Copy Cloner — THREE separately downloadable major-version
        // generations (5, 6, 7) all report the SAME bundle id `com.bombich.ccc` under
        // the same Team `L4F2DED5Q7`. Bombich keeps
        // all three downloadable (`download_ccc.php` answers `?v=ccc5`, `?v=ccc6` and
        // `?v=ccc7`, plus `?v=latest`, a permanent alias for whichever generation is
        // newest; bombich.com/download links the CCC 5 and 6 downloads and says their
        // development ceased when CCC 6 and CCC 7 shipped) and crossing generations is
        // a PAID upgrade, not a free
        // update: "We do not sell CCC 4 or CCC 5 licenses. To use CCC 4 or 5,
        // please purchase a CCC 6 license" (bombich.com/en/kb/ccc/6). CCC 7 also
        // requires Ventura+ (bombich.com/download's own compatibility table),
        // which a CCC 5 install on High Sierra–Big Sur or a CCC 6 install on
        // Catalina–Monterey cannot run at all.
        //
        // Each generation therefore gets its own recipe, gated with
        // `installedVersionPattern` so `VendorProbeSource` only offers a
        // same-generation point release — never routes a CCC 5/6 install through
        // `?v=latest`'s CCC 7 answer just because, e.g., "7.1.6" sorts numerically
        // above "5.1.28"/"6.1.13". Without this gate every CCC 5/6 install in
        // this registry would have been a phantom cross-generation "update"
        // forever, silently, the same shape of bug `VersionComparator`'s
        // "never compare across namespaces" rule exists to prevent — just one
        // this registry had not modeled before because no other vendor here
        // keeps multiple generations downloadable side by side under one bundle id.
        //
        // stable (CCC 7) — the app DOES ship a Sparkle
        // `SUFeedURL` (`https://api.bombich.com/updates/ccc`), so it is not the
        // "no Sparkle at all" case it first looks like. But that feed answers
        // every request we tried — plain GET, several User-Agents including a
        // Sparkle-shaped one, an `appVersion` query param, and the same
        // `URLSession`/UA `SparkleAppcastSource` itself sends — with HTTP 200 and
        // a ZERO-BYTE body.
        // `SparkleAppcastSource` would parse that into an empty item list and
        // report "no update" forever: a silent dead source, not a missing one.
        // Homebrew's cask carries `auto_updates: true`, so `HomebrewCaskSource`
        // correctly refuses it too — there is no standard source left to answer.
        //
        // The endpoint that DOES work is the `download_ccc.php` one the cask's own
        // `livecheck` block relies on — but this recipe probes `?v=ccc7`, NOT the
        // `?v=latest` the cask uses. Both 302 (through a second hop at
        // `api.bombich.com/download/ccc?v=…`) to the same versioned filename on the
        // CDN while CCC 7 is the newest generation. They stop being the same file
        // the day CCC 8 ships: `?v=latest` is
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
        // `ccc-8.…` filename fails to match and the probe fails (`ProbeFailed`, a
        // Failed row) rather than reporting a cross-generation version. Failing closed
        // here is right — a recipe that fails shows up in the nightly `duo verify`
        // sweep, a recipe
        // that reports a paid upgrade as a point release does not. The captured
        // marketing version matches the bundle's `CFBundleShortVersionString`
        // exactly (e.g. `7.1.6`, with `8368` matching `CFBundleVersion`), and CCC
        // bumps its marketing version on every release (e.g. 7.0 → 7.0.4 → 7.1 → … → 7.1.6, roughly
        // quarterly per `https://bombich.com/software/updates/ccc7_rn.html`) — not
        // a frozen-marketing app — so the default marketing-only comparison
        // (`versionIsBuild: false`) is correct, no build-number routing needed.
        // The filename's marketing segment is 2 OR 3 dot-groups depending on era
        // (e.g. `ccc-7.1.1234.zip` for a bare `7.1` release vs `ccc-7.1.6.8368.zip`),
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
        // `?v=latestbeta` (no hyphen) 302s through the same two-hop chain as stable
        // to the beta's zip (`ccc-<marketing>-b<N>.<build>.zip`) while a beta is on
        // offer, and to the plain stable zip between cycles — measured, not
        // "likely": when checked (2026-09-14) it answered with the same stable zip
        // as `?v=ccc7` and `?v=latest` (History has the filename). `versionPattern`
        // accepts BOTH, which is why `-b<N>` is optional below. It used to require
        // the suffix, so the between-cycles answer matched nothing and the probe
        // threw `ProbeFailed` (`VendorProbeSource`): a failed-check row, and a
        // `duo verify` finding on every machine for a recipe working as written
        // (issue #612). Marketing matches the probed capture group exactly, so
        // `versionIsBuild` stays the default `false`, same as stable.
        //
        // That stable answer is the vendor's ordinary RESTING state between
        // cycles, not an outage, and the graduation is the vendor's own text
        // rather than an inference: `ccc7_rn.html` skips 7.1.7 entirely (7.1.6 →
        // 7.2) and 7.2's "What's new" is the beta page's cycle list item for
        // item, while that beta page stayed frozen on the closed cycle's last
        // prerelease. Both readings are in `docs/app-audits/com-bombich-ccc.md`.
        //
        // Anchoring to `-b` instead fails on that resting state in both of the
        // ways CotEditor's beta rule (`Recipes/com-coteditor-CotEditor.swift`)
        // spells out for the same vendor shape:
        //
        //   • A copy on `7.1.7-b7` is never offered the `7.2` that graduated from
        //     its own train, and sits on a superseded prerelease until the next
        //     cycle opens. (CotEditor's version of this bullet adds "while the
        //     vendor's own updater hands it that release". Not repeated here: CCC
        //     ships Sparkle but its feed is the dead zero-byte one described
        //     above, so its own updater hands a beta copy nothing either. The
        //     vendor's DOWNLOAD endpoint for beta users is what serves the
        //     graduation, which is the thing measured.)
        //     `VersionComparator` ranks the graduation on its own, and with more
        //     room to spare than CotEditor's pair: `7.2` beats `7.1.7-b7` at the
        //     SECOND component, so it never reaches the `.text`-versus-padded-
        //     `.number(0)` rule `7.1.0` / `7.1.0-beta.6` depends on. The pattern
        //     was the only thing in the way.
        //   • And it is not a quiet nil. `duo verify` walks RECIPES, not
        //     installs, so the miss is a red finding on every machine for a
        //     recipe working exactly as written, and the row shows a failed check
        //     behind a Retry button that cannot work.
        //
        // ⚠️ THE COST IS ONE-WAY, and unlike CotEditor it is NOT recoverable here
        // without a code change. Taking the graduation puts the copy on `7.2`,
        // `ReleaseChannel.detect` step 0.8 finds no `-b<N>` and answers
        // `.stable`, and the stable recipe serves it from the next check on — so
        // we stop offering it prereleases. CotEditor escapes that because
        // `CotEditorChannel` reads the vendor's own prerelease checkbox and is
        // authoritative whatever the version string says. CCC has the same
        // checkbox (quoted above) and nothing here reads it — there is no
        // `ChannelBinding` for `com.bombich.ccc` — so this is WhatCable's shape,
        // not CotEditor's, and a user who wants back on the train installs a beta
        // by hand. Taken anyway because the alternative is a row that is
        // permanently red and offered nothing at all, and because this recipe is
        // detection-only: nothing is installed for them, `downloadURL` sends them
        // to the vendor's own beta endpoint, and what they get there is the same
        // artifact this probe just read.
        //
        // ⚠️ AND A RETIRED BETA RAIL IS NOW INVISIBLE. Requiring `-b` had a side
        // effect worth naming: if Bombich ever drops or renames `?v=latestbeta`,
        // the answer stops being a beta filename and the probe goes red, so
        // somebody looks. It now resolves the stable zip and stays GREEN forever
        // — "the cycle is resting" and "the rail is gone" are the same bytes, and
        // nothing else here would notice (no `install`, so no proof questions it;
        // the Homebrew cask is `auto_updates: true`, so no cross-check either).
        // `trackClosedPattern` is not the answer: it wants the VENDOR to say the
        // track is empty, and this endpoint says nothing — it just hands you a
        // different file. Accepted knowingly, the same trade CotEditor's beta rule
        // makes by accepting a stable tag.
        //
        // ⚠️ And a copy AHEAD of the graduation reads a lower "latest". If a cycle
        // closes back to a stable older than the installed prerelease (on
        // `7.2.1-b1`, endpoint answers `7.2`), `VersionComparator` correctly
        // offers nothing, but the row names a smaller number and
        // `RecipeSanity.remoteBehindInstalled` starts raising an advisory — the
        // shape CotEditor's comment accepts as "a row that says up to date beside
        // a lower number". Not what happened in the 7.1.7-b7 → 7.2 transition
        // (the endpoint served `-b7` right up to 7.2's release; see the audit),
        // so this is a reachable shape, not an observed one.
        //
        // ⚠️ The other half of the cost is the changelog: `ccc7_rn_beta.html` is
        // the CLOSED cycle's page, so between cycles the offered version and the
        // notes beside it disagree (7.2 offered, 7.1.7-b7 described). Left as is
        // — the stable page is not this channel's page either, and swapping by
        // shape would mean guessing which state the vendor is in from the
        // filename, which is the inference this recipe avoids everywhere else.
        //
        // CHANNEL SIGNAL: `CFBundleShortVersionString` carries a short `-b<N>`
        // suffix (e.g. "7.1.7-b7") that `ReleaseChannel.detect()` needed a new
        // bundle-id-scoped rule for (step 0.8) — it is neither the Mozilla
        // `b<N>` shape (requires exactly one dot, no dash) nor the full-word
        // `-beta<N>` shape (GitHub Desktop's), so without that rule this would
        // silently read as `.stable`.
        //
        // No `changelogURL` beyond what's already public: the same
        // `ccc7_rn_beta.html` page the stable investigation already found is reused
        // here directly rather than re-verified as a separate discovery.
        //
        // `?v=latestbeta` is itself a "latest" alias, and unlike stable there is
        // no per-generation twin to switch to. So the anchor on
        // `versionPattern` — major 7, same as stable's — is the only guard
        // available here, and making `-b<N>` optional puts the WHOLE weight on it:
        // requiring `-b` used to reject a CCC 8 STABLE filename as a side effect,
        // and now only the `7` does. It still fails closed in both shapes —
        // `ccc-8.0.2-b1.9012.zip` and `ccc-8.0.1.9000.zip` alike fail to match, so
        // the probe fails (a Failed row, and a finding in the nightly sweep)
        // instead of offering a CCC 7 install a CCC 8 build, beta or paid upgrade.
        //
        // ⚠️ THE ENDPOINT IS NOW THE ONLY THING THAT SAYS "BETA". `-b[0-9]+` used
        // to be a second, independent statement of which train an answer came
        // from; it is now satisfied by a stable filename, so `url`'s
        // `v=latestbeta` carries that alone — the endpoint-keyed shape
        // `ChannelArtifactProof.recipeAnchor(_, in: ["url"])` exists for (IntelliJ
        // EAP's and Alfred beta's are the registered ones). None is registered
        // here because none is required: `ChannelProofRegistry.proofs` has to
        // cover `channelRecipesWithInstall`, this recipe carries no `install`, and
        // `RecipeSanity.crossChannelArtifact` returns nil at its first guard. The
        // day an install spec is added, the proof that becomes mandatory is
        // `.recipeAnchor(#"latestbeta"#, in: ["url"])` and NOT an `.artifact` one
        // anchored to `-b`: that one passes every day the vendor has a cycle open
        // and fails on exactly the release it is there to judge — the mistake
        // CotEditor's own proof entry records having shipped for a day.
        //
        // No `install`, same reasoning as stable — the privileged-helper
        // footprint applies equally to both channels. `installedVersionPattern`
        // scopes this to CCC 7 for the same reason stable's does — there is no
        // evidence CCC 5/6 currently ship a beta at all, so this is
        // scoped to what was actually observed, not assumed to generalize.
        VendorProbeRecipe(
            bundleID: "com.bombich.ccc",
            url: URL(string: "https://bombich.com/software/download_ccc.php?v=latestbeta")!,
            mode: .redirectFilename,
            versionPattern: #"^ccc-(7(?:\.[0-9]+)+(?:-b[0-9]+)?)\.[0-9]{3,}\.zip$"#,
            downloadURL: URL(string: "https://bombich.com/software/download_ccc.php?v=latestbeta"),
            changelogURL: URL(string: "https://bombich.com/software/updates/ccc7_rn_beta.html"),
            channel: .beta,
            hostRequirement: VendorHostRequirement(minimumSystemVersion: "13.1"),
            installedVersionPattern: #"^7\."#),

        // stable (CCC 6) — DOES carry a Sparkle `SUFeedURL`
        // (`https://update.bombich.com/software/updates/ccc.php`) — a DIFFERENT
        // literal URL than CCC 7's
        // (`api.bombich.com/updates/ccc`), so this is not simply "same feed,
        // different app". But it 301s → 302s straight into that exact CCC 7
        // feed URL and returns the identical HTTP 200 + zero-byte body — so
        // Bombich's whole
        // Sparkle update backend is dead across all three generations, not a
        // CCC-7-specific outage, and `SparkleAppcastSource` is a dead end here
        // too. No MAS listing, no GitHub repo. Same `download_ccc.php` endpoint
        // as detection, `v=ccc6` instead of `ccc7`/`latestbeta`. Same filename
        // shape as CCC 7 (`ccc-<marketing>.<build>.zip`),
        // so the same pattern applies, anchored to major 6 the way CCC 7's is to
        // major 7 — a per-generation endpoint that ever answered with another
        // generation's file would be a vendor-side change, and this recipe should
        // fail and get triaged rather than quietly report it.
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
        // `ccc7_rn.html`).
        //
        // No `install`: same privileged-helper footprint as CCC 7, so
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
        // Same filename shape, same pattern,
        // anchored to major 5 for the same reason CCC 6's is to major 6.
        // `installedVersionPattern` pins this to CCC 5 for the identical reason
        // CCC 6's does. changelogURL is CCC 5's own release-notes page. No
        // `install`, same reasoning as the other two.
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
