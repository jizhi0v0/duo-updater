import Foundation

enum com_coteditor_CotEditor {
    static let set = AppRecipeSet(
        family: "com-coteditor-CotEditor",
        changelogs: [
        // CotEditor — the GitHub source already renders the release it is
        // OFFERING (the bodies are structured Markdown: `## Improvements`,
        // `## Known Issues`, measured through the source on both rails), so what
        // these two add is the rest of the rail: the previous releases in the
        // changelog panel.
        //
        // `per_page=40` with `maxEntries: 20` is the house shape. Measured
        // 2026-09-06: the newest 40 releases hold 34 stable and 6 prerelease.
        //
        // ⚠️ BOTH rails therefore fill their 20, and the beta rail's 20 are mostly
        // STABLE entries — `includesPromotedStable` makes
        // `StructuredChangelogDecoder.decodeGitHubReleases` want every
        // non-prerelease, not only the one that graduates, so the beta rail is
        // simply the newest 20 releases (7.1.0-beta.6, 7.0.9, 7.1.0-beta.5, …).
        // That is the field's existing behaviour and it is what this rail wants —
        // the copy can be offered any of them — but it is not "the 6 betas", which
        // is what an earlier version of this comment claimed. All 6 do fit: they
        // sit inside the newest 8 releases.
        //
        // ⚠️ `includesPromotedStable: true` on the beta recipe is the OPPOSITE of
        // Yaak's pair (`Recipes/app-yaak-desktop.swift`), and the difference is in the rules, not in taste.
        // Yaak's beta rule cannot resolve a stable artifact, so a promoted entry
        // there would describe a build that channel never offers. CotEditor's beta
        // rule can and must — its train runs in cycles and a copy has to be able
        // to take the release that graduates from it — so without this the panel
        // would omit the very entry the row is offering, which is UTM's case
        // exactly (see the field's own doc).
        ChangelogRecipe(
            bundleID: "com.coteditor.CotEditor",
            source: URL(string: "https://api.github.com/repos/coteditor/CotEditor/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),

        ChangelogRecipe(
            bundleID: "com.coteditor.CotEditor",
            source: URL(string: "https://api.github.com/repos/coteditor/CotEditor/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .beta,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases),
        ],
        githubRules: [
        // CotEditor — read through GitHub DELIBERATELY, not through its appcast.
        //
        // The app ships Sparkle and publishes a well-formed feed, and reading it
        // is what #368 was about: that feed keeps ONE prerelease slot, so every
        // beta but the newest is trimmed out of it, `channel(ofInstalled:)` then
        // misses on both passes, and the copy falls back to the default channel —
        // where the stable line outranks it by build (843 against 840) and is
        // three marketing versions older. GitHub keeps every release, and the tag
        // says which train it is on, so the channel needs no lookup that history
        // can invalidate. `SparkleFeedCatalog` therefore does NOT carry the feed:
        // Sparkle answers before GitHub in `SourceStack`, and would take this back.
        //
        // Measured on the 100 newest releases (2026-09-06): 0 drafts, no `v`
        // prefix, and every one of the 100 carries exactly one asset,
        // `CotEditor_<tag>.dmg`, with no other artifact to disambiguate against.
        //
        // ⚠️ That sweep also recorded "exactly three tag shapes — `7.0.9`,
        // `7.1.0-beta`, `7.1.0-beta.6`" and the rule below was written to those
        // three. It was a true reading of a page taken mid-cycle, and it MISSED A
        // PHASE: the whole tag history (`git ls-remote --tags`, 365 tags, measured
        // 2026-09-14) holds 87 `-beta*` and 38 `-rc*`, and every minor cycle back
        // to 2.0.0 runs `-beta` → `-rc` → the plain release. The 7.1.0 cycle had
        // simply not reached its rc yet on 2026-09-06 — `7.1.0-rc` shipped
        // 2026-09-10 (asset `CotEditor_7.1.0-rc.dmg`, read off the releases API
        // 2026-09-14), and 7.1.0 stable two days after it. A shape census taken
        // inside one window is a census of that window.
        // Mounted the real 7.0.9 dmg: com.coteditor.CotEditor, short `7.0.9`
        // (== the tag), build 843, `LSMinimumSystemVersion` 15.0 matching the
        // feed's own `minimumSystemVersion`, Team HT3Z3A72WZ, notarized.
        GitHubReleaseRule(
            bundleID: "com.coteditor.CotEditor",
            owner: "coteditor", repo: "CotEditor",
            versionPattern: #"^([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern: #"^CotEditor_[0-9.]+\.dmg$"#,
            installerKind: .dmg),
        // The beta train is CYCLICAL, and that is what shapes this rule: the six
        // prereleases in those 100 releases all belong to the 7.1.0 cycle that
        // opened 2026-07-26, and the 94 releases before it — back to 2022-04 —
        // carry none.
        //
        // ONE train, TWO phases, and the counter is optional in both: a cycle runs
        // `7.1.0-beta`, `7.1.0-beta.2` … `7.1.0-beta.6`, `7.1.0-rc`, (`-rc.2` when
        // there is one — `7.0.0-rc.2` and `2.2.0-rc.3` are real), then the plain
        // `7.1.0`. All four prerelease shapes have to be accepted here, which is
        // why the suffix is optional twice over below AND why `-rc` is an
        // alternative rather than an afterthought.
        //
        // What the `-beta`-only version of this pattern did during an rc window,
        // replayed rather than reasoned about: `settle` walks the page newest-first
        // and takes the first tag the pattern accepts, so between 2026-09-10 and
        // 2026-09-12 it skipped `7.1.0-rc` and landed on `7.0.9`. A copy on
        // `7.1.0-beta.6` was therefore never offered the rc, and its row named
        // 7.0.9 — the READOUT failure described further down, arriving through a
        // phase the pattern could not see rather than through a patch release.
        // It went unreported — the window was two days wide and 7.1.0 landed on
        // top of it — and the replay above is where it comes from rather than a
        // machine that hit it. The next cycle's rc window is the one this fixes.
        //
        // **The pattern accepts stable tags too, and that is the design** — the
        // same call WhatCable's beta rule makes, for the same two reasons, and
        // both bite harder here because this vendor's train stops between cycles
        // instead of running continuously:
        //
        //   • A copy on `7.1.0-beta.6` would never be offered the plain `7.1.0`
        //     that graduates from it, and would sit on a superseded prerelease
        //     until the next cycle opened — while CotEditor's own updater hands it
        //     that release, since Sparkle allows the default channel to everyone.
        //     `VersionComparator` ranks the graduation correctly on its own (the
        //     missing fourth component pads to `.number(0)` and outranks
        //     `.text("beta")`); the pattern was the only thing in the way.
        //   • Anchoring to `-beta` is also a fuse. Once the cycle closes and the
        //     last prerelease scrolls off the page, a `-beta`-only pattern matches
        //     nothing — and that is not a quiet nil: `duo verify` walks RULES, not
        //     installs, so it would file a red finding on every machine for a rule
        //     working exactly as written. An earlier version of this comment said
        //     it "answers nil rather than erroring", which is true of a check and
        //     false of the sweep.
        //
        // ⚠️ A second consequence of accepting plain tags, and it is a READOUT one
        // rather than an offer one: `settle` walks the page newest-first and takes
        // the first tag this pattern accepts, so once a 7.0.x patch ships above the
        // newest beta — the shape #368 called the secondary form, and one this
        // vendor really maintains — the beta rail resolves THAT. Nothing is
        // offered: GitHub sets `version: nil`, so `evaluate` compares marketing and
        // `7.0.10` is older than `7.1.0-beta.6`. But the row then names 7.0.10 as
        // the latest version for a copy running a 7.1.0 beta, where a `-beta`-only
        // pattern named the copy's own build. Accepted: the alternative is the two
        // failures above, and a row that says "up to date" beside a lower number is
        // the same shape a copy ahead of its feed already produces.
        //
        // ⚠️ The cost, one-way and shared with WhatCable: taking that graduation
        // puts the copy on `7.1.0`, `ReleaseChannel.detect` then reads `.stable`,
        // and the stable rule serves it from the next check on — so we stop
        // offering it prereleases. Unlike WhatCable, that is recoverable here
        // without a code change: `CotEditorChannel` reads the vendor's own
        // "Update to prereleases when available" box, so a user who wants to stay
        // on the train ticks it and is authoritative `.beta` again whatever the
        // version string says.
        GitHubReleaseRule(
            bundleID: "com.coteditor.CotEditor",
            owner: "coteditor", repo: "CotEditor",
            usePrereleases: true,
            versionPattern:
                #"^([0-9]+\.[0-9]+\.[0-9]+(?:-beta(?:\.[0-9]+)?|-rc(?:\.[0-9]+)?)?)$"#,
            installAssetPattern:
                #"^CotEditor_[0-9.]+(?:-beta(?:\.[0-9]+)?|-rc(?:\.[0-9]+)?)?\.dmg$"#,
            installerKind: .dmg,
            channel: .beta),
        ],
        githubChannelProofs: [
        // CotEditor's beta rule accepts a plain tag as well as a `-beta` one, on
        // purpose: its beta train runs in cycles, and a copy on `7.1.0-beta.6`
        // has to be able to take the `7.1.0` that graduates from it (see the
        // rule). So an `.artifact` proof is not available — the tag segment is the
        // only place either train names itself, and a pattern anchored to `-beta`
        // would fire on exactly that legitimate resolution. Same reasoning as
        // WhatCable's entry (`Recipes/uk-whatcable-whatcable.swift`) — but NOT the same anchor, and the difference is
        // load-bearing: WhatCable's is `-beta\.`, which matches the escaped dot in
        // its own `-beta\.[0-9]+` pattern. CotEditor's cycle opens with an
        // unnumbered `7.1.0-beta`, so its pattern reads `-beta(?:` — `-beta`
        // followed by a parenthesis, never by an escaped dot. Tightening this
        // anchor to WhatCable's literal shape would make the proof report a
        // correct rule as unanchored.
        //
        // ⚠️ This was an `.artifact(#"/download/[0-9.]+-beta…/"#)` for a day, from
        // when the rule was `-beta`-only. It passed the whole time, and would have
        // gone on passing right up to the release it was wrong about.
        //
        // ⚠️ The anchor requires BOTH phases, and that is the lesson of this
        // entry's own history rather than belt-and-braces: `^true$|-beta` went on
        // passing while the pattern was blind to every `-rc` tag, exactly as the
        // `.artifact` proof before it went on passing while the pattern was blind
        // to the graduation. An anchor that names only the phase somebody happened
        // to have measured is a proof about that sweep, not about the train.
        //
        // Written as two lookaheads rather than `-beta.*-rc` so it asserts
        // PRESENCE and not ORDER: swapping the two alternatives in the pattern is
        // a rewrite with no behaviour change, and a proof that reddens on it would
        // be teaching the next person that the anchor is noise. `^true$` is the
        // `usePrereleases` half — `recipeAnchor` requires a match in EVERY named
        // field, and `true` carries neither token.
        ChannelProofKey("com.coteditor.CotEditor", .beta):
            .recipeAnchor(#"^true$|^(?=.*-beta)(?=.*-rc)"#,
                          in: ["usePrereleases", "versionPattern"]),
        ])
}
