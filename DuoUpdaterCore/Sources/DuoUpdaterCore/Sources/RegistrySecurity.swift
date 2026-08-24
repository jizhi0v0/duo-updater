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
/// A second dimension arrived with the Codex recipe: an app that is perfectly
/// safe to sweep, reading one non-credential value out of a file that also holds
/// tokens. That is not "this app carries a secret", it is "this read must stay
/// exactly the read it is", so it is allow-listed separately below in
/// `credentialBearingFileReads`.
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

    /// Local files that hold real credentials but also hold one value a recipe
    /// legitimately needs, mapped to the exact reads allowed out of each.
    ///
    /// `credentialBearingBundleIDs` answers "may this app be swept at all".
    /// This answers a narrower question the same class of mistake hides behind:
    /// the app is fine to sweep, the endpoint keys on a value that lives in a
    /// file which ALSO holds tokens, and nothing in `ProbeIdentity`'s types
    /// stops a later recipe from reaching for a different key in that same file.
    ///
    /// `~/.codex/auth.json` is the instance and it is not a hypothetical hazard:
    /// `OPENAI_API_KEY` sits at its TOP LEVEL, so `.jsonKey("OPENAI_API_KEY")`
    /// would read it, and the character backstop would wave it through — an
    /// `sk-` key is URL-unreserved end to end. What makes the one allowed read
    /// safe is not the file, it is the path: `.jwtClaim` walks two literal paths
    /// to one claim and can return nothing else.
    ///
    /// So this allow-lists the READ, not the file. Keyed by
    /// `ProbeIdentity.displayPath`, valued by `ProbeIdentity.readPath`; every
    /// read in `VendorProbeRecipe.localReads` that points into one of these files
    /// must be listed here, which `RegistrySecurityTests` asserts against the
    /// registry as it stands. Derived from `localReads` rather than from
    /// `identities` on purpose — the day the plan moved from one to the other,
    /// an enumerated guard would have gone quiet instead of red.
    public static let credentialBearingFileReads: [String: Set<String>] = [
        "~/.codex/auth.json": [
            // The rollout track ChatGPT's appcast keys on. Authenticates
            // nothing; see the Codex recipe in `VendorProbeRegistry` for why it
            // is needed and what it can and cannot tell us.
            "tokens.access_token → https://api.openai.com/auth.chatgpt_plan_type",
        ],
    ]
}
