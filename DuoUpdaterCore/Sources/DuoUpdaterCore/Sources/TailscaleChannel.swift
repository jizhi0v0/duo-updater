import Foundation

/// Tailscale (`io.tailscale.ipn.macsys`, the standalone "macsys" build, NOT the
/// Mac App Store one) ships THREE public tracks the "Update to:" GUI dropdown
/// lets a user opt into:
///   * stable             → `pkgs.tailscale.com/stable`             (even minor, e.g. 1.98.x)
///   * release candidate  → `pkgs.tailscale.com/release-candidate/` (verified 2026-08-21, HTTP
///     200 + the same JSON shape as the other two tracks)
///   * unstable           → `pkgs.tailscale.com/unstable`           (odd  minor, e.g. 1.99.x)
/// `pkgs.tailscale.com/rc` 404s — that guessed path name is just wrong, NOT
/// evidence the track doesn't exist. The real path is `release-candidate`, found
/// by reading the value out of the app's own preferences rather than guessing
/// URLs (see below).
///
/// All three tracks share one bundle id and one app name; the installed
/// `CFBundleShortVersionString` is a plain semver with no channel suffix, so the
/// only reliable local signal is the app's own opt-in toggles, stored in
/// UserDefaults as two Bools:
///   * `UnstableUpdatesEnabled` (1 → unstable)
///   * `RCUpdatesEnabled`       (1 → release candidate; absent until the user has
///     switched to RC at least once)
/// We read them like OrbStack's `updates_optinChannel` and let the VendorProbe
/// channel gate route the install to the matching `pkgs.tailscale.com/<track>`
/// endpoint.
///
/// The two keys were verified mutually exclusive by directly reading
/// `~/Library/Preferences/io.tailscale.ipn.macsys.plist` through all three GUI
/// dropdown positions on 2026-08-21/22, on the same machine, back to back:
///     Stable             → UnstableUpdatesEnabled absent,  RCUpdatesEnabled absent
///     Release candidates → UnstableUpdatesEnabled 0,       RCUpdatesEnabled 1
///     Unstable versions  → UnstableUpdatesEnabled 1,       RCUpdatesEnabled 0
/// Switching dropdown positions doesn't just add the newly-chosen key, it
/// actively WRITES 0 into the one being left (RCUpdatesEnabled goes from 1 to a
/// literal `0`, not removed, when the user moved from RC to Unstable) — so the
/// two keys behave as one client-maintained tri-state, not independent toggles
/// that could drift apart from normal use.
///
/// Safety: a missing/unreadable key falls back to `.stable` — the shipped
/// default — so we never push a non-stable build at someone who didn't opt in.
enum TailscaleChannel {
    static let bundleID = "io.tailscale.ipn.macsys"

    /// Map the two flags to a resolution. Pure and tested. No feed override:
    /// each track is its own VendorProbe recipe, picked by the channel gate —
    /// not a feed swap.
    ///
    /// `unstableEnabled` is checked first, so a hypothetical on-disk state with
    /// both flags true would resolve to `.unstable`. This is PURELY DEFENSIVE —
    /// the empirical three-state check above found no GUI path that produces
    /// it, and there is no evidence it can happen. It exists only so an
    /// out-of-band write (a bug in a future Tailscale version, manual
    /// `defaults write`, a corrupted plist) can't silently escalate someone
    /// past what they opted into: `.unstable` is the noisier of the two
    /// non-stable tracks, so if the keys ever did disagree, resolving to the
    /// one further from stable is the same "never surprise the user with a
    /// quieter build than the noisiest thing they might have picked" bias the
    /// rest of this file already uses (`?? false` on a bad read still won't
    /// escalate PAST stable). It is not proof of a real ordering — just a
    /// documented tie-break for a case that has not been observed.
    static func resolve(unstableEnabled: Bool, rcEnabled: Bool) -> ResolvedChannel {
        if unstableEnabled { return ResolvedChannel(channel: .unstable) }
        if rcEnabled { return ResolvedChannel(channel: .rc) }
        return ResolvedChannel(channel: .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(unstableEnabled: readUnstableEnabled(), rcEnabled: readRCEnabled())
    }

    /// Read `UnstableUpdatesEnabled` from Tailscale's preferences. Returns false
    /// (stable) when the key is absent — the conservative default.
    static func readUnstableEnabled() -> Bool {
        readBoolPref("UnstableUpdatesEnabled")
    }

    /// Read `RCUpdatesEnabled` from Tailscale's preferences. Returns false
    /// (stable) when the key is absent OR explicitly 0 — both are observed on
    /// real installs (see the three-state check above: absent on Stable,
    /// explicitly written back to 0 when the user leaves RC for Unstable).
    static func readRCEnabled() -> Bool {
        readBoolPref("RCUpdatesEnabled")
    }

    private static func readBoolPref(_ key: String) -> Bool {
        (CFPreferencesCopyAppValue(key as CFString,
                                   bundleID as CFString) as? NSNumber)?.boolValue ?? false
    }
}
