/// The keying decision behind the per-host install gate: which host an app's
/// download-concurrency cap should be charged against.
///
/// Pulled out of `AppListModel.recordEffectiveHost` / `hostInstallGate(for:appID:)`
/// so it can be executed: the model itself is not constructible in a test (its
/// `init` registers notification permissions, installs FS watchers and starts
/// timers), and this is the part that can be wrong — #671 changed it and the only
/// thing that saw that change was the whole-app build compiling.
///
/// **Why this exists at all.** Real bytes frequently arrive from a CDN after
/// redirects, so the gate must key on the server that actually serves them, not
/// the URL written in the feed — two "different" feed hosts that both bounce to
/// one CDN still end up sharing a cap, because they each learn that same CDN. The
/// cap is about the CDN, not the feed.
///
/// **Why keyed by app, not by feed host.** #671 made the vendor probe hand over a
/// `.redirect` spec's ENTRY url as `downloadURL`, so several unrelated apps now
/// share a feed host: six specs share the entry host `go.microsoft.com`
/// (Word/Excel/PowerPoint/OneDrive/Edge/m365copilot) and land on at least two
/// different CDNs — measured 2026-09-16, Word's `linkid=525134` landed on
/// `res.public.onecdn.static.microsoft` and Edge's `linkid=2093504` on
/// `msedge.sf.dl.delivery.mp.microsoft.com`; `discord.com` covers three more
/// specs the same way. A table keyed by feed host would let the first of those
/// siblings to finish write its CDN under `go.microsoft.com`, and every other
/// sibling would then be throttled against a host that never sends it a single
/// byte — the exact failure this type exists to avoid.
///
/// Keying by app instead means each app's first download still keys on its feed
/// URL's host — the redirect target can't be known before the first response,
/// and a HEAD request per install just to learn it is not worth a round trip —
/// and only that app's OWN subsequent downloads move to the host that served it.
/// Two apps whose feeds happen to bounce to the same CDN still converge on a
/// shared cap once each has downloaded once, because they each independently
/// learn that same CDN, not because one inherits the other's answer. An app whose
/// own feed host serves it different CDNs at different times is throttled on its
/// last-seen one — still better than throttling on a host that never sends it a
/// byte.
public struct EffectiveInstallHost: Equatable, Sendable {

    /// App id → the host that actually served that app's bytes, learned from a
    /// completed download. Entries are never evicted — the set of apps is tiny
    /// and bounded by the installed-app catalog, and pruning is intentionally
    /// out of scope for this type.
    private var byApp: [String: String] = [:]

    public init() {}

    /// The host this app's per-host install gate should key on: the host that
    /// served its bytes last time, if one has been learned, otherwise the feed
    /// host passed in for this call.
    public func host(forApp appID: String, feedHost: String) -> String {
        byApp[appID] ?? feedHost
    }

    /// Remember which host actually served this app's bytes, so `host(forApp:)`
    /// keys on that from the app's next download on.
    ///
    /// Both hosts are optional on purpose: the caller passes through whatever it
    /// has — `result.remote?.downloadURL?.host` and the host that actually
    /// responded — without pre-filtering, and the judgment of when that pair is
    /// worth remembering lives entirely in this guard. Nothing is recorded when
    /// either host is unknown, or when they are equal: the equal case is a host
    /// serving its own bytes directly (no redirect happened). Recording it
    /// anyway would be harmless against the SAME feed host — the next `learn`
    /// call for it, equal or not, simply overwrites the entry. The failure it
    /// actually guards against shows up later: if this app's feed URL moves to
    /// a DIFFERENT host, a stale entry equal to the OLD feed host would sit in
    /// the map and permanently shadow that new host, since `host(forApp:)`
    /// always prefers a learned entry over the host passed in. The guard keeps
    /// this map free of entries that don't yet mean anything.
    public mutating func learn(appID: String, feedHost: String?, servedBy finalHost: String?) {
        guard let feedHost, let finalHost, feedHost != finalHost else { return }
        byApp[appID] = finalHost
    }
}
