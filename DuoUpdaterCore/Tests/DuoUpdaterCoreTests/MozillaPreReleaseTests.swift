import Testing
import Foundation
@testable import DuoUpdaterCore

/// Firefox and Thunderbird's pre-release channels, which are read from Mozilla's
/// own update service rather than from `product-details`.
///
/// **The defect this covers.** An installed Firefox beta reports
/// `CFBundleShortVersionString` = `155.0` for the entire cycle — the `b5` is
/// stripped on install — so `product-details`' `155.0b5` was measured against
/// `155.0`, and `VersionComparator` ranks a pre-release BELOW the release it
/// leads. `isNewer` was therefore false for every build of every cycle. Nightly
/// was worse: Mozilla ships one every day and they are all called `157.0a1`, so
/// a ~4-week cycle produced exactly zero update notices. Both are asserted
/// directly below (`theOldMarketingComparisonIsWhyThisExists`) so the reason
/// survives even if someone later "simplifies" these recipes back.
///
/// Every expectation is checked against the five response bodies captured
/// verbatim from the live endpoints on 2026-08-30, and against `BuildID`s read
/// out of the official dmgs on the same day. Recipes are looked up from the
/// registry, never restated.
struct MozillaPreReleaseTests {

    // MARK: - captured evidence

    /// `aus5.mozilla.org/update/6/Firefox/155.0/…/beta/…`, 2026-08-30.
    static let firefoxBetaBody = """
        <?xml version="1.0"?>
        <updates>
            <update appVersion="155.0" buildID="20260826090609" detailsURL="https://www.firefox.com/en-US/firefox/155.0/releasenotes/" displayVersion="155.0 Beta 5" type="minor">
                <patch type="complete" URL="https://download.mozilla.org/?product=firefox-155.0b5-complete&amp;os=osx&amp;lang=en-US" hashFunction="sha512" hashValue="ebb69f5345b9ed2bbe14172fe1a2b98103955198d88982c469c5b4f147a6cf995159a096fa3e1b16f80aef0ccd9d3a10a710560442beed432465ccf5acdcc7d3" size="143785819"/>
            </update>
        </updates>
        """

    /// Same endpoint on the `aurora` channel — Developer Edition. Same build,
    /// different artifact (`devedition-…` rather than `firefox-…`).
    static let firefoxDevBody = """
        <?xml version="1.0"?>
        <updates>
            <update appVersion="155.0" buildID="20260826090609" detailsURL="https://www.firefox.com/en-US/firefox/155.0/releasenotes/" displayVersion="155.0 Beta 5" type="minor">
                <patch type="complete" URL="https://download.mozilla.org/?product=devedition-155.0b5-complete&amp;os=osx&amp;lang=en-US" hashFunction="sha512" hashValue="6e261ccfcd39fb38cffbb0849557c2409cce74290c2e90de0447bd68e942d727b7240203519e3815af77336bfea9a134d28edfc1cea06f2f9b11f62246eaab8b" size="158714029"/>
            </update>
        </updates>
        """

    /// Nightly. Note the attributes are in a different order and there is no
    /// `detailsURL` — the patterns are attribute-keyed, not positional.
    static let firefoxNightlyBody = """
        <?xml version="1.0"?>
        <updates>
            <update type="minor" displayVersion="157.0a1" appVersion="157.0a1" platformVersion="157.0a1" buildID="20260829211045">
                <patch type="complete" URL="https://archive.mozilla.org/pub/firefox/nightly/2026/08/2026-08-29-21-10-45-mozilla-central/firefox-157.0a1.en-US.mac.complete.mar" hashFunction="sha512" hashValue="c2f108e0af5a980d895d7fbd7aeb9506ff6b23d76fc1f96d949b38b2914ecda11b1324a7013a89684bd0e7529ef05cd8b2969e59806726a72dc750b13fd80294" size="162697745"/>
            </update>
        </updates>
        """

    /// `aus.thunderbird.net`, which 302s to the same path on `aus5.mozilla.org`.
    static let thunderbirdBetaBody = """
        <?xml version="1.0"?>
        <updates>
            <update appVersion="155.0" buildID="20260826184332" detailsURL="https://live.thunderbird.net/thunderbird/releasenotes?locale=en-US&amp;version=155.0&amp;channel=beta" displayVersion="155.0 Beta 5" type="minor">
                <patch type="complete" URL="https://download.mozilla.org/?product=thunderbird-155.0b5-complete&amp;os=osx&amp;lang=en-US" hashFunction="sha512" hashValue="6f7aa72334166e8eddec2139477f89cd6fa85bd92a8dd986f26b493e36068128b261f4c3761ac81536c9c6fe536037ee9b2856f8a3be716a799f1d392ef5f727" size="144419454"/>
            </update>
        </updates>
        """

    static let thunderbirdDailyBody = """
        <?xml version="1.0"?>
        <updates>
            <update type="minor" displayVersion="157.0a1" appVersion="157.0a1" platformVersion="157.0a1" buildID="20260829100815">
                <patch type="complete" URL="https://archive.mozilla.org/pub/thunderbird/nightly/2026/08/2026-08-29-10-08-15-comm-central/thunderbird-157.0a1.en-US.mac.complete.mar" hashFunction="sha512" hashValue="77e1c0aea9e349bc4904f6550733921d6f2a7a1dd1900d1d1d4d053205e28519d8b1a7ff3d26ad3e645ad687c7fc309c92b4217030b910ca85b282f4567512f2" size="163177596"/>
            </update>
        </updates>
        """

    /// What AUS answers when the build you named is already the newest one. Only
    /// reachable with a per-machine anchor, which is exactly why these recipes
    /// use a frozen one — see `theAnchorIsFrozenSoAnEmptyAnswerIsAlwaysAFailure`.
    static let upToDateBody = """
        <?xml version="1.0"?>
        <updates></updates>
        """

    /// One case per pre-release channel: the recipe's (bundle id, channel), the
    /// body the live endpoint returned, and the `BuildID` / marketing string read
    /// out of that channel's official dmg on 2026-08-30.
    struct Case {
        let bundleID: String
        let channel: ReleaseChannel
        let body: String
        /// `application.ini` `BuildID` of the dmg the endpoint was pointing at.
        let installedBuildID: String
        /// `CFBundleShortVersionString` of that same bundle — frozen across the
        /// cycle, which is the whole problem.
        let installedShortVersion: String
        /// What the row should read, in the `155.0b5` form the rest of the app
        /// (notably the changelog templates) already speaks.
        let display: String
    }

    static let cases: [Case] = [
        Case(bundleID: "org.mozilla.firefox", channel: .beta, body: firefoxBetaBody,
             installedBuildID: "20260826090609", installedShortVersion: "155.0",
             display: "155.0b5"),
        Case(bundleID: "org.mozilla.firefoxdeveloperedition", channel: .dev, body: firefoxDevBody,
             installedBuildID: "20260826090609", installedShortVersion: "155.0",
             display: "155.0b5"),
        Case(bundleID: "org.mozilla.nightly", channel: .nightly, body: firefoxNightlyBody,
             installedBuildID: "20260829211045", installedShortVersion: "157.0a1",
             display: "157.0a1"),
        Case(bundleID: "org.mozilla.thunderbirdbeta", channel: .beta, body: thunderbirdBetaBody,
             installedBuildID: "20260826184332", installedShortVersion: "155.0",
             display: "155.0b5"),
        Case(bundleID: "org.mozilla.thunderbird-daily", channel: .nightly, body: thunderbirdDailyBody,
             installedBuildID: "20260829100815", installedShortVersion: "157.0a1",
             display: "157.0a1"),
    ]

    // MARK: - helpers

    /// The registry entry for one case. Deliberately resolved by (bundle id,
    /// channel) so a recipe that silently changes channel fails here rather than
    /// being quietly skipped.
    static func recipe(for c: Case) throws -> VendorProbeRecipe {
        let matches = VendorProbeRegistry.recipes.filter {
            $0.bundleID == c.bundleID && $0.channel == c.channel
        }
        #expect(matches.count == 1,
                Comment(rawValue: "expected one \(c.bundleID) recipe on \(c.channel.rawValue), got \(matches.count)"))
        return try #require(matches.first)
    }

    /// Every Mozilla recipe in the registry, derived rather than listed — a new
    /// one has to satisfy the rules below without anyone remembering to add it.
    static var mozillaRecipes: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.bundleID.hasPrefix("org.mozilla") }
    }

    static func installed(_ c: Case, buildID: String?) -> InstalledApp {
        InstalledApp(
            name: c.bundleID, bundleID: c.bundleID,
            shortVersion: c.installedShortVersion,
            // The real `CFBundleVersion` (`15526.8.26`) — present, in a namespace
            // nothing remote publishes, and therefore never the thing compared.
            buildVersion: "15526.8.26",
            vendorBuildVersion: buildID,
            path: URL(fileURLWithPath: "/Applications/\(c.bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: c.channel)
    }

    static func remote(_ c: Case) throws -> RemoteVersion {
        let recipe = try Self.recipe(for: c)
        let version = try #require(
            VendorProbeRecipe.extractVersion(from: c.body, pattern: recipe.versionPattern),
            Comment(rawValue: "\(recipe.recipeID): versionPattern matched nothing"))
        let display = recipe.displayVersionPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: c.body, pattern: $0)
        }
        return VendorProbeSource.makeRemoteVersion(
            recipe: recipe, version: version, install: recipe.install,
            plan: nil, resolvedDownload: nil, display: display)
    }

    // MARK: - the reason this exists

    /// The old shape, restated: `product-details` gave the marketing string and
    /// nothing else, so the engine compared `155.0b5` against the `155.0` on
    /// disk — and answered "up to date" for the whole cycle. Nightly compared
    /// `157.0a1` against `157.0a1`, which is worse: it is false for every build
    /// Mozilla ships, and it ships one a day.
    @Test func theOldMarketingComparisonIsWhyThisExists() {
        #expect(!VersionComparator.isNewer("155.0b5", than: "155.0"),
                "a pre-release sorts below the release it leads — this is correct, and it is why a marketing-only feed cannot track a beta")
        #expect(!VersionComparator.isNewer("157.0a1", than: "157.0a1"))
    }

    /// And the new shape answers. Two builds of the SAME marketing version — for
    /// nightly, two builds of the same DAY — compare correctly.
    @Test(arguments: Self.cases) func aNewerBuildIsAnUpdate(_ c: Case) throws {
        let remote = try Self.remote(c)
        let behind = String(Int(c.installedBuildID)! - 1)
        #expect(UpdateChecker.evaluate(
            installed: Self.installed(c, buildID: behind), remote: remote)
                == .updateAvailable(latest: c.display),
            Comment(rawValue: "\(c.bundleID): a build behind must be an update"))
        #expect(UpdateChecker.evaluate(
            installed: Self.installed(c, buildID: c.installedBuildID), remote: remote) == .upToDate,
            Comment(rawValue: "\(c.bundleID): the build the endpoint named must be up to date"))
    }

    /// The comparison must never reach across namespaces. `CFBundleVersion` for a
    /// Mozilla build is `<major><yy>.<month>.<day>` (`15526.8.26`) and no Mozilla
    /// endpoint publishes it; measured against a 14-digit `BuildID` it is simply
    /// the smaller number, so a bundle with no `application.ini` would be told it
    /// is behind forever. Say "unknown" instead.
    @Test(arguments: Self.cases) func aBundleWithNoBuildIDIsUnknownNotBehind(_ c: Case) throws {
        let remote = try Self.remote(c)
        #expect(UpdateChecker.evaluate(
            installed: Self.installed(c, buildID: nil), remote: remote) == .unknown)
    }

    // MARK: - registry shape

    /// Derived from the registry: any Mozilla recipe on a pre-release channel has
    /// to be in the vendor build namespace. A new one — a second nightly fork, a
    /// resurrected `aurora` — cannot quietly go back to the marketing comparison
    /// that does not work.
    @Test func everyMozillaPreReleaseRecipeComparesOnTheVendorBuild() {
        let preRelease: Set<ReleaseChannel> = [.beta, .dev, .nightly]
        for recipe in Self.mozillaRecipes where preRelease.contains(recipe.channel) {
            #expect(recipe.versionIsBuild && recipe.buildNamespace == .vendor,
                    Comment(rawValue: "\(recipe.recipeID) is on a pre-release channel but does not compare on application.ini's BuildID"))
            #expect(recipe.displayVersionPattern != nil,
                    Comment(rawValue: "\(recipe.recipeID) would show a bare 14-digit build id in the row"))
        }
    }

    /// The mirror, registry-wide: `.vendor` is meaningless without
    /// `versionIsBuild`, and today Mozilla is the only vendor that speaks it.
    @Test func theVendorNamespaceIsOnlyEverUsedWithABuild() {
        for recipe in VendorProbeRegistry.recipes where recipe.buildNamespace == .vendor {
            #expect(recipe.versionIsBuild,
                    Comment(rawValue: "\(recipe.recipeID) declares the vendor build namespace but reports a marketing version"))
            #expect(recipe.bundleID.hasPrefix("org.mozilla"),
                    Comment(rawValue: "\(recipe.recipeID) is not a Mozilla app — `InstalledApp.vendorBuildVersion` is only populated for org.mozilla.* and would be nil here"))
        }
    }

    /// Stable and ESR are NOT part of this: they move their marketing version on
    /// every release, `product-details` states it, and nothing needed fixing.
    /// Asserted so a future sweep doesn't move them onto AUS for symmetry and
    /// lose the one thing AUS cannot give — a version a human recognises.
    @Test func stableAndESRStayOnProductDetails() {
        for recipe in Self.mozillaRecipes
        where recipe.channel == .stable || recipe.channel == .esr {
            #expect(recipe.url.host() == "product-details.mozilla.org",
                    Comment(rawValue: "\(recipe.recipeID) left product-details"))
            #expect(!recipe.versionIsBuild && recipe.buildNamespace == .bundle,
                    Comment(rawValue: "\(recipe.recipeID) should still compare marketing versions"))
        }
    }

    /// Each app asks the host its own `application.ini` names. Thunderbird's
    /// `[AppUpdate] URL` is `aus.thunderbird.net`, which 302s to the same path on
    /// `aus5.mozilla.org`; we follow Thunderbird's, so that if the two ever
    /// diverge we are on the side that stays right.
    @Test(arguments: Self.cases) func theEndpointIsTheOneTheAppItselfAsks(_ c: Case) throws {
        let recipe = try Self.recipe(for: c)
        let expected = c.bundleID.contains("thunderbird")
            ? "aus.thunderbird.net" : "aus5.mozilla.org"
        #expect(recipe.url.host() == expected)
        #expect(recipe.url.path.hasPrefix("/update/6/"))
        // Balrog needs all eleven path parameters; drop one (the easy one to
        // forget is `%SYSTEM_CAPABILITIES%`) and it answers with nothing at all.
        #expect(recipe.url.path.split(separator: "/").count == 13,
                Comment(rawValue: "\(recipe.recipeID): \(recipe.url.path) is not a complete Balrog path"))
    }

    /// The anchor is frozen on purpose, and this states the two properties that
    /// make that safe. AUS is *conditional* — it answers "what is newer than the
    /// build you named" — so a per-machine anchor would make an empty response
    /// mean "you are current" on a Mac and "the recipe is broken" in a sweep. One
    /// response shape, two meanings, is how a check goes quietly dead. A frozen
    /// anchor means every caller sends the same request and empty is always a
    /// failure.
    @Test(arguments: Self.cases) func theAnchorIsFrozenSoAnEmptyAnswerIsAlwaysAFailure(_ c: Case) throws {
        let recipe = try Self.recipe(for: c)
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.upToDateBody, pattern: recipe.versionPattern) == nil,
            "an empty <updates/> must not resolve to a version")
        // …and the anchor must not be mistakable for the answer. `RecipeSanity`
        // warns when an extracted version appears verbatim in the request URL,
        // which is the shape of a pattern reading the URL instead of the body.
        #expect(!recipe.url.absoluteString.contains(c.display),
                Comment(rawValue: "\(recipe.recipeID): the anchor spells out the answer"))
        #expect(!recipe.url.absoluteString.contains(c.installedBuildID))
    }

    // MARK: - the patterns, against the real bodies

    @Test(arguments: Self.cases) func theBuildIDIsReadOutOfTheResponse(_ c: Case) throws {
        let recipe = try Self.recipe(for: c)
        #expect(VendorProbeRecipe.extractVersion(
            from: c.body, pattern: recipe.versionPattern) == c.installedBuildID,
            Comment(rawValue: "\(recipe.recipeID): the endpoint's buildID must be byte-identical to the dmg's application.ini BuildID"))
    }

    /// The row keeps the `155.0b5` spelling rather than Mozilla's own
    /// `displayVersion` ("155.0 Beta 5"), and that is load-bearing: the beta
    /// changelog recipes template their URL off this string. Fed the prose form,
    /// `urlVersionToken` produces `155.0 Beta 5beta` and the release notes 404 —
    /// which is exactly what happened the first time this recipe was written.
    @Test(arguments: Self.cases) func theDisplayVersionIsTheFormTheRestOfTheAppSpeaks(_ c: Case) throws {
        let recipe = try Self.recipe(for: c)
        let pattern = try #require(recipe.displayVersionPattern)
        #expect(VendorProbeRecipe.extractVersion(from: c.body, pattern: pattern) == c.display)
    }

    @Test func theBetaChangelogURLStillResolves() throws {
        #expect(ChangelogRecipe.urlVersionToken(for: "155.0b5", channel: .beta) == "155.0beta")
        #expect(ChangelogRecipe.urlVersionToken(for: "155.0 Beta 5", channel: .beta)
            != "155.0beta",
            "stated as the counter-example: this is the form that 404s")
    }

    /// A `versionIsBuild` recipe routes the build into `version` and the display
    /// string into `shortVersion` — so nothing downstream that reads a marketing
    /// version starts seeing a 14-digit number.
    @Test(arguments: Self.cases) func theRemoteCarriesBothHalves(_ c: Case) throws {
        let remote = try Self.remote(c)
        #expect(remote.version == c.installedBuildID)
        #expect(remote.shortVersion == c.display)
        #expect(remote.displayVersion == c.display)
        #expect(remote.buildNamespace == .vendor)
    }

    // MARK: - everywhere else a remote build meets an installed one

    /// The row's "same version, different build" line. Nightly is the case that
    /// reaches it — `latest` and the installed marketing version are both
    /// `157.0a1` — and both halves have to be the build the source is speaking in.
    /// Reading `CFBundleVersion` on the left would render `15726.8.29 →
    /// 20260829211045`: two numbers from unrelated namespaces, side by side, with
    /// nothing marking them as such.
    @Test func theBuildBumpLineShowsOneNamespace() throws {
        let c = try #require(Self.cases.first { $0.channel == .nightly })
        let remote = try Self.remote(c)
        let behind = String(Int(c.installedBuildID)! - 1)
        let result = UpdateResult(
            app: Self.installed(c, buildID: behind), remote: remote,
            status: .updateAvailable(latest: c.display))
        let bump = try #require(result.buildBump(latest: c.display))
        #expect(bump == (installed: behind, remote: c.installedBuildID))
    }

    /// `duo verify`'s "the feed is BEHIND the copy you have" check — the tell for
    /// a recipe reading a different version scheme than the app reports. Handed a
    /// `CFBundleVersion` against a Mozilla `BuildID` it does not complain, it
    /// answers "not behind" forever: a 14-digit stamp outranks `15526.8.26` no
    /// matter what either side is doing. It has to be given the vendor build.
    @Test(arguments: Self.cases) func theSweepsBehindCheckComparesInTheRightNamespace(
        _ c: Case
    ) throws {
        let remote = try Self.remote(c)
        // Honest state: the machine is ahead of what the endpoint serves. This is
        // what the check exists to notice.
        let ahead = String(Int(c.installedBuildID)! + 1)
        #expect(RecipeSanity.remoteBehindInstalled(
            remote: remote, installedMarketing: c.installedShortVersion,
            installedBuild: "15526.8.26", installedVendorBuild: ahead) != nil,
            Comment(rawValue: "\(c.bundleID): a genuinely behind endpoint went unreported"))
        // And the current build is not "behind".
        #expect(RecipeSanity.remoteBehindInstalled(
            remote: remote, installedMarketing: c.installedShortVersion,
            installedBuild: "15526.8.26", installedVendorBuild: c.installedBuildID) == nil)
        // Without a vendor build there is no comparable build, and the check falls
        // back to marketing rather than reaching for `CFBundleVersion` — which for
        // a beta means the advisory its own doc already names as an honest false
        // positive (`155.0b5` sorts below the suffix-less `155.0` the bundle
        // reports). Unchanged from before these recipes moved to AUS, where
        // `remote.version` was nil and this same branch ran; asserted so the
        // fallback stays the marketing one and never becomes the cross-namespace
        // build comparison, which would answer "not behind" for anything.
        let noVendorBuild = RecipeSanity.remoteBehindInstalled(
            remote: remote, installedMarketing: c.installedShortVersion,
            installedBuild: "15526.8.26", installedVendorBuild: nil)
        #expect(noVendorBuild == nil || noVendorBuild!.contains(c.installedShortVersion),
                Comment(rawValue: "\(c.bundleID): the fallback stopped being the marketing one"))
    }

    /// The display string is load-bearing here, so losing it has to be reported.
    ///
    /// Found while reviewing this change: a `displayVersionPattern` that matches
    /// nothing had no warning of its own, and `duo verify` could not see it either
    /// — it records `shortVersion ?? version`, so a lost display string makes the
    /// recorded value jump from `155.0b5` to `20260826090609`, an INCREASE, while
    /// the only history check it has looks for a version moving backwards.
    /// Meanwhile the beta changelog URL is templated off that same string and 404s.
    @Test func aLostDisplayStringIsWarnedAbout() async throws {
        let c = try #require(Self.cases.first { $0.bundleID == "org.mozilla.firefox" })
        let recipe = try Self.recipe(for: c)

        let healthy = try RecipeVerificationTests.StubServer(body: c.body)
        defer { healthy.stop() }
        let good = await VendorProbeSource().probeDiagnostic(recipe.with(url: healthy.url))
        #expect(good.remote?.shortVersion == c.display)
        #expect(!good.warnings.contains(.displayPatternNoMatch))

        // The one edit a vendor rename would make. The version still resolves —
        // which is the whole problem: nothing else notices.
        let renamed = c.body.replacingOccurrences(
            of: "product=firefox-", with: "product=firefox-desktop-")
        let broken = try RecipeVerificationTests.StubServer(body: renamed)
        defer { broken.stop() }
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: broken.url))
        #expect(outcome.failure == nil, "the build still resolves — that is the point")
        #expect(outcome.remote?.version == c.installedBuildID)
        #expect(outcome.remote?.shortVersion == nil)
        #expect(outcome.remote?.displayVersion == c.installedBuildID,
                "the row would show a bare 14-digit build id")
        #expect(ChangelogRecipe.urlVersionToken(for: c.installedBuildID, channel: .beta)
            != "155.0beta", "…and the beta release notes would 404")
        #expect(outcome.warnings.contains(.displayPatternNoMatch))
    }

    // MARK: - the disk side

    /// `AppScanner` reads both fields out of one `application.ini`. The values are
    /// the real ones from `Firefox 155.0b5.dmg`.
    @Test func theScannerReadsRemotingNameAndBuildID() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("moz-ini-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("Firefox.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try """
            [App]
            Vendor=Mozilla
            Name=Firefox
            RemotingName=firefox-beta
            Version=155.0
            BuildID=20260826090609
            SourceRepository=https://hg.mozilla.org/releases/mozilla-beta

            [Gecko]
            MinVersion=155.0
            """.write(to: resources.appendingPathComponent("application.ini"),
                      atomically: true, encoding: .utf8)

        let ini = AppScanner.mozillaApplicationINI(in: root.appendingPathComponent("Firefox.app"))
        #expect(ini.remotingName == "firefox-beta")
        #expect(ini.buildID == "20260826090609")
        // The one-field reader still answers the same thing for the channel gate.
        #expect(AppScanner.mozillaRemotingName(
            in: root.appendingPathComponent("Firefox.app")) == "firefox-beta")
    }

    /// A bundle with no `application.ini` (a fork, a damaged install) yields
    /// nothing rather than a stale or invented value.
    @Test func aBundleWithoutTheFileYieldsNothing() {
        let ini = AppScanner.mozillaApplicationINI(
            in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).app"))
        #expect(ini.remotingName == nil && ini.buildID == nil)
    }
}
