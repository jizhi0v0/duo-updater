import Foundation

/// Mac Mouse Fix (`com.nuebling.mac-mouse-fix`) — a feed-swap Sparkle app, same
/// shape as IINA: the shipped Info.plist `SUFeedURL` is always the STABLE feed,
/// and the user's own in-app toggle swaps in a second feed at runtime.
///
/// Read from the open-source repo rather than inferred (issue #555 / #556):
/// `App/Update/SparkleUpdaterController.m`'s `+enablePrereleaseChannel:` does
/// exactly this —
/// ```
/// SUUpdater.sharedUpdater.feedURL =
///     pre ? "<repo>/update-feed/appcast-pre.xml" : "<repo>/update-feed/appcast.xml"
/// ```
/// where `<repo>` is `kMFUpdateFeedRepoAddressRaw`
/// (`https://raw.githubusercontent.com/noah-nuebling/mac-mouse-fix/update-feed`,
/// `Shared/Constants.h`). The toggle itself (`betaToggle` in
/// `App/UI/Main/Tabs/GeneralTabController.swift`) writes a Bool at the config
/// path `General.checkForPrereleases` — NOT UserDefaults/CFPreferences. Mac
/// Mouse Fix keeps its own config file instead (`Shared/Locator/Locator.m`):
/// `~/Library/Application Support/com.nuebling.mac-mouse-fix/config.plist`, a
/// dict whose `"General"` entry is itself a dict holding `"checkForPrereleases"`
/// (confirmed against the bundle's own `Contents/Resources/default_config.plist`,
/// which ships that shape with the key defaulting to `false`).
///
/// `generate_releases.py` (the script that WRITES both feeds, read on the
/// `update-feed` branch) is the authority on how the two tracks are built, and
/// two things follow from reading it rather than guessing:
///   * `is_prerelease = r['prerelease']` comes straight from the GitHub release
///     API flag. The stable feed (`appcast_items`) only ever gets
///     `not is_prerelease` releases; the preview feed (`appcast_pre_items`) gets
///     EVERY release, prerelease or not — so it is a superset of stable, not a
///     separate track, and both lists preserve the GitHub API's own
///     newest-first order (no re-sort in the script).
///   * `sparkle:shortVersionString` is `r['name']` — the release's literal
///     GitHub display name, e.g. the verified newest preview item's
///     `"3.1.0 Beta 1"` (space, capital B) — while `sparkle:version` is the
///     REAL `CFBundleVersion` read out of the actual downloaded, unzipped
///     bundle. Downloading that exact asset (build 24830, 2026-09-12) confirms
///     both fields land on the installed copy unchanged: its own
///     `CFBundleShortVersionString` is the literal `3.1.0 Beta 1` and its
///     `CFBundleVersion` is `24830` — so there is no feed-vs-bundle mismatch
///     here the way Mozilla's suffix-stripping is (`ReleaseChannel.detect`'s
///     own warning). `RemoteVersion.marketingMatchesBundle: true` is correct.
///
/// Comparator behaviour actually run against `"3.1.0 Beta 1"` (not assumed):
///   * `VersionComparator.comparableMarketingVersion` rejects any string
///     containing whitespace, so `"3.1.0 Beta 1"` fails it. `isMarketingDowngrade`
///     therefore answers "cannot tell" (→ not a downgrade) for a pair on either
///     side of it — the safe direction, since callers use that guard only to
///     WITHHOLD an offer, never to raise one.
///   * `UpdateChecker.evaluate` reaches its build-number branch first: with both
///     sides carrying `sparkle:version`, `24830` vs. an installed `24310`
///     compares as strictly newer under `VersionComparator.isNewer`, and the
///     marketing-downgrade guard above declines to override that verdict — so
///     the beta is correctly offered. This is not an accident of this one pair:
///     Mac Mouse Fix's OWN Sparkle delegate (`CoolSUComparator.m`) resolves the
///     exact same ambiguity the same way — it strips a version string down to
///     its leading digits-and-periods run before comparing (so `"3.1.0"` and
///     `"3.1.0 Beta 1"` compare EQUAL), then breaks the tie on the build number
///     — i.e. the vendor's own client also treats the build as authoritative
///     once the marketing strings tie. Both call sites lean on the same fact:
///     `CFBundleVersion` here is a real, monotonically increasing build id.
///
/// ⚠️ **This file is the ONLY thing on disk that can tell a beta copy from a
/// stable one**, which is why the binding has to exist rather than leaving the
/// app to `ReleaseChannel.detect()`. Measured 2026-09-12 against the real
/// detector: `detect(version: "3.1.0 Beta 1")` answers `.stable`. Its
/// version-suffix signal reads the `-beta.1` shape, not a space-separated
/// `Beta 1`, and the bundle id, app name and bundle filename are identical on
/// both tracks — so nothing else has anything to go on. The practical
/// consequence to keep in mind when touching `readCheckForPrereleases`: a
/// config file we cannot read resolves to an AUTHORITATIVE `.stable` (see
/// `AppScanner`, where a non-nil binding sets `channelIsAuthoritative`), and no
/// `detect()` signal is being suppressed when that happens — there was never one
/// to suppress. That is what makes false-on-failure safe HERE and is not a
/// licence to copy it into a resolver whose app does mark its betas; CotEditor's
/// maps false to nil for exactly the opposite reason.
///
/// Team ID is unchanged across channels: the downloaded 3.1.0 Beta 1 bundle is
/// signed `Developer ID Application: Noah Nuebling (LM5Z78756B)`, matching the
/// installed stable copy — so a one-click install does not cross signing
/// identities.
enum MacMouseFixChannel {
    static let bundleID = "com.nuebling.mac-mouse-fix"

    static let stableFeed = URL(
        string: "https://raw.githubusercontent.com/noah-nuebling/mac-mouse-fix/update-feed/appcast.xml")!
    static let betaFeed = URL(
        string: "https://raw.githubusercontent.com/noah-nuebling/mac-mouse-fix/update-feed/appcast-pre.xml")!

    /// Map Mac Mouse Fix's `General.checkForPrereleases` flag to a resolution.
    /// Pure and tested. `stableFeed` is named explicitly (even though it is also
    /// the bundle's own signed `SUFeedURL`) so a stable resolution never
    /// depends on that plist value staying what it is today — the same choice
    /// `IINAChannel` makes for the same reason.
    static func resolve(checkForPrereleases: Bool) -> ResolvedChannel {
        checkForPrereleases
            ? ResolvedChannel(channel: .beta, feedOverride: betaFeed)
            : ResolvedChannel(channel: .stable, feedOverride: stableFeed)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(checkForPrereleases: readCheckForPrereleases())
    }

    /// The file `readCheckForPrereleases` reads. Exposed for the same reason
    /// `SurgeChannel.defaultsFileURL` is: `ChannelBinding.preferenceWatchCandidates`
    /// has to sit on exactly this path, and a watcher aimed anywhere else would
    /// look healthy while never firing.
    static var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("config.plist", isDirectory: false)
    }

    /// Read `General.checkForPrereleases` from Mac Mouse Fix's own config file.
    /// Returns false (stable) if the file, the `General` dict, or the key is
    /// missing — the conservative default, same stance `SurgeChannel` takes.
    static func readCheckForPrereleases() -> Bool {
        guard
            let data = try? Data(contentsOf: configFileURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any]
        else { return false }
        return checkForPrereleases(fromConfig: plist)
    }

    /// The typed half of the read, split out so the nested-dict lookup can be
    /// tested without touching the real config file — same discipline
    /// `ForkChannel.channelPref(from:)` uses for its own preference read.
    ///
    /// The key is nested (`plist["General"]["checkForPrereleases"]`), not a
    /// dotted top-level key — confirmed against the bundle's own
    /// `default_config.plist`, which ships exactly this shape. The dotted
    /// string `"General.checkForPrereleases"` seen in `AppDelegate.m` is Mac
    /// Mouse Fix's OWN config accessor's path syntax, not the on-disk key.
    static func checkForPrereleases(fromConfig plist: [String: Any]?) -> Bool {
        guard let general = plist?["General"] as? [String: Any] else { return false }
        return (general["checkForPrereleases"] as? NSNumber)?.boolValue ?? false
    }
}
