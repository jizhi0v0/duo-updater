import Foundation

/// CleanShot X (`pl.maketheweb.cleanshotx`) — a Sparkle app whose code-signed
/// Info.plist `SUFeedURL` points at the LEGACY v3 appcast
/// (`updates.getcleanshot.com/v3/appcast.xml`), which is frozen at 3.7.1. The
/// real 4.x updates come from the maketheweb "Legit" licensing service, which
/// serves a per-license, subscription-filtered Sparkle appcast: its head is the
/// newest build the user's entitlement covers, so reusing it never reports a
/// version the user isn't licensed for (sidesteps the subscription-detection
/// dead-end — see the `duo-updater-subscription-detection` memory).
///
/// We read the user's license key from CleanShot's own (plaintext) prefs and
/// swap the feed to the personalized legit endpoint, so the existing
/// `SparkleAppcastSource` parses the correct, entitlement-aware latest — and the
/// `4.8.8 ↓ 3.7.1` phantom downgrade disappears.
///
/// Security: the resolved feed URL carries `?key=<licenseKey>`. The key is a
/// credential, so it must never be logged or persisted. Audited (2026-06-03):
/// nothing prints `sparkleFeedURL` — `SparkleAppcastSource` does no logging,
/// `UpdateChecker`/`AppListModel` log by app name/version/source name only, the
/// URL-keyed `ChangelogCache` is in-memory and keyed on the *changelog recipe*
/// source (cleanshot.com/changelog), not this feed, and `InstalledApp` is not
/// Codable so it never reaches disk. Re-audit before adding any feed-URL log.
enum CleanShotChannel {
    static let bundleID = "pl.maketheweb.cleanshotx"

    /// Build the personalized legit appcast feed from a license key.
    static func feed(forKey key: String) -> URL? {
        var components = URLComponents(string: "https://legit.maketheweb.io/api/v1/appcast")
        components?.queryItems = [URLQueryItem(name: "key", value: key)]
        return components?.url
    }

    /// nil when there's no readable license key — we then leave the feed alone and
    /// fall back to the app's shipped v3 `SUFeedURL` (current behavior), never to
    /// a higher channel. Graceful, non-degrading.
    static func resolveCurrent() -> ResolvedChannel? {
        resolve(activationKey: readActivationKey())
    }

    /// The pure half, so `ChannelBinding.allResolutions` can enumerate what this
    /// binding is CAPABLE of without depending on whether the machine running the
    /// tests happens to have a licensed CleanShot on it.
    ///
    /// That is not a hypothetical tidy-up: enumerating via `resolveCurrent()`
    /// made the binding appear on a licensed Mac and vanish on every other one,
    /// so the enumeration test passed for the author and failed for everybody
    /// else — and it put a REAL licence key into a public `static let` global, in
    /// a file whose own header says the key must never be logged or persisted.
    /// Callers enumerate with a placeholder; only `resolveCurrent()` ever sees the
    /// real one.
    static func resolve(activationKey: String?) -> ResolvedChannel? {
        guard let key = activationKey, !key.isEmpty,
              let feed = feed(forKey: key) else { return nil }
        return ResolvedChannel(channel: .stable, feedOverride: feed)
    }

    /// A syntactically-valid stand-in for the licence key, for enumeration only.
    /// Never a real key, and never used to build a request.
    static let placeholderActivationKey = "PLACEHOLDER-NOT-A-REAL-KEY"

    /// Read `activationKey` from CleanShot's own defaults via CFPreferences, so
    /// it's authoritative even while CleanShot is running. Plaintext, non-keychain;
    /// DuoUpdater is unsandboxed so it's directly readable. nil if absent.
    static func readActivationKey() -> String? {
        guard let raw = CFPreferencesCopyAppValue(
            "activationKey" as CFString, bundleID as CFString) else { return nil }
        return raw as? String
    }
}
