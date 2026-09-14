import Foundation

enum uk_whatcable_whatcable {
    static let set = AppRecipeSet(
        family: "uk-whatcable-whatcable",
        githubRules: [
        // History: docs/app-audits/uk-whatcable-whatcable.md#历史与实测
        // WhatCable — an open-source menu-bar app (`uk.whatcable.whatcable`) that
        // reads what each USB-C/Thunderbolt cable plugged into the Mac can
        // actually do. Distributed from its own GitHub releases: one constant
        // asset name, `WhatCable.zip`, on every release checked (2026-09-06 and
        // 2026-09-14; History has the counts). The `whatcable-cli-<version>.zip`
        // beside it is the standalone CLI, a different artifact — the app bundle
        // ships its own copy at `Contents/Helpers/whatcable`, which is what
        // Homebrew's cask symlinks — so the pattern is anchored end to end and
        // cannot drift onto it.
        //
        // Homebrew has a `whatcable` cask, and it is deliberately not the source
        // here: it is `auto_updates true`, which this repo treats as "the app
        // updates itself, Homebrew defers" (see `HomebrewCaskSource`).
        //
        // One-click: the release asset holds `WhatCable.app`,
        // `uk.whatcable.whatcable`, CFBundleShortVersionString == the tag,
        // universal (x86_64 + arm64), signed "Developer ID Application: Darryl
        // Morley (M4RUJ7W6MP)" and accepted by `spctl` as Notarized Developer ID —
        // the same Team as the installed copy, so the swap passes the
        // VendorInstaller gate (checked 2026-09-06; History has the version).
        //
        // Notes: the release bodies are full Markdown (v1.4.0's runs to several
        // hundred words of per-area headings and bullets), so `GitHubMarkdownParser`
        // renders them natively and no `ChangelogRecipe` is needed.
        GitHubReleaseRule(
            bundleID: "uk.whatcable.whatcable",
            owner: "darrylmorley", repo: "whatcable",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^WhatCable\.zip$"#,
            installerKind: .zip),

        // WhatCable beta — the same repo's prerelease train, and it MUST exist
        // rather than being left to the stable rule. The betas ship a version
        // string the bundle keeps verbatim (`CFBundleShortVersionString` reads
        // "1.5.0-beta.8", confirmed on the real v1.5.0-beta.8 artifact), which
        // `ReleaseChannel.detect` step 4 resolves to `.beta` — so a beta install
        // is refused by the stable rule's channel gate and, without this, would
        // have no source at all and read "Failed" indefinitely. That is not
        // hypothetical: it is the exact shape of the Alfred regression documented
        // on its `.beta` recipe in `Recipes/com-runningwithcrayons-Alfred.swift`.
        //
        // The vendor's own updater has the matching opt-in — `receiveBetaUpdates`
        // in `uk.whatcable.whatcable`'s defaults, whose comment in the app's
        // `AppSettings.swift` says an opted-out user "keeps hitting
        // releases/latest, which GitHub never returns a pre-release from". That
        // toggle is NOT read here, and the gap is one-directional and known: a
        // copy running a STABLE build with the toggle on is offered stable by us
        // and betas by the app itself. Closing it needs a `ChannelBinding`, which
        // is tracked in CHANNEL_COVERAGE_TODO rather than smuggled in here. The
        // direction that would be harmful — pushing a beta at someone who never
        // asked for one — cannot happen: the beta rule only applies to a copy
        // already running a beta.
        //
        // **The pattern accepts stable tags too, and that is the design.** The
        // vendor's updater says what this track means, in the same file: "the
        // updater still picks whichever release is newest, so a stable always
        // supersedes its own betas." Two things follow, and both were nearly got
        // wrong by anchoring the pattern to `-beta\.`:
        //
        //   • A copy on `1.5.0-beta.8` would never be offered the plain `1.5.0`
        //     that graduates from it — it would sit on a superseded prerelease
        //     until the next cycle opened. `VersionComparator` ranks the
        //     graduation correctly (a missing 4th component pads to `.number(0)`
        //     and beats `.text("beta")`), so the only thing standing in the way
        //     was the pattern.
        //   • Worse, it is a fuse. If this vendor pauses the beta train, a
        //     `-beta\.`-only pattern matches nothing in the page, and the miss is
        //     a red `duo verify` finding on EVERY machine — the sweep walks rules,
        //     not installs — for a rule that is working exactly as written. Not a
        //     remote prospect: the beta train did not exist at all until
        //     `v1.2.0-beta.1`, more than a hundred releases into this repo's
        //     history (History has the count).
        //
        // ⚠️ And the cost, which is real and one-way: taking that graduation puts
        // the copy on `1.5.0`, `ReleaseChannel.detect` then reads it as `.stable`,
        // and from the next check on it is served by the stable rule — so WE never
        // offer it a beta again. Neither rule sets `installedTagPrefix`, so the
        // discovery path that remembers a channel across an install is unreachable
        // here. The vendor's own updater, which reads the toggle we do not, keeps
        // offering betas to such a copy and would move it back. That asymmetry is
        // the same one-cell gap as above, reached from the other side, and it is
        // what the `ChannelBinding` in CHANNEL_COVERAGE_TODO would close.
        //
        // Accepting stable here means a beta install can legitimately be handed a
        // release GitHub marks stable — the same thing UTM's `.beta` rule does,
        // for the same reason (a preview that graduates into the shared
        // numbering, not a parallel train). It also means the channel proof
        // cannot be an `.artifact` one: the tag segment is the only place either
        // train names itself, so an artifact proof would fire on that legitimate
        // resolution. The registered proof is a `.recipeAnchor` on
        // `usePrereleases` instead — see `ChannelProofRegistry.githubProofs`.
        // (UTM's third option, `candidateScope: .installedMajorLineOrNewestStable`
        // plus `installedTagPrefix`, was considered and not taken: its ceiling is
        // about keeping a preview inside its own MAJOR line, which is a question
        // WhatCable does not have — one line, and its betas are its next release,
        // not a parallel v-next.)
        //
        // listPageSize: every release checked has a tag this pattern matches and
        // carries `WhatCable.zip` (2026-09-06 and 2026-09-14; History has the
        // counts and the page sizes), so first-match index is 0 and the gap is 0.
        // The floor is 1; 5 is kept for headroom against a draft or a
        // platform-partial release. `probesNewestFirst` means the common round is
        // a page of one anyway.
        GitHubReleaseRule(
            bundleID: "uk.whatcable.whatcable",
            owner: "darrylmorley", repo: "whatcable",
            usePrereleases: true,
            listPageSize: 5,
            versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$"#,
            installAssetPattern: #"^WhatCable\.zip$"#,
            installerKind: .zip,
            channel: .beta),
        ],
        githubChannelProofs: [
        // WhatCable beta — an anchor rather than an artifact, and the reason is
        // that its rule deliberately accepts stable tags as well as `-beta.<N>`
        // ones (see the rule's own comment: the vendor's updater graduates a beta
        // onto the stable release, and a `-beta.`-only pattern is also a fuse the
        // day the beta train pauses). The tag segment of the download path is the
        // only place either train names itself — both publish one asset called
        // `WhatCable.zip` — so an `.artifact` proof would be RIGHT about the
        // evidence and WRONG about the rule: it would fire on a resolution that is
        // exactly what this track is for.
        //
        // TWO fields, and the alternation is why: this rule's channel identity is
        // split across them, and each has to keep its own half. `usePrereleases`
        // is what makes it read the releases list instead of `/releases/latest`,
        // which GitHub computes with prereleases excluded; `versionPattern` is
        // what makes it ACCEPT a prerelease once fetched. Break either and the
        // beta rule silently becomes a second stable rule — no error, no missing
        // version, just a beta install that stops being offered betas. The pattern
        // matches each field through its own branch (`^true$` the Bool,
        // `-beta\\\.` the REGEX SOURCE — the extra escaping is there because the
        // text being matched is itself a regex, so the backslash in `-beta\\.` has
        // to be matched literally; the t3code anchor (`Recipes/com-t3tools-t3code.swift`) does the same thing to
        // that pattern's brackets); neither branch can satisfy the other field.
        //
        // A first draft anchored `usePrereleases` alone and claimed it was "the
        // whole of this rule's channel identity". It is not, in two ways:
        // `versionPattern` is the other half, and `usePrereleases: true` is not
        // even a beta-only property — three STABLE rules in this registry set it
        // (`com.insomnia.app`, `com.bitwarden.desktop`, `com.microsoft.Headlamp`),
        // so on its own it says nothing about which train this rule is on.
        //
        // Be honest about the reach, as UTM's anchor (`Recipes/com-utmapp-UTM.swift`) is: this cannot see a
        // vendor who launches an identically-named third train, and it says
        // nothing about which release was chosen — the `.recipeAnchor` branch of
        // `crossChannelArtifact` never looks at the resolved artifact. It is a
        // claim about the request, which is the same kind the `bindingProofs`
        // make, and it fails only when somebody edits one of the two fields.
        ChannelProofKey("uk.whatcable.whatcable", .beta):
            .recipeAnchor(#"^true$|-beta\\\."#, in: ["usePrereleases", "versionPattern"]),
        ])
}
