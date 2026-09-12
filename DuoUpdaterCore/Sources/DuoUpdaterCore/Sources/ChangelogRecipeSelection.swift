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
    /// over. No entry does that today — `catalogAndRecipeOverlapIsWhatTheCommentSays`
    /// pins the overlap so this sentence cannot quietly stop being true — but the
    /// catalog's whole purpose is "the source shipped no notes", which is exactly
    /// the failed-lookup state, so this is the next entry away rather than
    /// hypothetical.
    ///
    /// The catalog half is gated; the `remote` half is not, and deliberately.
    /// For every `UpdateSource`, `UpdateChecker` only lets one whose
    /// `answersAppStoreCopies` is true near a store copy — the
    /// `if app.isMASApp, !source.answersAppStoreCopies { continue }` guard in its
    /// source loop, and `UpdateChecker.apps(_:visibleTo:)` for the batch paths
    /// (named rather than cited by line number: the two this comment used to give
    /// had both moved) — and `MacAppStoreSource` is the only
    /// one — so a store copy's `changelogURL` is a store listing. ⚠️ That is a
    /// property of the SOURCE LOOP, not of `runSources` as a whole: the Toolbox
    /// and TestFlight branches return before the loop and pass neither gate. The
    /// Toolbox one does carry a vendor `changelogURL`, so a hypothetical
    /// Toolbox-managed store copy would reach a JetBrains page through the
    /// ungated half. The checker's own comment says a JetBrains IDE is never a
    /// MAS app, so nothing reaches it today; it is named here because "by
    /// construction" was the wrong word for it, not because it is live.
    ///
    /// A store LISTING in the catalog survives the gate, because for a store copy
    /// that page is the right answer rather than the wrong one — `net.whatsapp.whatsapp`
    /// is the entry in hand, added so the store page shows while the check is
    /// still in flight. Gating on the URL rather than on the entry is what makes
    /// that safe without an allowlist.
    ///
    /// ⚠️ **The inverse case is real and is NOT addressed here.** WhatsApp also
    /// ships a Developer ID build from `web.whatsapp.com` (see its
    /// `VendorProbeRecipe`, Team `57T9237FN3`, verified 2026-08-09), and a copy
    /// installed that way has no `_MASReceipt` and no `WrappedBundle`, so
    /// `isMASApp` is false for it and it is handed the App Store listing's notes
    /// — the mirror image of #388. That predates this function and survives it
    /// unchanged; it is written down rather than reasoned away because an earlier
    /// draft of this comment claimed WhatsApp is "always `isMASApp`", which is
    /// false, and that claim is what made the case invisible.
    public static func fallbackPage(for result: UpdateResult) -> FallbackPage {
        if let fromSource = result.remote?.changelogURL { return .fromSource(fromSource) }
        guard let curated = ChangelogCatalog.url(forBundleID: result.app.bundleID) else {
            return .none
        }
        guard !result.app.isMASApp || isAppStoreListing(curated) else { return .withheld }
        return .fromCatalog(curated)
    }

    /// Apple's own listing hosts, matched on the WHOLE host.
    ///
    /// Both ends matter and they fail differently. A suffix test
    /// (`hasSuffix("apps.apple.com")`) admits `notapps.apple.com`, which anyone
    /// can register; a prefix test or `contains` admits
    /// `apps.apple.com.example.invalid`, where the store's name is a label
    /// inside a domain its owner points wherever they like. Equality is the only
    /// test that refuses both, and `onlyTheWholeHostCountsAsAStoreListing` pins
    /// one host for each.
    ///
    /// Every way this can be wrong is safe: a host it fails to recognise makes a
    /// store copy fall through to `.withheld` (no page rather than the wrong
    /// one), and the one host shape it over-accepts — `https://evil.com@apps.apple.com/`,
    /// whose `URL.host` is the store — is refused afterwards by
    /// `ChangelogURLPolicy`'s credential guard before any web view sees it.
    static func isAppStoreListing(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let bare = host.count > 1 && host.hasSuffix(".") ? String(host.dropLast()) : host
        return bare == "apps.apple.com" || bare == "itunes.apple.com"
    }

    /// Which link of the fallback chain answered, carrying the URL it answered
    /// with so the pane's log line cannot name one and show the other.
    ///
    /// An enum with the URL attached rather than a struct of `(URL?, origin)`:
    /// the whole reason this type exists is that the token must not lie about
    /// the URL, and a struct lets `.withheld` be built with a URL in it. Here
    /// that pairing is unrepresentable rather than merely conventional.
    public enum FallbackPage: Sendable, Equatable {
        /// Neither candidate produced a URL.
        case none
        /// The update source supplied one (`RemoteVersion.changelogURL`).
        case fromSource(URL)
        /// `ChangelogCatalog`'s curated page.
        case fromCatalog(URL)
        /// `ChangelogCatalog` had a vendor page, and this copy came from the Mac
        /// App Store — so it was withheld rather than shown. Distinct from
        /// `.none` because "we had a page and refused it" is the state worth
        /// seeing in a report; `.none` reads as "nobody publishes one".
        case withheld

        public var url: URL? {
            switch self {
            case .fromSource(let url), .fromCatalog(let url): return url
            case .none, .withheld: return nil
            }
        }

        /// Fixed English for a `Log.` line, lowercase to match the tokens already
        /// in this pane's log format and `ChangelogURLPolicy.RejectionReason.logToken`.
        /// Never localized, for the reason given there: a log line is read next to
        /// the source, and translating it breaks grepping across reports.
        public var logToken: String {
            switch self {
            case .none: return "none"
            case .fromSource: return "remote"
            case .fromCatalog: return "catalog"
            case .withheld: return "catalog-withheld"
            }
        }
    }
}
