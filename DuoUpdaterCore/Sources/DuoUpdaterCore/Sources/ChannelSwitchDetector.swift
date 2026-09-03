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
        // Sorted for the same reason as the headers: a Set has no order, and the
        // fingerprint must not depend on one. Included because a binding can hold
        // `.channel` steady while moving between feed tags — BetterDisplay's
        // `pre` and `internal` happen to map to different `ReleaseChannel` cases
        // today, but nothing guarantees the next one will, and leaving the field
        // out would make such a switch invisible to `changes` — the same failure
        // the `feedOverride` component above exists to prevent for CleanShot.
        let tagPart = resolved.sparkleChannelNames.sorted().joined(separator: ",")
        let raw = [
            resolved.channel.rawValue,
            resolved.feedOverride?.absoluteString ?? "",
            headerPart,
            tagPart,
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

    /// The cache to store after a pass that may not have finished every id.
    ///
    /// `changes` returns `current` wholesale for the caller to store, which is
    /// right only when the caller then acts on every changed id. A pass that is
    /// superseded partway — the user flipped the toggle again while the first
    /// recheck was still on the network — must NOT book the ids it never got to,
    /// or the flip it did not act on is remembered as already seen and nothing
    /// compares it again. That left a row offering a prerelease to someone who
    /// had just opted out, until an unrelated event happened to trigger another
    /// pass (issue #74).
    ///
    /// So: start from `current` (seeding first sightings and pruning ids that
    /// dropped out of the scan, exactly as `changes` does), then rewind every
    /// changed-but-unfinished id to what it was, leaving it looking changed to
    /// the next pass.
    public static func booked(
        current: [String: String],
        lastSeen: [String: String],
        changed: Set<String>,
        completed: Set<String>
    ) -> [String: String] {
        var next = current
        for id in changed.subtracting(completed) {
            // `changes` only marks ids that were already in `lastSeen`, so the
            // prior value exists; the `else` is unreachable and drops the key
            // rather than inventing one.
            if let prior = lastSeen[id] { next[id] = prior } else { next.removeValue(forKey: id) }
        }
        return next
    }

    /// Whether a change in the set of running bundle identifiers is worth
    /// resolving channels for.
    ///
    /// The running-apps monitor fires for EVERY process on the machine — helpers,
    /// menu-bar utilities, anything the user opens all day — while the pass behind
    /// it reads one vendor preference per bound app, and Surge's resolver reads a
    /// plist off disk. Without this gate that ran on every such event; with it, it
    /// runs when one of the nine apps whose channel can actually change appeared
    /// or disappeared.
    ///
    /// **Two snapshots, not one identifier.** The monitor's primary source is KVO
    /// on `NSWorkspace.runningApplications`, which reports the array, not "who
    /// changed" — and the array is the better witness anyway: one event routinely
    /// covers several processes (UURemote takes UURemoteServer with it), which a
    /// single identifier cannot express.
    ///
    /// **What this deliberately does not cover:** a *second* process of an app
    /// that was already running, and the reverse — one of two processes quitting.
    /// Neither changes the identifier set, so neither is reported here. That is
    /// not a gap in channel detection: the app was running across the whole event,
    /// so a toggle flipped inside it is caught by the preference watcher
    /// (`ChannelBinding.preferenceWatchPaths`), which is the path the ordinary
    /// "flip it and leave the app open" flow already relies on.
    ///
    /// An empty change set returns false: the monitor also fires for changes that
    /// move no identifier at all (a second copy of an app already running), and
    /// there is nothing there for a channel to have switched behind.
    public static func isWorthRechecking(
        runningBundleIDsChangedFrom previous: Set<String>,
        to current: Set<String>
    ) -> Bool {
        // Bundle ids are case-insensitive, and TablePlus really does ship
        // `com.tinyapp.TablePlus` while its prefs live under the lowercased
        // domain — a case-sensitive gate would silently skip it.
        previous.symmetricDifference(current)
            .contains { ChannelBinding.boundBundleIDs.contains($0.lowercased()) }
    }
}
