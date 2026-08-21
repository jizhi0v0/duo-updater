import Foundation
import CryptoKit

/// Detects when a `ChannelBinding`-covered app's user-chosen channel has actually
/// changed since we last looked — e.g. the user opened Tailscale's own
/// Preferences and flipped Unstable→Stable. That choice lives entirely in the
/// vendor app's private preference (see `ChannelBinding`), which our FS watcher
/// never sees (it only watches app *bundles*, not another app's prefs) and no
/// networked check re-derives on its own (the row keeps whatever channel it was
/// last resolved against until the next scheduled check, which can be hours
/// away).
///
/// This is the pure half of that fix: given a fresh `ResolvedChannel` per bound
/// app (the caller does the actual `ChannelBinding.resolve` calls, which touch
/// `CFPreferences`/disk and so aren't pure) and a fingerprint of what we saw last
/// time, decide which ids actually flipped. Kept separate from the resolving and
/// from the recheck side-effect so it's trivially testable and so the caller can
/// decide, cheaply and without any network, whether a real recheck is warranted
/// at all.
///
/// Why the *whole* `ResolvedChannel`, not just `.channel`: four of the ten bound
/// apps are feed-swap or header-keyed (see `ChannelBinding`'s doc comment) —
/// CleanShot in particular keeps `.channel == .stable` always and encodes the
/// actual entitlement entirely in `feedOverride` (a personalized, license-keyed
/// URL). Comparing `.channel` alone would see CleanShot as never changing and
/// silently drop this fix for the one app whose bug shape is "feed changed,
/// channel didn't."
///
/// Why a fingerprint and not the `ResolvedChannel` itself: `feedOverride` for
/// CleanShot embeds the user's license key in the query string
/// (`?key=<licenseKey>`, see `CleanShotChannel`). That key must never be logged
/// or persisted in the clear (existing rule, audited in `CleanShotChannel`'s doc
/// comment) — so what we cache and compare is a one-way SHA-256 digest of the
/// resolved channel's fields, never the raw URL/headers.
public enum ChannelSwitchDetector {

    /// A one-way, non-reversible fingerprint of a `ResolvedChannel`. Safe to log,
    /// persist, or compare — it never carries the license key (or anything else)
    /// a `feedOverride`/`feedHTTPHeaders` might embed.
    public static func fingerprint(_ resolved: ResolvedChannel) -> String {
        // Headers sorted so the fingerprint doesn't depend on dictionary order.
        let headerPart = resolved.feedHTTPHeaders
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let raw = [
            resolved.channel.rawValue,
            resolved.feedOverride?.absoluteString ?? "",
            headerPart,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// - Parameters:
    ///   - current: bound-app id → fingerprint of its freshly resolved channel,
    ///     for every bound app currently installed (scanned).
    ///   - lastSeen: the same shape, from the previous call.
    /// - Returns:
    ///   - changed: ids whose fingerprint differs from what we saw last time.
    ///     Empty on the very first call for an id — seeing an id for the first
    ///     time just seeds the cache, it never counts as a "switch" (an app
    ///     appearing in the scan for the first time isn't a channel change, and
    ///     without this a fresh install or app relaunch would trigger a needless
    ///     recheck of every bound app it happens to include).
    ///   - next: the cache to store for the next call — exactly `current`, so an
    ///     id no longer present (the app was uninstalled or dropped out of the
    ///     scan) is pruned and the map can't grow without bound.
    public static func changes(
        current: [String: String],
        lastSeen: [String: String]
    ) -> (changed: Set<String>, next: [String: String]) {
        var changed = Set<String>()
        for (id, fingerprint) in current {
            if let prior = lastSeen[id], prior != fingerprint {
                changed.insert(id)
            }
        }
        return (changed, current)
    }
}
