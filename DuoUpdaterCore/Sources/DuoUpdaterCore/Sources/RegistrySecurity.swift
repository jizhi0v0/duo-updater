import Foundation

/// Which apps' update paths carry a credential, and therefore must never be
/// swept by an automated verifier that publishes what it sees.
///
/// The list lives here, in the core beside the registries, rather than in the
/// verification tool. A tool-side blocklist drifts: someone adds a recipe for a
/// licensed feed, the tool doesn't know, and the key ends up in a public issue.
/// Here it sits next to the thing it describes, and the test suite can assert
/// the invariant directly.
///
/// **Today no recipe in `VendorProbeRegistry` is credential-bearing.** The two
/// credentialed paths in the app reach their feeds by other routes:
///
///  • **CleanShot** — `ChannelBinding` reads the machine's activation key and
///    hands `AppScanner` a personalized Sparkle feed URL with the key in the
///    query string. It never appears in a probe recipe.
///  • **Alcove** — `AlcoveUpdateSource` exchanges a license key for a bearer
///    token entirely on its own; it is not an entry in any registry. (The
///    `com.henrikruscon.Alcove` entry that *is* in `VendorProbeRegistry` is the
///    public, unauthenticated CDN mirror.)
///
/// So this type is a guard against future drift, not a filter for the present —
/// which is exactly when a guard is cheap to add.
public enum RegistrySecurity {

    /// Bundle ids whose *registry entry* would carry a secret. A verifier must
    /// skip these, and must never log, publish, or forward any URL, header, or
    /// body associated with them.
    ///
    /// Keyed on the bundle id because that is what a registry entry has — which
    /// means it can only express "this app has no safe recipe", not "this app
    /// has one safe recipe and one unsafe one". **Alcove is deliberately absent
    /// for exactly that reason**: `com.henrikruscon.Alcove` appears in
    /// `VendorProbeRegistry` as the public, unauthenticated CDN mirror, which is
    /// safe to sweep, while the credentialed path lives in `AlcoveUpdateSource`
    /// and is in no registry at all. Listing the bundle id here would skip the
    /// harmless recipe and protect nothing; the invariant that actually protects
    /// Alcove is `theAuthenticatedAlcoveSourceIsInNoRegistry`.
    public static let credentialBearingBundleIDs: Set<String> = [
        CleanShotChannel.bundleID,          // personalized appcast, key in the query
    ]

    /// Header names some apps inject that are *not* secrets, but which are still
    /// scrubbed from published output on principle — an injected header is
    /// exactly the shape a secret takes, and the reader can't tell by looking.
    ///
    /// TablePlus's `X-Tiny-Beta-Update: true` is the only member: a literal flag
    /// that opts its feed into the beta track.
    public static let nonSecretInjectedHeaders: Set<String> = ["x-tiny-beta-update"]

    public static func isCredentialBearing(bundleID: String) -> Bool {
        credentialBearingBundleIDs.contains(bundleID)
    }
}
