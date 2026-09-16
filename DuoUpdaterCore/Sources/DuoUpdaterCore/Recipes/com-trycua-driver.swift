import Foundation

enum com_trycua_driver {
    static let set = AppRecipeSet(
        family: "com-trycua-driver",
        githubRules: [
        // History: docs/app-audits/com-trycua-driver.md#历史与实测
        //
        // Cua Driver — a computer-use daemon installed by `curl … | bash` from
        // cua.ai. On macOS the whole product IS the bundle: the installer copies
        // `CuaDriver.app` into `/Applications` and points `~/.local/bin/cua-driver`
        // at `Contents/MacOS/cua-driver` inside it (the versioned
        // `~/.cua-driver/packages/releases/` layout is Linux/Windows only — on this
        // platform that directory stays empty). No Sparkle feed, no Homebrew cask.
        //
        // **`usePrereleases` is not a preference here, it is the only way to read
        // this repo.** `trycua/cua` is a monorepo publishing at least eight trains
        // (driver, nightly driver, sandbox, fleet, npm-fleet, lume, computer-server,
        // hyprland kit), and the vendor flags EVERY `cua-driver-rs-v*` release as a
        // prerelease on purpose — its own release bodies say so under a "Why GitHub
        // says Pre-release" heading, and its installer says "Cua Driver's stable
        // tags are marked prerelease in GitHub metadata, so tag syntax — not the
        // prerelease flag — defines the channel". So `/releases/latest`, which
        // GitHub computes with prereleases excluded, answers with whichever OTHER
        // product in this repo shipped a non-prerelease last — History names the one
        // it landed on. A `usePrereleases: false` rule here would not be stale, it
        // would be reading a different product.
        //
        // **The anchors carry two loads, not one.** `^`/`$` here are what keep the
        // stable rule off the nightly train, and the reason is sharper than the
        // usual "a suffix might appear": a nightly tag literally CONTAINS a
        // well-formed stable tag. `NSRegularExpression` matches anywhere, so an
        // unanchored `cua-driver-rs-v([0-9]+\.[0-9]+\.[0-9]+)` run against
        // `nightly-cua-driver-rs-v<x.y.z>-nightly.<8 digits>.<run id>` matches the
        // `cua-driver-rs-v<x.y.z>` inside it and hands back a stable release that
        // does not exist yet — every single night. The `^` also keeps the retired
        // Swift driver's `cua-driver-v*` tags out; they are still on this repo. The
        // grammar is the vendor's own, copied from `_install-rust.sh`: stable is
        // exactly `x.y.z`, nightly is that plus the `-nightly.…` suffix.
        //
        // listPageSize: 25, against a floor of 19 registered in
        // `GitHubListPageSizeTests.measuredMinimumDepth` — History has the walk
        // (newest 100 releases, recomputed in Python rather than reread out of this
        // rule) and the worst gap it found. 25 carries margin over that floor the
        // way Bitwarden's 10 carries margin over its 8, and it is NOT free: this is
        // the most expensive GitHub rule in the registry, because a page of this
        // repo is mostly other products' release bodies (History has the wire
        // bytes at three page sizes). A stable train that went quiet for longer
        // than the page could hold would push the newest match off it, which
        // surfaces as a `recordMiss` and a row going `.unknown`, not as a confident
        // "up to date".
        //
        // probesNewestFirst is off for Bitwarden's reason, only with a wider
        // margin: stable driver tags are about an eighth of this repo's rows and
        // the nightly job cuts a release most mornings, so row 0 is almost never
        // the one this rule wants. Probing a page of one would buy a request that
        // fails over into the full page nearly every round. History has the share.
        //
        // ⚠️ **`.newest` is first-match-wins, and this repo's list order is not
        // strictly semver order.** Replaying every published release, GitHub
        // returns the stable driver tags out of order twice, both times across a
        // digit rollover published on one day (`v0.9.1` ahead of the newer
        // `v0.10.0`; `v0.2.9` ahead of `v0.2.18`). The order is not `created_at`,
        // `published_at` or `id` descending — all three disagree with it — which is
        // presumably why the vendor's own installer sorts the matches numerically
        // instead of taking the first. `settle()` has no such sort, so inside such
        // a window this rule offers the lower version until the next release ships.
        // Recorded rather than worked around: the failure is a temporarily stale
        // offer, never a wrong one, and `GitHubCandidateScope` has no
        // ordering-independent option that fits a vendor whose releases are all
        // flagged prerelease. History has both windows and how long they lasted.
        //
        // One-click: the asset is the same tarball the vendor's own installer
        // fetches on macOS, `…-darwin-universal.tar.gz`, and `CuaDriver.app` sits
        // one directory down inside it, which `ArchiveExtractor.firstApp` reaches
        // (it recurses exactly one level). The `-binary` sibling is deliberately
        // excluded by ending the pattern at `-darwin-universal.tar.gz` — that one
        // ships the bare executables with no `.app` at all, and `ArchiveExtractor`
        // would fail it as `noAppFound`. Every stable release carries exactly one
        // asset matching this pattern, so the pattern never has a choice to make
        // within a release and never triggers the walk-back in `settle()`. The
        // build is Developer ID (`Cua AI, Inc.`), notarized and stapled, and
        // `SignatureVerifier`'s Team-ID gate holds trivially because the installed
        // copy is the same vendor artifact. The swap also keeps the app's TCC
        // grants: Accessibility and Screen Recording are keyed to the designated
        // requirement (`com.trycua.driver` + that Team ID), which does not change,
        // and `~/.local/bin/cua-driver` keeps resolving because the path it points
        // at is unchanged. History has the packaged-bytes verification and the
        // end-to-end downgrade-and-reinstall run.
        GitHubReleaseRule(
            bundleID: "com.trycua.driver",
            owner: "trycua", repo: "cua",
            usePrereleases: true,
            listPageSize: 25,
            versionPattern: #"^cua-driver-rs-v([0-9]+\.[0-9]+\.[0-9]+)$"#,
            installAssetPattern:
                #"^cua-driver-rs-[0-9]+\.[0-9]+\.[0-9]+-darwin-universal\.tar\.gz$"#,
            installerKind: .tarGz,
            probesNewestFirst: false),

        // The nightly train, reachable only through `CuaDriverChannel` — read
        // that type first, because the reason this rule needs a binding at all is
        // the same reason it can only ever be approximate.
        //
        // **A nightly bundle does not say it is a nightly.** Its
        // `CFBundleShortVersionString` and `CFBundleVersion` are the bare base
        // version, identical to a stable release of that base AND to every other
        // nightly of that base (History has the three artifacts this was measured
        // on). So this pattern captures the BASE out of the nightly tag and
        // nothing else: capturing the full `x.y.z-nightly.<date>.<run>` would put
        // a prerelease-shaped string up against a plain `x.y.z` on disk, which
        // compares as OLDER and would offer nothing, ever.
        //
        // What that costs, stated rather than discovered later: consecutive
        // nightlies sharing a base are indistinguishable to us, so only a base
        // bump produces an offer — History has the share of nightly releases that
        // is. The alternative is executing the installed binary to read its real
        // version (`cua-driver --version` does know), and a scanner that runs
        // third-party executables to learn a version is not a trade this project
        // makes.
        //
        // Cheap where the stable rule is expensive, and for the mirror-image
        // reason: the nightly job cuts a release most mornings, so a matching tag
        // is usually row 0 — hence the small page and `probesNewestFirst` left at
        // its default. Floor measured the same way as stable's; see
        // `GitHubListPageSizeTests.measuredMinimumDepth`.
        //
        // One-click: same artifact shape, same `-binary` exclusion, and the
        // nightly build is signed and notarized exactly like stable (Developer ID
        // `Cua AI, Inc.`, ticket stapled, `--deep --strict` and `spctl` both
        // clean on the real bytes — History). The channel token is in the tag AND
        // in the asset filename, which is what lets `githubChannelProofs` below
        // carry an `.artifact` proof rather than a weaker recipe anchor.
        GitHubReleaseRule(
            bundleID: "com.trycua.driver",
            owner: "trycua", repo: "cua",
            usePrereleases: true,
            listPageSize: 12,
            versionPattern:
                #"^nightly-cua-driver-rs-v([0-9]+\.[0-9]+\.[0-9]+)-nightly\.[0-9]{8}\.[1-9][0-9]*$"#,
            installAssetPattern:
                #"^cua-driver-rs-[0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]{8}\.[1-9][0-9]*-darwin-universal\.tar\.gz$"#,
            installerKind: .tarGz,
            channel: .nightly),
        ],
        githubChannelProofs: [
        // Both halves of the resolved URL name the train, and either alone would
        // do: GitHub builds an asset URL as `…/releases/download/<tag>/<name>`, so
        // the tag is in the path (`/download/nightly-cua-driver-rs-v…/`) and the
        // filename carries `-nightly.<date>.<run>-` as well. Anchored on the path
        // because that is the half the `versionPattern` actually matched — this
        // proof then asserts the same thing the pattern does, but about what was
        // resolved rather than about what someone meant to write.
        ChannelProofKey("com.trycua.driver", .nightly):
            .artifact(#"/download/nightly-cua-driver-rs-v[0-9.]+-nightly\."#),
        ])
}
