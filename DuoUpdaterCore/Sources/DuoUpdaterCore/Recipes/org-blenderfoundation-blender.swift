import Foundation

enum org_blenderfoundation_blender {
    static let set = AppRecipeSet(
        family: "org-blenderfoundation-blender",
        probes: [
        // History: docs/app-audits/org-blenderfoundation-blender.md#历史与实测
        // Blender — no updater in the bundle (no `SUFeedURL`, no Sparkle), so a
        // direct-download copy has no source until this one. The version is read
        // off www.blender.org/download/, the vendor's own "current release" page:
        // its macOS button links to
        // `/download/release/Blender<major.minor>/blender-<version>-macos-arm64.dmg/`
        // and it is the only macOS link on the page. That version string is the
        // bundle's `CFBundleShortVersionString` (and `CFBundleVersion`, identical),
        // so no `versionIsBuild`. The page names a GA build anyone can download by
        // hand, not a staged rollout.
        //
        // Apple silicon only: since 5.0 Blender builds no Intel dmg (the 5.x
        // release directories hold `-macos-arm64.dmg` alone), and the page links
        // nothing for Intel. Intel copies are capped at the 4.5 LTS line, which
        // this recipe does not cover.
        //
        // Every stable line shares the bundle id: a 4.5 LTS copy is offered the
        // current release here, the same as Homebrew's `blender` cask does, and the
        // major-version gate marks a 4 → 5 jump. Alpha, beta and release-candidate
        // builds share it too, but never reach this recipe: their cycle is read out
        // of the executable (`BlenderBuildInfo`) and they follow the builder tracks
        // below.
        //
        // Homebrew notes the page sits behind Cloudflare and its livecheck reads
        // download.blender.org/release/ instead; that listing is two levels deep
        // (one directory per minor), which a single-URL probe cannot follow.
        //
        // One-click: the page's link is a thank-you page, not the file. The dmg
        // lives at download.blender.org/release/Blender<major.minor>/, rebuilt
        // from the same anchor's two captures. Blender.app is self-contained (no
        // helpers or launch items outside the bundle), so `.dmg` is right. Team
        // 68UA947AUU (Stichting Blender Foundation).
        VendorProbeRecipe(
            bundleID: "org.blenderfoundation.blender",
            url: URL(string: "https://www.blender.org/download/")!,
            mode: .responseBody,
            versionPattern:
                #"href="https://www\.blender\.org/download/release/Blender[0-9]+\.[0-9]+/blender-([0-9]+\.[0-9]+\.[0-9]+)-macos-arm64\.dmg/""#,
            downloadURL: URL(string: "https://www.blender.org/download/"),
            changelogURL: URL(string: "https://developer.blender.org/docs/release_notes/"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.blender.org/release/Blender{0}/blender-{1}-macos-arm64.dmg",
                    fields: [
                        #"href="https://www\.blender\.org/download/release/Blender([0-9]+\.[0-9]+)/blender-[0-9]+\.[0-9]+\.[0-9]+-macos-arm64\.dmg/""#,
                        #"href="https://www\.blender\.org/download/release/Blender[0-9]+\.[0-9]+/blender-([0-9]+\.[0-9]+\.[0-9]+)-macos-arm64\.dmg/""#,
                    ]),
                kind: .dmg),
            hostRequirement: VendorHostRequirement(architectures: [.arm64])),
        // Alpha, beta and release candidate — the builds builder.blender.org
        // publishes every day. Its JSON listing names the newest build of each
        // branch per platform, and nothing older (that lives in a ~100-day archive
        // that is not in date order). So each track reads its entry's commit
        // (`headBuildPattern`) and compares by `BuildLineage.head`: the installed
        // commit (`BlenderBuildInfo.trackCommit`) either is the head or is behind
        // it. The marketing version, still read by `versionPattern`, only picks
        // among entries — every 5.3 alpha says "5.3.0", so it cannot order builds.
        //
        // Tracks, by the listing's `risk_id`: `alpha` on `main`; `beta` and
        // `candidate` on the `vNN` release branches. Each reads only its own
        // builds: a beta copy is never handed the release that ends its beta (that
        // is the stable track, and crossing into it is the user's move, not ours).
        // `entryStartPattern` slices the listing into its objects and the entry
        // with the highest marketing version wins (`highestVersionEntry`): the RC
        // track can list several lines at once (4.5 LTS and 5.2 candidates
        // overlapped in the archive), and the listing keeps stale entries (a 2024
        // `4.2.0` alpha for Windows). `evaluate` still never offers a lower
        // marketing version than the installed one.
        //
        // Beta and RC exist only for weeks at a time; between them the listing
        // has no such entry, which `trackClosedPattern` says in the listing's own
        // terms: the alpha entry is present in the usual shape, the track's is not.
        // A listing whose shape changed matches neither, and fails loudly.
        //
        // One-click installs the listing's own dmg from cdn.builder.blender.org,
        // signed 68UA947AUU like the releases (checked on a 5.3.0 alpha, a 5.2.0
        // beta and a 5.2.1 RC). The published `.sha256` is hex, not the base64
        // SHA-512 `checksumPattern` verifies, so the signature gate is the check.
        builderTrack(.alpha, risk: "alpha", branch: "main"),
        builderTrack(.beta, risk: "beta", branch: "v[0-9]+"),
        builderTrack(.rc, risk: "candidate", branch: "v[0-9]+"),
        ],
        changelogs: [
        // History: docs/app-audits/org-blenderfoundation-blender.md#历史与实测
        // Blender — developer.blender.org/docs/release_notes/<major.minor>/ is the
        // clean per-version notes page (the blender.org/download marketing pages are
        // sprawling splash pages with no parseable block). One page per MINOR, with
        // its patch releases folded in, so the URL is templated on `{majorMinor}`:
        // the page always matches the target build, and nothing needs bumping when
        // Blender ships. `source` is only the fallback for a load with no version.
        //
        // Each page is an <h1> "Blender X.Y Release Notes" — "Blender X.Y LTS
        // Release Notes" on an LTS minor — then a <p>"Blender X.Y [LTS] was released
        // on DATE."</p>, then module-section <ul>s and Compatibility/Bugfixes lists.
        // We surface a COARSE summary (changed-module list + compat/bugfix bullets).
        // The body ends at the "Corrective Releases" <h2> where there is one, else at
        // </article>: LTS pages have no such heading (their fixes live on a separate
        // LTS page), and a lookahead that insisted on it matched nothing there.
        //
        // Requiring the literal "was released on" is a GUARD: daily/alpha/beta builds
        // share the bundle id, and an in-development minor's page reads "is currently
        // in Alpha/Beta" instead, so it yields zero entries (safe embed fallback)
        // rather than a partial changelog.
        ChangelogRecipe(
            bundleID: "org.blenderfoundation.blender",
            source: URL(string: "https://developer.blender.org/docs/release_notes/5.2/")!,
            entryPattern:
                #"<h1[^>]*>Blender\s+(?<version>\d+\.\d+(?:\.\d+)?)(?:\s+LTS)?\s+Release Notes.*?</h1>\s*"#
                + #"<p>Blender\s+[\d.]+(?:\s+LTS)?\s+was released on\s+(?<date>[^.<]+)\.</p>"#
                + #"(?<body>.*?)"#
                + #"(?=<h2[^>]*id="corrective-releases"|</article>)"#,
            itemPatterns: [#"<li>\s*(?<item>.*?)\s*</li>"#],
            maxEntries: 1,
            sourceTemplate: "https://developer.blender.org/docs/release_notes/{majorMinor}/"),
        ],
        channelProofs: [
        // The builder names each file after its track and branch:
        // `blender-5.3.0-alpha+main.<commit>-darwin.arm64-release.dmg`.
        ChannelProofKey("org.blenderfoundation.blender", .alpha):
            .artifact(#"/download/daily/blender-[0-9.]+-alpha\+main\.[0-9a-f]{12}-darwin\.arm64-release\.dmg$"#),
        ChannelProofKey("org.blenderfoundation.blender", .beta):
            .artifact(#"/download/daily/blender-[0-9.]+-beta\+v[0-9]+\.[0-9a-f]{12}-darwin\.arm64-release\.dmg$"#),
        ChannelProofKey("org.blenderfoundation.blender", .rc):
            .artifact(#"/download/daily/blender-[0-9.]+-candidate\+v[0-9]+\.[0-9a-f]{12}-darwin\.arm64-release\.dmg$"#),
        ])

    /// The one entry shape of builder.blender.org's daily listing, as the
    /// listing orders its fields, for one track. `branch` is a regex.
    static func builderEntry(risk: String, branch: String) -> String {
        #""version":\s*"([0-9]+\.[0-9]+\.[0-9]+)",\s*"risk_id":\s*""# + risk
            + #"",\s*"branch":\s*""# + branch
            + #"",[^{}]*?"platform":\s*"darwin",\s*"architecture":\s*"arm64",[^{}]*?"file_extension":\s*"dmg""#
    }

    static func builderTrack(_ channel: ReleaseChannel, risk: String, branch: String) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "org.blenderfoundation.blender",
            url: URL(string: "https://builder.blender.org/download/daily/?format=json&v=1")!,
            mode: .responseBody,
            versionPattern: builderEntry(risk: risk, branch: branch),
            // The listing keeps each branch's newest Mac dmg long after the branch
            // stops building (it still lists `v43`'s 4.3.2 dmg, uploaded
            // 2025-01-10), so `main`'s newest Mac alpha is always there: a listing
            // without it is not "between releases", it is a listing this recipe no
            // longer understands.
            trackClosedPattern: channel == .alpha ? nil
                : #"(?s)\A(?=.*"# + builderEntry(risk: "alpha", branch: "main")
                    + #")(?!.*"# + builderEntry(risk: risk, branch: branch) + #")"#,
            downloadURL: URL(string: "https://builder.blender.org/download/daily/"),
            changelogURL: URL(string: "https://developer.blender.org/docs/release_notes/"),
            buildNamespace: .vendor,
            publishedAtPattern: #""file_mtime":\s*([0-9]{10})\b"#,
            entryStartPattern: #"\{\s*"url""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url":\s*"(https://cdn\.builder\.blender\.org/download/daily/blender-[0-9]+\.[0-9]+\.[0-9]+-"#
                        + risk + #"\+"# + branch
                        + #"\.[0-9a-f]{12}-darwin\.arm64-release\.dmg)""#),
                kind: .dmg),
            channel: channel,
            hostRequirement: VendorHostRequirement(architectures: [.arm64]),
            headBuildPattern: #""hash":\s*"([0-9a-f]{12})""#)
    }
}
