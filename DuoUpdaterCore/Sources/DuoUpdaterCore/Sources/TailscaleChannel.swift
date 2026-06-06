import Foundation

/// Tailscale (`io.tailscale.ipn.macsys`, the standalone "macsys" build, NOT the
/// Mac App Store one) ships two public tracks the GUI lets a user opt into:
///   * stable   → `pkgs.tailscale.com/stable`   (even minor, e.g. 1.98.x)
///   * unstable → `pkgs.tailscale.com/unstable` (odd  minor, e.g. 1.99.x)
/// (`pkgs.tailscale.com/rc` 404s — there's no third consumer track here.)
///
/// Both tracks share one bundle id and one app name; the installed
/// `CFBundleShortVersionString` is a plain semver with no channel suffix, so the
/// only reliable local signal is the app's own opt-in toggle, stored in
/// UserDefaults as `UnstableUpdatesEnabled` (Bool: 1 → unstable). We read it like
/// OrbStack's `updates_optinChannel` and let the VendorProbe channel gate route
/// the install to the matching `pkgs.tailscale.com/<track>` endpoint.
///
/// Safety: a missing/unreadable key falls back to `.stable` — the shipped
/// default — so we never push an unstable build at someone who didn't opt in.
enum TailscaleChannel {
    static let bundleID = "io.tailscale.ipn.macsys"

    /// Map the `UnstableUpdatesEnabled` flag to a resolution. Pure and tested.
    /// No feed override: each track is its own VendorProbe recipe, picked by the
    /// channel gate — not a feed swap.
    static func resolve(unstableEnabled: Bool) -> ResolvedChannel {
        ResolvedChannel(channel: unstableEnabled ? .unstable : .stable)
    }

    static func resolveCurrent() -> ResolvedChannel {
        resolve(unstableEnabled: readUnstableEnabled())
    }

    /// Read `UnstableUpdatesEnabled` from Tailscale's preferences. Returns false
    /// (stable) when the key is absent — the conservative default.
    static func readUnstableEnabled() -> Bool {
        (CFPreferencesCopyAppValue("UnstableUpdatesEnabled" as CFString,
                                   bundleID as CFString) as? NSNumber)?.boolValue ?? false
    }
}
