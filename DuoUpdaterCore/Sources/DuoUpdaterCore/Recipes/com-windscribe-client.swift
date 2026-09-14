import Foundation

enum com_windscribe_client {
    static let set = AppRecipeSet(
        family: "com-windscribe-client",
        probes: [
        // MARK: - 2026-09-07 Windscribe

        // History: docs/app-audits/com-windscribe-client.md#历史与实测
        // Windscribe — VPN client (Qt, vendor's own updater; no Sparkle, no
        // electron-builder). `feed-discover` has nothing to find: the real bundle
        // (extracted from the 2.24.12 dmg, see History) declares no `SUFeedURL` and
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
        // snapshot-lint:allow — contract and measurement share one sentence, kept whole per README 「以句子为单位」
        //
        // WHY `/ChangeLogs/summary` AND NOT `/CheckUpdate`, which is the smaller
        // and more obvious endpoint. `CheckUpdate?platform=osx&beta=<n>` takes a
        // track number (0 release / 1 beta / 2 guinea pig, the same numbering as
        // the client's own `UPDATE_CHANNEL` enum) and answers with one artifact
        // URL to read the version off. The problem is that "the parameter
        // selects the release track" and "the parameter is ignored" cannot be
        // told apart from its answers while release leads: every value's correct
        // answer is then the same (History has the byte-identical responses).
        //
        // That ambiguity is not academic, and its risky branch is the NORMAL state
        // of this vendor: a prerelease outranks the newest release for most of
        // each cycle. If the parameter is ignored, then throughout those windows
        // `CheckUpdate` names a `…_beta_universal.dmg` and a recipe
        // reading that filename would report `versionPatternNoMatch` — the app
        // `.unknown` and `duo verify` BROKEN, for weeks at a time, four times a
        // day.
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
        // NO ONE-CLICK, and this is a structural refusal rather than a TODO.
        // An install is not a bundle swap here: it also writes
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
        // track is selected by key. The reverse is NOT prevented, by design: the
        // three tracks share `com.windscribe.client`, a display name and an
        // unsuffixed version string, so `detect()` has no signal, and
        // `WindscribeChannel` answers nil for the Release preference — the
        // default, which installing a beta dmg does not change. A prerelease
        // build on that preference is therefore compared against the release
        // track. That is accepted rather than overlooked: it is the vendor's own
        // ladder (a client on Release is served the release track), the version
        // only moves forward, and the install is manual — we hand the user the
        // vendor's download page. A copy on the Beta or Guinea Pig preference is
        // bound to its own track recipe below, when `WindscribeChannel` can read
        // that preference (see EXPECTED WARNING for when it cannot).
        //
        // The bundle's `CFBundleShortVersionString` == `CFBundleVersion` (the
        // plist template writes one value into both, so no `versionIsBuild`).
        //
        // EXPECTED WARNING, so nobody files an issue against a working recipe.
        // `duo verify` runs `RecipeSanity.remoteBehindInstalled` whenever it finds
        // an installed copy, and Windscribe's build numbers climb ACROSS tracks
        // inside a cycle (2.24.3/2.24.6 guinea pig → 2.24.8/2.24.10 beta →
        // 2.24.12 release). `duo verify` files an installed copy under the
        // channel the scan gave it (`Verify.installedVersions`), and
        // `AppScanner.readApp` applies `ChannelBinding` to every copy, so a copy
        // whose preference `WindscribeChannel` reads as Beta or Guinea Pig is
        // compared against its own track. Every other copy is filed under
        // stable unless an earlier check stored a proven channel for it
        // (`ResolvedChannelStore`): a prerelease build left on the Release
        // preference, and any copy whose preference could not be read (missing
        // or undecodable plist, or the resolver's time bound expiring). A
        // prerelease copy filed under stable is routinely newer
        // than the newest release-track build, and this recipe, which reads the
        // release track by design, then reads behind the installed copy and
        // draws a warning, four times a day for weeks. That is one of the honest
        // causes that check's own doc lists, not a fault here.
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

        // Windscribe beta / guinea pig — the two tracks `WindscribeChannel`
        // unlocks. Different endpoint from the stable recipe above, and the
        // reason is the shape of the answer rather than taste.
        //
        // A LADDER, NOT PARALLEL TRAINS. The vendor's own page says a fix "will
        // be released in the Guinea Pig channel first" and that staying on
        // Release is how you see fewest bugs; the feed shows the same thing, with
        // the build number climbing ACROSS tracks inside one cycle (2.24.3 and
        // 2.24.6 guinea pig → 2.24.8 and 2.24.10 beta → 2.24.12 release). So a
        // user on level N is served the newest build from tracks 0…N — reading
        // only their own track would tell someone on the beta line that the beta
        // track's 2.24.10 is the newest thing there is while release 2.24.12 sits
        // above it, and would offer a guinea pig user a version OLDER than the
        // one they are running.
        //
        // `/ChangeLogs/summary`, which the stable recipe reads, cannot express
        // that: its three `*_full_version` fields live in one object behind a
        // single `"platform": "osx"` anchor, and a pattern that consumes the
        // anchor matches exactly ONCE. Adding an alternation there looks like it
        // works — today it returns 2.24.12, the right answer — and would keep
        // returning the release track on the day a beta leads.
        //
        // `/ChangeLogs?platform=osx` states each release's track as its own
        // `"beta"` number (0 release / 1 beta / 2 guinea pig), so the track set
        // is a character class and `selectHighest` does the max across entries.
        // `entryStartPattern` is what keeps a version and its date inside ONE
        // entry; it also switches selection to "highest among matching entries",
        // which is the wanted behaviour here and why the single-match guard
        // being skipped under `selectHighest` is fine rather than a hole.
        //
        // Replaying the feed by date is what tells the three apart (stable,
        // beta and guinea pig give the same answer while release leads), and the
        // regression tests use those dates: on 2026-08-01 the three answer
        // 2.23.11 / 2.23.11 / 2.24.6, and on 2026-08-12 they answer 2.23.11 /
        // 2.24.8 / 2.24.8.
        //
        // Costs 250 KB per fetch against the stable recipe's 14 KB. An APP pays
        // one of the three — the channel gate binds exactly one recipe to a copy.
        // `duo verify` pays all three, because it walks the registry rather than
        // the installed apps. Worth stating both ways round; the first
        // sentence alone would let someone size the nightly job's cost and be
        // wrong by a wide margin.
        //
        // Detection only, exactly as stable is — the dmg is an installer stub and
        // the install writes a LaunchDaemon, a privileged helper and a system
        // extension. Because there is no install spec,
        // `RecipeSanity.crossChannelArtifact` returns early and no
        // `ChannelProofRegistry` entry is required; that is a consequence of the
        // refusal above, so anyone adding one-click here inherits the proof
        // obligation with it.
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
        // snapshot-lint:allow — catch-up batch after 2f
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
        // `includesPromotedStable` exists for; see CotEditor (`Recipes/com-coteditor-CotEditor.swift`).
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

        // The same feed for the two prerelease tracks, with
        // `includesPromotedStable` — which is the ladder, expressed in a field
        // that already existed. `decodeGitHubReleases` shows non-stable channels
        // the prereleases PLUS the releases that graduated, and "the newest build
        // from tracks 0…N" is exactly that: a beta copy is offered whichever of
        // the beta and release lines is newer, so the pane has to be able to hold
        // both or it omits the very entry the row offers.
        //
        // Without these two, `recipe(forBundleID:channel:)` walks past the exact
        // match it cannot find and lands on the `.stable` recipe above rather than
        // on nil, so a beta copy got a list filtered to release builds —
        // containing the offered version only while release leads, about a quarter
        // of each cycle.
        //
        // ⚠️ WHAT THIS LISTS THAT IT SHOULD NOT, measured on the newest 40
        // releases (2026-09-07): 9 are stable and 31 are prereleases, and GitHub
        // marks all 31 the same way — it has no idea which track a build is on.
        // So a beta reader sees guinea pig entries too, and both readers see
        // builds the vendor never announced.
        // snapshot-lint:allow — catch-up batch after 2f
        //
        // ⚠️ AND IT DOES NOT REMOVE THAT FAILURE ENTIRELY, only most of it. The
        // version comes from the vendor's feed and the notes come from GitHub,
        // and those two do not hold the same set of releases: of the 70 versions
        // the vendor has listed since 2024, three have no GitHub release at all
        // (2.21.1 guinea pig, 2.20.6 beta, 2.15.9 release). Each was the newest
        // on its track for a while, so in those windows the row offers a version
        // this pane cannot show — the same shape as before, at roughly 4% instead
        // of the ~75% it does fix. Worth knowing before reading an occasionally
        // empty-looking pane as a parser bug. The proper fix removes this too,
        // since the vendor's feed is by construction the set the probe reads.
        //
        // Shipped anyway because the failure it replaces is worse — a pane that
        // omits the release being offered three quarters of the time — and
        // because the precise fix is a different endpoint, not a better pattern:
        // the vendor's
        // `ChangeLogs?platform=osx` states each entry's track, but it 403s
        // without an `Authorization` header that `ChangelogRecipe` has no field
        // for, and its notes are markdown escaped inside a JSON string, which
        // wants its own `structuredFormat` rather than a regex. See the audit.
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
