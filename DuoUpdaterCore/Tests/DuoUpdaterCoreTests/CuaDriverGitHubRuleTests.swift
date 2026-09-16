import Testing
import Foundation
@testable import DuoUpdaterCore

/// Cua Driver (`com.trycua.driver`) is served out of `trycua/cua`, a monorepo
/// where every release this rule wants is flagged `prerelease: true` by vendor
/// policy and the newest row is almost always some other product. Each of those
/// facts is one small edit away from silently reading a different train, so each
/// is pinned here against strings the vendor really published.
///
/// See `docs/app-audits/com-trycua-driver.md` for the measurements.
@Suite struct CuaDriverGitHubRuleTests {

    /// EVERY rule this bundle id carries, not the first. Nightly is a real
    /// channel this vendor already publishes (the installer persists a
    /// stable/nightly preference in `~/.cua-driver/release-channel`), so a
    /// second rule here is a plausible future, and a guard reading `.first`
    /// would inspect one rule and vouch for two — the finding that came out of
    /// #680's review.
    ///
    /// Non-empty is required rather than assumed: a lookup that stops finding
    /// anything has to fail loudly instead of leaving this suite green while it
    /// exercises nothing.
    private static var rules: [GitHubReleaseRule] {
        get throws {
            let found = GitHubReleaseRegistry.rules.filter { $0.bundleID == "com.trycua.driver" }
            try #require(!found.isEmpty, "com.trycua.driver is no longer in GitHubReleaseRegistry")
            return found
        }
    }

    private static var stableRule: GitHubReleaseRule {
        get throws {
            try #require(
                self.rules.first { $0.channel == .stable },
                "com.trycua.driver has no stable rule any more")
        }
    }

    /// Tags this repository really published, one per train, and what the stable
    /// rule must read out of each. `extractVersion` is the same call
    /// `GitHubReleasesSource` makes on every release it walks.
    ///
    /// The nightly row is the one that matters. `NSRegularExpression` matches
    /// anywhere, and a nightly tag CONTAINS a well-formed stable tag, so an
    /// unanchored pattern reads `0.28.3` out of it — a stable release that does
    /// not exist — and would do so again every night.
    @Test(arguments: [
        ("cua-driver-rs-v0.28.2", "0.28.2"),
        ("cua-driver-rs-v0.19.3", "0.19.3"),
        // The nightly train, whose tag embeds the stable shape.
        ("nightly-cua-driver-rs-v0.28.3-nightly.20260916.35055871159", nil),
        // The retired Swift driver, still on this repo under its own prefix.
        ("cua-driver-v0.2.0", nil),
        // Other products in the same monorepo.
        ("sandbox-v0.8.0", nil),
        ("lume-v0.5.3", nil),
        ("computer-server-v0.3.46", nil),
        ("fleet-v0.1.17", nil),
    ])
    func realTagsFromThisMonorepoResolveOnlyWhenTheyAreTheDriver(
        tag: String, expected: String?
    ) throws {
        let rule = try Self.stableRule
        #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern)
                == expected)
    }

    /// The mutation the anchors exist for, spelled out: drop them and the
    /// nightly tag starts answering as a stable version. Both halves are
    /// asserted so the test states the hazard, not just the fix.
    @Test func anUnanchoredPatternWouldReadTheNightlyTagAsStable() throws {
        let nightly = "nightly-cua-driver-rs-v0.28.3-nightly.20260916.35055871159"
        #expect(VendorProbeRecipe.extractVersion(
            from: nightly, pattern: try Self.stableRule.versionPattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(
            from: nightly, pattern: #"cua-driver-rs-v([0-9]+\.[0-9]+\.[0-9]+)"#) == "0.28.3")
    }

    /// This vendor flags its stable releases as GitHub prereleases on purpose,
    /// so `/releases/latest` — which GitHub computes with prereleases excluded —
    /// answers with whichever other product in the monorepo shipped a
    /// non-prerelease last (`sandbox-v0.8.0` on 2026-09-16). A rule that read
    /// that endpoint would not be stale, it would be reading another product.
    ///
    /// `probesNewestFirst` is the same fact from the other side: stable driver
    /// tags are 88 of this repo's 683 published releases, so a one-row probe
    /// would fall through to the full page nearly every round and only add a
    /// request.
    @Test func theRuleReadsTheListEndpointAndDoesNotProbeTheNewestRow() throws {
        let rule = try Self.stableRule
        #expect(rule.usePrereleases,
                "/releases/latest excludes prereleases, and every cua-driver-rs release is flagged as one")
        #expect(!rule.probesNewestFirst,
                "the newest row in this monorepo is almost never a stable driver tag")
    }

    /// The macOS install target. Two things must hold at once and a single
    /// character decides both: the pattern has to take the tarball that carries
    /// `CuaDriver.app`, and it has to refuse the `-binary` sibling, which ships
    /// the bare executables with no bundle in it at all — `ArchiveExtractor`
    /// would fail with `noAppFound` on that one.
    ///
    /// The list is the real asset listing of `cua-driver-rs-v0.28.2`.
    @Test func theInstallPatternTakesTheBundleTarballAndNotTheBareBinaries() throws {
        let assets = [
            "checksums.txt",
            "cua-driver-rs-0.28.2-darwin-arm64.tar.gz",
            "cua-driver-rs-0.28.2-darwin-universal-binary.tar.gz",
            "cua-driver-rs-0.28.2-darwin-universal.tar.gz",
            "cua-driver-rs-0.28.2-darwin-x86_64.tar.gz",
            "cua-driver-rs-0.28.2-linux-arm64.tar.gz",
            "cua-driver-rs-0.28.2-windows-x86_64.zip",
            "cua_driver-0.28.2-py3-none-macosx_13_0_universal2.whl",
            "trycua-cua-driver-darwin-arm64-0.28.2.tgz",
            "install.sh", "uninstall.sh", "release-manifest.json",
        ]
        let rule = try Self.stableRule
        let pattern = try #require(rule.installAssetPattern)
        let matched = assets.filter {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matched == ["cua-driver-rs-0.28.2-darwin-universal.tar.gz"],
                "exactly the tarball the vendor's own installer fetches on macOS")
        #expect(rule.installerKind == .tarGz)
    }

    /// The pattern must not start matching a different platform's archive if the
    /// vendor renames things — `darwin` is in it, and these are the names that
    /// would be there to confuse it.
    @Test func theInstallPatternIgnoresTheOtherPlatforms() throws {
        let pattern = try #require(try Self.stableRule.installAssetPattern)
        for name in [
            "cua-driver-rs-0.28.2-linux-x86_64.tar.gz",
            "cua-driver-rs-0.28.2-linux-arm64-binary.tar.gz",
            "cua-driver-rs-0.28.2-darwin-universal-binary.tar.gz",
            "cua-hyprland-plugin-0.28.2-fc188250b4ca8549b8e61f937fdb1fb560770e86.tar.gz",
            "cua-driver-rs-v0.28.2-skills.tar.gz",
        ] {
            #expect(name.range(of: pattern, options: .regularExpression) == nil,
                    "\(name) must not be offered as the macOS install")
        }
    }

    private static var nightlyRule: GitHubReleaseRule {
        get throws {
            try #require(
                self.rules.first { $0.channel == .nightly },
                "com.trycua.driver has no nightly rule any more")
        }
    }

    /// The hazard of having two rules on one bundle id in one repo: each is the
    /// obvious place to copy the other from, and a pattern that drifted wide
    /// enough to accept the other train would be invisible — same vendor, same
    /// Team ID, same notarization, past every gate we have. So all four
    /// directions are pinned, with the real strings from both trains.
    ///
    /// The stable→nightly direction is the one that already nearly happens for
    /// free: a nightly TAG contains a well-formed stable tag, so only the `$`
    /// anchor separates them. The nightly→stable direction is the reverse and is
    /// structural (a stable tag has no `-nightly.` segment at all), but it is
    /// pinned anyway, because "structural today" is what a loosened pattern
    /// stops being.
    @Test func theTwoTrainsNeverMatchEachOthersTagsOrAssets() throws {
        let stable = try Self.stableRule
        let nightly = try Self.nightlyRule

        let stableTag = "cua-driver-rs-v0.28.2"
        let nightlyTag = "nightly-cua-driver-rs-v0.28.3-nightly.20260916.35055871159"
        let stableAsset = "cua-driver-rs-0.28.2-darwin-universal.tar.gz"
        let nightlyAsset =
            "cua-driver-rs-0.28.3-nightly.20260916.35055871159-darwin-universal.tar.gz"

        // Tags: each rule reads its own and refuses the other's.
        #expect(VendorProbeRecipe.extractVersion(from: stableTag, pattern: stable.versionPattern)
                == "0.28.2")
        #expect(VendorProbeRecipe.extractVersion(from: nightlyTag, pattern: stable.versionPattern)
                == nil)
        #expect(VendorProbeRecipe.extractVersion(from: nightlyTag, pattern: nightly.versionPattern)
                == "0.28.3")
        #expect(VendorProbeRecipe.extractVersion(from: stableTag, pattern: nightly.versionPattern)
                == nil)

        // Assets: same, for the thing that actually gets downloaded.
        func matches(_ name: String, _ pattern: String?) -> Bool {
            guard let pattern else { return false }
            return name.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matches(stableAsset, stable.installAssetPattern))
        #expect(!matches(nightlyAsset, stable.installAssetPattern))
        #expect(matches(nightlyAsset, nightly.installAssetPattern))
        #expect(!matches(stableAsset, nightly.installAssetPattern))
    }

    /// The nightly rule captures the BASE version, not the full nightly string,
    /// and that is forced rather than chosen: the installed bundle reports the
    /// bare base (`0.28.3`), so a captured `0.28.3-nightly.20260916.…` would be a
    /// prerelease-shaped string against a plain release-shaped one — which
    /// compares as OLDER, and would mean a nightly copy is never offered anything.
    ///
    /// The cost of the base capture is pinned here too, as the thing it is: two
    /// different nightlies of one base resolve to the same version, so only a base
    /// bump can produce an offer.
    @Test func theNightlyRuleCapturesTheBaseVersionSoItCanBeComparedAtAll() throws {
        let nightly = try Self.nightlyRule
        let sameBase = [
            "nightly-cua-driver-rs-v0.28.2-nightly.20260914.34806428689",
            "nightly-cua-driver-rs-v0.28.2-nightly.20260915.34929088253",
        ].map { VendorProbeRecipe.extractVersion(from: $0, pattern: nightly.versionPattern) }

        #expect(sameBase == ["0.28.2", "0.28.2"])
        // The comparison that forced the base capture, stated as an assertion
        // rather than as a claim in a comment.
        #expect(!VersionComparator.isNewer("0.28.3-nightly.20260916.35055871159", than: "0.28.3"))
    }

    /// The nightly rule hands out an artifact on a channel it chose from a
    /// preference file, so `ChannelProofRegistry` requires it to state how the
    /// artifact is known to be nightly. Both real URLs are run through the
    /// registered proof: the nightly one passes, the stable one is caught.
    @Test func theNightlyArtifactIsProvenToBeOnTheNightlyTrack() throws {
        let nightly = try Self.nightlyRule
        try #require(ChannelProofRegistry.githubProofs[
            ChannelProofKey("com.trycua.driver", .nightly)] != nil)

        func remote(_ url: String) -> RemoteVersion {
            RemoteVersion(
                shortVersion: "0.28.3", version: "0.28.3",
                downloadURL: URL(string: url)!, sourceName: "GitHub",
                vendorInstallerKind: .tarGz)
        }
        let base = "https://github.com/trycua/cua/releases/download/"
        #expect(RecipeSanity.crossChannelArtifact(rule: nightly, remote: remote(
            base + "nightly-cua-driver-rs-v0.28.3-nightly.20260916.35055871159/"
                 + "cua-driver-rs-0.28.3-nightly.20260916.35055871159-darwin-universal.tar.gz"))
            == nil)
        // The failure it exists for: the stable train's artifact reaching a
        // nightly install. Same vendor, same Team ID, same notarization.
        #expect(RecipeSanity.crossChannelArtifact(rule: nightly, remote: remote(
            base + "cua-driver-rs-v0.28.2/cua-driver-rs-0.28.2-darwin-universal.tar.gz"))
            != nil)
    }

    /// What the changelog pane gets, and — more to the point — what it does not.
    ///
    /// Every one of this vendor's release bodies repeats the same boilerplate:
    /// a one-line install snippet, an explanation of why GitHub labels the
    /// release a prerelease, and a fenced block of ~20 SHA256 checksums. None of
    /// it reaches the pane, because `GitHubMarkdownParser`'s strict pass takes
    /// only top-level bullets and `qualifyingHeadings` drops a heading with a
    /// digit in it (`SHA256 Checksums`) and the `full changelog` /
    /// `contributors` boilerplate keywords. That is why this family needs no
    /// `ChangelogRecipe` and no `skipSections` — it is measured, not assumed.
    ///
    /// Verbatim `cua-driver-rs-v0.28.2` body, fetched 2026-09-16, trimmed only
    /// by shortening the checksum block (it is 21 lines upstream; keeping three
    /// exercises the same fence).
    @Test func theRealReleaseBodyYieldsTheFixesAndNoneOfTheBoilerplate() {
        let body = """
            # Cua Driver 0.28.2

            ## Summary

            This release includes 4 fixes.

            ## Fixes

            - preserve semantic Hyprland AX scrolling. ([#3820](https://github.com/trycua/cua/pull/3820))
            - unify desktop snapshot identity and payload ownership. ([#3616](https://github.com/trycua/cua/pull/3616))
            - capture macOS desktops without relying on PATH. ([#3755](https://github.com/trycua/cua/pull/3755))
            - route background text through Hyprland input. ([#3877](https://github.com/trycua/cua/pull/3877))

            ## Contributors

            This release contains maintainer changes only.

            ## Install

            macOS and Linux:

            ```bash
            /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)"
            ```

            ## Why GitHub says “Pre-release”

            GitHub's label is used only to keep this monorepo's repository-wide “Latest”
            pointer from switching between independently released products. A plain Cua
            Driver SemVer is a stable release.

            ## SHA256 Checksums

            ```text
            818ddefa0fa8ba2ec9cba837c7aa634a4b064221c748752cf49c5b08e2c94e8c  cua-driver-rs-0.28.2-darwin-arm64.tar.gz
            e273181b26709c88b1d809474deb3c592b4efae3530b11d76318f1887fc3fbb1  cua-driver-rs-0.28.2-darwin-universal.tar.gz
            317ba3a49fdba10f2a7f1b9f392c1bc1b7657f3aae85e1e2e43684cf17a1bf3b  install.sh
            ```

            ## Full changelog

            [cua-driver-rs-v0.28.1...cua-driver-rs-v0.28.2](https://github.com/trycua/cua/compare/cua-driver-rs-v0.28.1...cua-driver-rs-v0.28.2)
            """

        let parsed = GitHubMarkdownParser.parse(body: body, version: "0.28.2", date: "2026-09-15")
        let entry = try? #require(parsed?.entries.first)
        guard let entry else { return }

        #expect(entry.items == [
            "preserve semantic Hyprland AX scrolling. ([#3820](https://github.com/trycua/cua/pull/3820))",
            "unify desktop snapshot identity and payload ownership. ([#3616](https://github.com/trycua/cua/pull/3616))",
            "capture macOS desktops without relying on PATH. ([#3755](https://github.com/trycua/cua/pull/3755))",
            "route background text through Hyprland input. ([#3877](https://github.com/trycua/cua/pull/3877))",
        ])
        #expect(entry.content.first == .heading("Fixes"))

        // The boilerplate, named rather than counted: a change to the parser that
        // let any of it through would still leave the item list above correct.
        let rendered = entry.items.joined(separator: "\n") + "\n"
            + entry.content.map { String(describing: $0) }.joined(separator: "\n")
        for leak in ["install.sh", "818ddefa", "Pre-release", "Checksums", "compare/"] {
            #expect(!rendered.contains(leak),
                    "release-body boilerplate reached the changelog pane: \(leak)")
        }
    }
}
