import Foundation

/// A committed probe target for `duo verify`'s Mac App Store sweep.
///
/// Every field is a public statement — "we check this app's listing" —
/// exactly like a `VendorProbeRecipe` or a `GitHubReleaseRule`. See
/// `MacAppStoreProbeRegistry`'s doc comment for why this list is hand-picked
/// rather than derived from what's installed on the sweeping machine.
public struct MacAppStoreProbeCase: Sendable {
    /// Which of `MacAppStoreSource.resolve(result:app:region:)`'s branches
    /// this case exercises.
    public enum Route: String, Sendable, CaseIterable {
        /// `kind == "mac-software"` → `nativeMacVersion`: page-scrapes the
        /// `mostRecentVersion` shelf, and is the only route that trusts the
        /// lookup's own `trackViewUrl` for a zero-redirect fetch (A2).
        case nativeMac
        /// `kind == "software"`, but the Mac build publishes on its own
        /// release line → `iosOnMacVersion`: same shelf scrape, on the
        /// `?platform=mac` page built from `trackId` (this route does NOT use
        /// `trackViewUrl` — see `MacAppStoreSource.iosOnMacVersion`, which
        /// points out that URL would land on the iOS listing instead).
        case iosOnMac
        /// `kind == "software"`, installed as the wrapped iOS binary →
        /// `remoteVersion(checkMacCompat: true)`: reads
        /// `isIOSBinaryMacOSCompatible` *and* `appPlatforms` off the plain
        /// (non `platform=mac`) product page.
        case wrappedIOS
    }

    /// `CFBundleIdentifier` this entry names.
    public let bundleID: String
    /// The listing's numeric App Store id — `itunes.apple.com/lookup`'s
    /// `trackId`.
    public let trackId: Int
    /// Storefront to probe. Always a fixed, public one (never the sweeping
    /// machine's own — see `MacAppStoreSource.homeRegion`) so the sweep's
    /// answer doesn't depend on where it happens to run.
    public let region: String
    /// What `LookupResult.kind` must read for this app. A value that drifts
    /// silently reroutes `resolve()` to a different branch — see
    /// `MacAppStoreSource.resolve(result:app:region:)`.
    public let expectedKind: String
    public let route: Route

    public init(bundleID: String, trackId: Int, region: String = "us", expectedKind: String, route: Route) {
        self.bundleID = bundleID
        self.trackId = trackId
        self.region = region
        self.expectedKind = expectedKind
        self.route = route
    }

    /// Stable sweep key — same shape as `VendorProbeRecipe`'s and
    /// `GitHubReleaseRule`'s, so the baseline and issue history key on it the
    /// same way.
    public var recipeID: String { "appstore:\(bundleID)" }
}

/// Committed probe targets for `duo verify`'s Mac App Store sweep.
///
/// `MacAppStoreSource` is not a recipe source — it has nothing to verify
/// against a registry, because it doesn't read one: it asks Apple's public
/// lookup API whatever bundle id an already-installed app carries, at
/// whatever storefront the signed-in account happens to be in. So until this
/// registry existed, `duo verify` had never swept it at all, and a batch of
/// changes to it (batched-lookup prewarm, product-page TTL caching, trusting
/// the lookup's own `trackViewUrl` instead of a constructed one) shipped with
/// only unit-test coverage against captured fixtures.
///
/// The failure mode this exists to catch is SILENT. If Apple reshapes the
/// embedded JSON `extractMacVersionInfo`/`extractMacCompatibility` parse:
///   - `nativeMacVersion` quietly falls back to the (possibly stale) lookup
///     version — no error, no red row, just an answer that stopped being the
///     freshest one.
///   - `iosOnMacVersion` returns nil outright — the row silently becomes "no
///     source" for that app.
/// Nothing in the shipping app or the existing unit tests would notice either
/// one. This sweep asks the real endpoints, on a fixed schedule, whether the
/// shapes the parsers depend on are still there.
///
/// **Every entry names a long-lived, first-party-maintained listing — never
/// an app read off the machine that happens to be running the sweep.**
/// `scripts/check_app_audits.py`'s header explains why that distinction is
/// load-bearing here, not stylistic: a list built from what's installed on a
/// specific Mac has, in this repo's history, doxed what's on that Mac. Naming
/// bundle ids here is the same kind of public statement `VendorProbeRegistry`
/// and `GitHubReleaseRegistry` already make ("we check this app"), which is
/// fine; deriving the list from `AppScanner().scan()` would not be.
///
/// Picked to cover every branch `resolve()` can take, confirmed live against
/// the real endpoints on 2026-09-04 (see the per-case comments in each app's `Recipes/<family>.swift`) — and
/// picked for apps unlikely to vanish from the store or change distribution
/// model, so this doesn't need re-curating every few months the way an
/// arbitrary installed-app sample would.
public enum MacAppStoreProbeRegistry {

    /// The id the sweep files a failed BATCH lookup under.
    ///
    /// It has to live here, next to the per-case ids, for one reason: `duo
    /// verify` prunes its baseline against the set of ids the registries can
    /// still produce, and it prunes BEFORE it saves. A synthetic id invented at
    /// the call site is therefore created, dropped, and never persisted — so it
    /// can never reach the `consecutiveInfra >= 3` escalation, can never fail a
    /// run however many nights it breaks, and prints as "no recipe produces
    /// this id any more", which reads as a recipe deletion rather than a
    /// network failure. That is exactly the vanishing-guard shape the sweep's
    /// own batch check was rewritten to remove; putting the id in the registry
    /// is what stops it happening one layer down. Lowercase `appstore:` to
    /// match `recipeID` — the first attempt used `appStore:` and fell out of
    /// the live set on the casing alone.
    public static let batchRecipeID = "appstore:batch"

    public static let cases: [MacAppStoreProbeCase] = AppRecipeIndex.all.flatMap(\.appStoreCases)
}
