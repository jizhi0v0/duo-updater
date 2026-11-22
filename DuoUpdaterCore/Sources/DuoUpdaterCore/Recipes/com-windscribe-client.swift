import Foundation

enum com_windscribe_client {
    static let set = AppRecipeSet(
        family: "com-windscribe-client",
        // History: docs/app-audits/com-windscribe-client.md#历史与实测
        // The macOS feed states track, version, DMG and digest in one entry.
        // Track preferences form a ladder: accept the newest eligible entry from
        // the selected track and all more stable tracks. The installer owns the
        // privileged helper update, so each DMG is an interactive handoff.
        probes: [ReleaseChannel.stable, .beta, .guineaPig].compactMap(windscribeTrackRecipe),
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
        // this vendor publishes: the versions the vendor's own API names on its
        // release track are `prerelease: false` on GitHub, and the ones it names on
        // the beta / guinea-pig tracks are not (checked 2026-09-07 across every
        // release since 2024; History has the counts) — so nothing from a track the
        // user did not opt into can reach the panel.
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
        // ⚠️ WHAT THIS LISTS THAT IT SHOULD NOT: GitHub marks every prerelease the
        // same way, beta and guinea pig alike — it has no idea which track a build
        // is on (checked 2026-09-07 on the newest 40 releases; History has the
        // counts). So a beta reader sees guinea pig entries too, and both readers
        // see builds the vendor never announced.
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
        //
        // Those never-announced builds are why `carriesOtherTrainEntries` is set
        // (#790/#791): on 2026-09-23 GitHub's newest was `v2.25.1-alpha` while
        // every vendor endpoint (`ChangeLogs?platform=osx`, `ChangeLogs/summary`,
        // `CheckUpdate?beta=0…3`, 10 requests each) still answered 2.24.12, and of
        // the 29 releases just below it 13 never reached any vendor track. The top
        // entry here cannot stand in for what a track is being offered.
        ] + [ReleaseChannel.beta, .guineaPig].map { channel in
            ChangelogRecipe(
                bundleID: "com.windscribe.client",
                source: URL(string: windscribeReleases)!,
                mode: .json,
                maxEntries: 20,
                channel: channel,
                includesPromotedStable: true,
                carriesOtherTrainEntries: true,
                structuredFormat: .gitHubReleases)
        },
        channelProofs: [
            ChannelProofKey("com.windscribe.client", .beta):
                .artifact(#"/Windscribe_[0-9.]+_(?:beta_)?universal[.]dmg$"#),
            ChannelProofKey("com.windscribe.client", .guineaPig):
                .artifact(#"/Windscribe_[0-9.]+_(?:beta_|guinea_pig_)?universal[.]dmg$"#),
        ])

    private static func windscribeTrackRecipe(_ channel: ReleaseChannel) -> VendorProbeRecipe? {
        guard let tracks = VendorProbeRegistry.windscribeTrackSet(channel) else { return nil }
        let suffix = switch channel {
        case .stable: "universal"
        case .beta: "(?:beta_)?universal"
        default: "(?:beta_|guinea_pig_)?universal"
        }
        // JSON may escape the path separators. Pin both copies of the version
        // in the vendor path and read the digest from the same entry.
        let urlPrefix = #"https:\x5c?/\x5c?/deploy\.totallyacdn\.com\x5c?/desktop-apps\x5c?/"#
        let version = #"[0-9]+(?:\.[0-9]+)+"#
        let filePrefix = #"\x5c?/Windscribe_"#
        let entry = #""platform"\s*:\s*"osx"[\s\S]*?"beta"\s*:\s*\#(tracks)(?![0-9])[\s\S]*?"#
        let urlKey = #""url"\s*:\s*""#
        let versionPattern = entry + urlKey + urlPrefix + "(" + version + ")" + filePrefix
            + #"\1_\#(suffix)\.dmg""#
        let downloadPattern = urlKey + "(" + urlPrefix + version + filePrefix
            + version + #"_\#(suffix)\.dmg)""#
        let install = VendorInstallSpec(
            urlSource: .bodyPattern(downloadPattern), kind: .dmg,
            checksumPattern: #""sha256"\s*:\s*"([a-fA-F0-9]{64})""#,
            checksumFormat: .sha256Hex,
            installerApp: VendorInstallerApp(
                bundleIdentifier: "com.windscribe.installer.macos",
                teamIdentifier: "GYZJYS7XUG",
                installedPath: "/Applications/Windscribe.app"))
        return VendorProbeRecipe(
            bundleID: "com.windscribe.client",
            url: URL(string: "https://api.windscribe.com/ChangeLogs?platform=osx")!,
            mode: .responseBody,
            versionPattern: versionPattern,
            downloadURL: URL(string: "https://windscribe.com/download"),
            changelogURL: URL(string: "https://windscribe.com/changelog"),
            selectHighest: true,
            publishedAtPattern: #""release_date"\s*:\s*"([0-9]{4}-[0-9]{2}-[0-9]{2})""#,
            minimumSystemVersionPattern: #""min_version"\s*:\s*"([0-9.]+)""#,
            entryStartPattern: #""id"\s*:\s*[0-9]+"#,
            install: install,
            requestHeaders: ["Authorization": "Bearer 1234"],
            channel: channel)
    }

    /// Declared once because the three Windscribe recipes must never drift onto
    /// different pages of the same feed — `per_page` decides how far back every
    /// one of them can see.
    private static let windscribeReleases =
        "https://api.github.com/repos/Windscribe/Desktop-App/releases?per_page=40"
}
