import Foundation

/// Getting a new developer session from Apple without the user, once the old
/// one has ended.
///
/// The developer site's session (`myacinfo`) ends on Apple's side after some
/// hours; the sign-in site's own session (`acsso`, on `idmsa.apple.com`) can
/// outlive it. While `acsso` holds, loading the developer site sends the page
/// through `idmsa` and straight back with a new `myacinfo` — no password, no
/// click, and no window needed. Measured 2026-09-23 with a throwaway probe on
/// its own store: the web view in no window, signed in again in ~6 s; `acsso`
/// alone was enough, and every run without it stayed on the password form
/// (25 s), whatever else was kept — the 30-day "trust this device" and 1-year
/// account-name cookies included. The same morning a real session, ~14 h after
/// its sign-in and hours after Apple ended its `myacinfo`, came back this way.
///
/// How long Apple honours `acsso` is not published and not yet measured. When
/// it has ended too, the page stays on the password form and the caller gives
/// up at `timeout`.
public enum AppleDeveloperSessionRenewal {
    /// Where the hidden page starts — the same page the sign-in window opens.
    public static let startURL = URL(string: "https://developer.apple.com/account")!

    /// The measured renewal took ~6 s; a page still on the sign-in form after
    /// this is the form waiting for a password.
    public static let timeout: Duration = .seconds(30)

    /// The user's switch for all of this (Settings → Xcode), in the app's
    /// defaults. On unless turned off.
    public static let enabledKey = "RenewAppleDeveloperSession"

    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Whether to try a renewal after Apple answered `verdict`: only when the
    /// user left background renewal on (`enabled`), only when Apple said the
    /// session has ended, only once per expiry, and never for a check that runs
    /// while the user is signing in themselves (`allowed` false) — a hidden page
    /// there would compete with the window for the same store.
    public static func shouldTry(
        verdict: AppleDeveloperSessionProbe.Verdict, alreadyTried: Bool, allowed: Bool, enabled: Bool
    ) -> Bool {
        enabled && allowed && !alreadyTried && verdict == .expired
    }

    /// Whether a page that finished loading at `host` is back on the developer
    /// site — the only way the round trip through `idmsa` ends signed in. Exact
    /// host: `idmsa.apple.com` (the form) and anything else are not.
    public static func hasLanded(host: String?) -> Bool {
        host?.lowercased() == "developer.apple.com"
    }
}
