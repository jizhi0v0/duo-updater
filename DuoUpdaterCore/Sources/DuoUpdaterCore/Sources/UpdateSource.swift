import Foundation

/// A strategy for discovering the latest available version of an app.
/// Sources are tried in priority order; the first one that can answer wins.
public protocol UpdateSource: Sendable {
    /// Human-readable name, shown in the UI ("Sparkle", "App Store", ...).
    var name: String { get }

    /// Return the latest version this source knows about for `app`, or nil if
    /// this source doesn't apply to the app (e.g. no Sparkle feed). Throw on a
    /// real failure (network/parse) so the engine can surface an error rather
    /// than silently treating it as "not applicable".
    func latestVersion(for app: InstalledApp) async throws -> RemoteVersion?

    /// Whether this source may answer for a copy installed from the Mac App
    /// Store. Almost always no, which is why the default is false.
    ///
    /// `UpdateChecker` skips every source that says no when the row is
    /// `isMASApp`, so a store copy is answered by the store or by nobody. The
    /// alternative — relying on `MacAppStoreSource` being first in
    /// `SourceStack` — does not hold, because the checker falls through on a
    /// THROWN error as well as on a miss, and the store lookup does both (a
    /// region-locked storefront, a lookup that 404s).
    ///
    /// Not hypothetical: 94a1842 (2026-08-23) recorded WhatsApp offering
    /// 26.32.75 → 26.33.19, the store build against the direct download from
    /// web.whatsapp.com, whose recipe carries a dmg install spec — so Update
    /// would have replaced the store copy, `_MASReceipt`, sandbox entitlements
    /// and the store's own update path with it. ⚠️ That row is gone: this
    /// machine's WhatsApp is now the Developer ID build, so nothing here can
    /// reproduce it end to end. The case is cited from that commit, not
    /// re-measured.
    ///
    /// **The default is the safe answer, deliberately.** Three sources learned
    /// this one at a time (Homebrew at the start, GitHub 2026-08-20 via
    /// LocalSend, the vendor probe 2026-08-23 via WhatsApp) and four were never
    /// revisited, because each fix went where the bite was. A property that has
    /// to be opted OUT of cannot be missed the same way — the same reason
    /// `RowActions.live` gives its callers no defaults.
    var answersAppStoreCopies: Bool { get }

    /// Optional hook: given the apps from a scan that this source is allowed to
    /// act on — the whole list, minus store copies unless
    /// `answersAppStoreCopies` — do whatever
    /// cheaper-in-bulk work would help `latestVersion(for:)` avoid a request it
    /// would otherwise make per app. `UpdateChecker.check(_ apps:)` calls this
    /// once, for every source, before its per-app fan-out starts — the only
    /// point that has the whole list in hand at once. Default is a no-op, so
    /// only a source that actually has a batched endpoint needs to implement it
    /// (see `MacAppStoreSource.prewarm`, which batches iTunes lookups).
    func prewarm(_ apps: [InstalledApp]) async

    /// Optional hook: drop any memoized answer this source is holding for
    /// exactly `apps`, so the next `latestVersion(for:)` call for each of them
    /// hits the network instead of a stale cache. Same narrowing as `prewarm`:
    /// `apps` is what this source may act on, not everything being checked — a
    /// source that declines store copies is never asked to invalidate one,
    /// because it will never be asked to answer one either. `UpdateChecker.check(_:freshening:)`
    /// calls this, for every source, before the per-app fan-out — and,
    /// defensively, before `prewarm`; see that call site for why no source
    /// today makes that ordering observable. Default
    /// is a no-op — but read that as "opt in", NOT as "every memoizing source
    /// already implements this". An earlier version of this comment said the
    /// latter and it was false.
    ///
    /// Implemented by `MacAppStoreSource`, which drops `AppStorePageCache`
    /// entries. DELIBERATELY NOT implemented by `HomebrewCaskSource`, which
    /// memoizes far harder: `HomebrewCaskCatalog.shared` holds a parsed index
    /// with a SIX-hour TTL and short-circuits the request entirely, so a user
    /// who reads a cask's release announcement can be told the old version for
    /// up to six hours with no way to insist. That is a real hole and it is
    /// left open on purpose: the index arrives as one blob, measured at
    /// 2007 KB a fetch (`formulae.brew.sh`, 2026-09-05), so dropping it on
    /// every per-row recheck — a path that also fires from FSEvents and
    /// running-app changes — would cost more than this whole branch saves.
    /// Closing it properly means fetching the single cask rather than the
    /// index; nobody has built that.
    func invalidateMemo(for apps: [InstalledApp]) async
}

public extension UpdateSource {
    var answersAppStoreCopies: Bool { false }
    func prewarm(_ apps: [InstalledApp]) async {}
    func invalidateMemo(for apps: [InstalledApp]) async {}
}
