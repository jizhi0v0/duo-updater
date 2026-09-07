import Foundation

/// Select vendor notes using the installed copy's provenance, even when an
/// update lookup has not answered or has failed.
public enum ChangelogRecipeSelection {
    public static func recipe(for result: UpdateResult) -> ChangelogRecipe? {
        guard !result.app.isMASApp, result.remote?.appStore == nil else { return nil }
        return ChangelogRecipeRegistry.recipe(
            forBundleID: result.app.bundleID, channel: result.effectiveReleaseChannel,
            version: targetVersion(for: result))
    }

    /// Lookup, fetching and caching must all use the same version window.
    public static func targetVersion(for result: UpdateResult) -> String? {
        result.remote?.displayVersion ?? result.app.shortVersion
    }

    /// The page the notes pane falls back to — and the header links out to —
    /// when no recipe applies.
    ///
    /// This exists because `recipe(for:)` is only HALF of "a store copy must not
    /// be shown another distribution's release notes". Refusing the recipe stops
    /// the *parsed* vendor notes; the view then falls through to a URL, and one
    /// of the two candidates for that URL comes from `ChangelogCatalog` — a
    /// second registry of hand-curated **vendor** pages, keyed by bundle id
    /// alone, with no provenance in it. So a catalog entry for a bundle id that
    /// also ships on the store would put the vendor's changelog back in front of
    /// a store copy through the web view, which is #388 verbatim, one registry
    /// over. No entry does that today (measured 2026-09-07: the two registries
    /// overlap on app.chatwise, com.electron.ollama, com.longbridge.app.desktop,
    /// com.mitchellh.ghostty and net.imput.helium, and `com.tencent.xinWeChat`
    /// has no catalog entry at all) — but the catalog's whole purpose is "the
    /// source shipped no notes", which is exactly the failed-lookup state, so
    /// this is the next entry away rather than hypothetical.
    ///
    /// The catalog half is gated; the `remote` half is not, and deliberately:
    /// `UpdateChecker` only lets a source with `answersAppStoreCopies` near a
    /// store copy, and `MacAppStoreSource` is the only one, so a store copy's
    /// `changelogURL` is a store listing by construction. Gating it here would
    /// be guessing at a property the checker already guarantees — and if that
    /// guarantee ever breaks, it should break loudly there, not be papered over
    /// here.
    ///
    /// A store LISTING in the catalog survives the gate, because for a store
    /// copy that page is the right answer, not the wrong one: `net.whatsapp.whatsapp`
    /// is an iOS-on-Mac app (hence always `isMASApp`) whose entry exists
    /// precisely so the store page shows while the check is still running. A
    /// blanket `!isMASApp` would delete that entry's only reason to exist.
    public static func fallbackPage(for result: UpdateResult) -> FallbackPage {
        if let fromSource = result.remote?.changelogURL {
            return FallbackPage(url: fromSource, origin: .remote)
        }
        guard let curated = ChangelogCatalog.url(forBundleID: result.app.bundleID) else {
            return FallbackPage(url: nil, origin: .none)
        }
        guard !result.app.isMASApp || isAppStoreListing(curated) else {
            return FallbackPage(url: nil, origin: .catalogWithheld)
        }
        return FallbackPage(url: curated, origin: .catalog)
    }

    /// Apple's own listing hosts, matched on the WHOLE host rather than a suffix:
    /// `apps.apple.com.example.invalid` is a name its owner can point anywhere,
    /// and a suffix test would call it a store page.
    static func isAppStoreListing(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let bare = host.count > 1 && host.hasSuffix(".") ? String(host.dropLast()) : host
        return bare == "apps.apple.com" || bare == "itunes.apple.com"
    }

    /// Which link of the fallback chain answered, kept beside the URL so the
    /// pane's log line and the URL it reports cannot disagree — recomputing the
    /// chain a second time at the call site is how the catalog half came to
    /// carry a different rule from the recipe half in the first place.
    public struct FallbackPage: Sendable, Equatable {
        public let url: URL?
        public let origin: Origin

        public enum Origin: String, Sendable, Equatable {
            /// Neither candidate produced a URL.
            case none
            /// The update source supplied one (`RemoteVersion.changelogURL`).
            case remote
            /// `ChangelogCatalog`'s curated page.
            case catalog
            /// `ChangelogCatalog` had a vendor page, and this copy came from the
            /// Mac App Store — so it was withheld rather than shown. Distinct
            /// from `.none` because "we had a page and refused it" is the state
            /// worth seeing in a report; `.none` reads as "nobody publishes one".
            case catalogWithheld
        }
    }
}
