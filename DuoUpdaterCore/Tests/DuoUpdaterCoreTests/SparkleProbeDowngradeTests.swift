import Testing
import Foundation
@testable import DuoUpdaterCore

/// Vendor probes that read a Sparkle appcast bypass `SparkleAppcastSource`
/// entirely — `usableItems`, `allowedChannels` and the marketing-downgrade guard
/// added in #368 all live there, and none of them runs on this path (#376).
///
/// What was measured, on the real bodies fetched 2026-09-06, before writing
/// anything here:
///
/// 1. **Only two of the twelve reach a build comparison.** `makeRemoteVersion`
///    fills `RemoteVersion.version` only for a `versionIsBuild` recipe, and
///    `UpdateChecker.evaluate` enters the build branch only when that is
///    non-nil. Every other appcast probe lands in the marketing branch, whose
///    first act is `guard isNewer(remote, than: installed) else { .upToDate }` —
///    a marketing downgrade is already unofferable there, and setting
///    `marketingMatchesBundle` on those recipes would be a no-op, since the
///    build branch is the only place it is read.
/// 2. **Cross-track ordering, the primary #368 mechanism, cannot happen here.**
///    Of the nine appcasts fetched, exactly one carries `sparkle:channel` at all
///    (OrbStack), and OrbStack's own `versionPattern` anchors on that tag. Every
///    other feed is one channel per URL.
/// 3. **Head-of-document ordering is already handled.** Bartender (16 items,
///    ascending 6.0.0 → 6.6.2), Kagi (48 items, ascending) and Docker (not
///    version-ordered at all) each set `selectHighest`, Docker additionally
///    picking its enclosure by declared version; the rest are newest-first
///    (Brave beta 1.95.96.0 → 1.70.107.0) or single-item.
///
/// So the answer to #376 is "no flag and no new gate on the check path" — and
/// these tests are what stops that answer from silently expiring.
struct SparkleProbeDowngradeTests {

    /// Every recipe whose `versionPattern` reads a `sparkle:` field. Derived, not
    /// listed: matching on the pattern rather than on the URL also catches
    /// WeChat, whose appcast is served as `mac-release.xml`, and it moves with
    /// the registry instead of drifting from it.
    static var sparkleReading: [VendorProbeRecipe] {
        VendorProbeRegistry.recipes.filter { $0.versionPattern.contains("sparkle:") }
    }

    /// The only appcast probes allowed into `evaluate`'s BUILD branch, each with
    /// the reason its build comparison is safe without a marketing witness.
    ///
    /// Reviewed as a pair with the test below: an entry here is a statement that
    /// somebody checked, and a stale entry is an inspection-free pass, so the
    /// suite also fails when one stops applying.
    static let buildComparedByDesign: [String: String] = [
        // Brave publishes one feed per channel per architecture, so there is no
        // second track to be ranked above this one; a backwards offer would take
        // a vendor rollback at the head of the feed. And the marketing witness
        // the #368 guard wants CANNOT be supplied here: the feed's
        // `sparkle:shortVersionString` is Brave's own 4-part version
        // ("1.95.96.0") while the installed bundle's
        // `CFBundleShortVersionString` is Chromium-major-prefixed
        // ("151.1.94.104", measured 2026-08-09; Brave's changelog puts 1.95/1.97
        // on Chromium 151-152, which is that leading segment). Setting
        // `marketingMatchesBundle` would put 1 against 151 and read every real
        // update as a downgrade — the same phantom that `versionIsBuild` exists
        // to prevent, re-entered through a different door. The case below
        // executes that.
        "com.brave.Browser.beta": "one feed per channel; feed marketing string is not the bundle's",
        "com.brave.Browser.nightly": "one feed per channel; feed marketing string is not the bundle's",
    ]

    /// Mutation: add `versionIsBuild: true` to any other appcast recipe — which
    /// is exactly how a new one would acquire this exposure — and this fails
    /// naming it.
    @Test func everySparkleReadingProbeIsMarketingComparedOrRegistered() {
        let recipes = Self.sparkleReading
        // A floor, because the selector is a substring match on the pattern: if
        // `sparkle:` stops appearing (a rewrite as `sparkle\:`, a move to a
        // different field) this whole suite goes vacuous while staying green.
        // Retiring a recipe is the one legitimate way to trip it — lower the
        // number in that commit, don't delete the check.
        #expect(recipes.count >= 12, """
            only \(recipes.count) recipes read a `sparkle:` field: either one was retired \
            (lower this floor in that commit) or the selector stopped matching (fix it)
            """)
        for recipe in recipes where recipe.versionIsBuild {
            #expect(Self.buildComparedByDesign[recipe.bundleID] != nil, """
                \(recipe.bundleID) compares BUILDS off a Sparkle appcast, which puts it in \
                UpdateChecker.evaluate's build branch — the one place a marketing downgrade \
                can be offered — with no marketing witness. Register it above with the reason \
                its direction is safe, or drop versionIsBuild.
                """)
        }
    }

    /// The `mayLookAlike` rule from `make gallery`, applied here: a registration
    /// that no longer matches anything is a permanent exemption for whatever
    /// takes its place.
    ///
    /// Mutation: delete Brave's `versionIsBuild: true` without deleting its entry
    /// and this fails.
    @Test func everyRegistrationStillDescribesABuildComparedProbe() {
        let compared = Set(Self.sparkleReading.filter(\.versionIsBuild).map(\.bundleID))
        for (bundleID, reason) in Self.buildComparedByDesign {
            #expect(compared.contains(bundleID),
                    "\(bundleID) is registered as build-compared (\(reason)) but no longer is")
        }
    }

    /// The reason none of the others needs a guard, executed rather than
    /// asserted from reading: every marketing-compared appcast probe, handed a
    /// version OLDER than the installed one, refuses.
    ///
    /// Mutation: `if !VersionComparator.isNewer(rs, than: isv)` → `if false` in
    /// `evaluate`'s marketing branch and this fails for all of them.
    @Test func aMarketingComparedProbeCannotOfferAnOlderVersion() throws {
        let recipes = Self.sparkleReading.filter { !$0.versionIsBuild }
        try #require(!recipes.isEmpty)
        for recipe in recipes {
            let remote = Self.remoteVersion(from: recipe, version: "1.0.0")
            // The precondition the whole argument rests on: no build, so
            // `evaluate` cannot take the build branch where the guard lives.
            #expect(remote.version == nil, "\(recipe.bundleID) reached the build branch")
            #expect(!remote.marketingMatchesBundle)
            // The build carries dots ON PURPOSE. `evaluate`'s marketing branch has
            // a second, narrower refusal after the first — the Oray fallback,
            // which re-compares against "<short>.<build>" — and it only runs for a
            // dot-free build. A "2000" build here made this case pass with the
            // primary `isNewer` guard mutated to `if false`: it was measuring the
            // fallback, not the guard the argument rests on.
            let installed = Self.installedApp(
                bundleID: recipe.bundleID, short: "2.0.0", build: "2.0.0.1")
            #expect(UpdateChecker.evaluate(installed: installed, remote: remote) == .upToDate,
                    "\(recipe.bundleID) was offered 1.0.0 over an installed 2.0.0")
        }
    }

    /// Why Brave must NOT get `marketingMatchesBundle`, executed on its real
    /// strings rather than argued in a comment.
    ///
    /// Mutation: pass `marketingMatchesBundle: true` from `makeRemoteVersion` and
    /// the first half of this fails — every Brave beta update, forever.
    @Test func braveWouldStopUpdatingIfItsFeedStringWereCalledTheBundles() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.brave.Browser.beta" })
        // Feed values fetched 2026-09-06; installed values are the shape recorded
        // on the real bundle 2026-08-09.
        let installed = Self.installedApp(
            bundleID: recipe.bundleID, short: "151.1.94.104", build: "194.104")
        let asShipped = Self.remoteVersion(
            from: recipe, version: "195.96", display: "1.95.96.0")
        #expect(asShipped.version == "195.96")
        #expect(!asShipped.marketingMatchesBundle)
        #expect(UpdateChecker.evaluate(installed: installed, remote: asShipped)
                == .updateAvailable(latest: "1.95.96.0"))

        // The same answer with the flag turned on. `1` loses to `151`, so the
        // guard reads a real update as a downgrade and holds it back.
        let withFlag = RemoteVersion(
            shortVersion: asShipped.shortVersion, version: asShipped.version,
            buildNamespace: asShipped.buildNamespace, marketingMatchesBundle: true,
            downloadURL: nil, sourceName: asShipped.sourceName)
        #expect(UpdateChecker.evaluate(installed: installed, remote: withFlag) == .upToDate,
                "if this stops holding, revisit whether Brave could carry the flag after all")
    }

    /// `makeRemoteVersion` down the branch THIS recipe takes in production.
    ///
    /// It has two — one for a recipe with an install spec and a resolved plan,
    /// one for detection only. Both leave `marketingMatchesBundle` at its
    /// default, but they are separate literals, so a case that always passed
    /// `install: nil, plan: nil` would stay green on a mutation touching only the
    /// installable branch — the branch most of these recipes actually use
    /// (Bartender, Kagi, Docker, WeChat, OrbStack, Vivaldi, ImageOptim and both
    /// Braves all carry install specs). Each branch was mutated separately to
    /// confirm this reaches both.
    private static func remoteVersion(
        from recipe: VendorProbeRecipe, version: String, display: String? = nil
    ) -> RemoteVersion {
        let plan: (url: URL, checksum: String?)? = recipe.install == nil
            ? nil : (url: URL(string: "https://example.invalid/artifact")!, checksum: nil)
        return VendorProbeSource.makeRemoteVersion(
            recipe: recipe, version: version, install: recipe.install, plan: plan,
            resolvedDownload: nil, display: display)
    }

    private static func installedApp(bundleID: String, short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: bundleID, bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil)
    }
}
