import Foundation

/// What one live read of a Sparkle appcast learned — fetch and parse only, no
/// verdict. `duo verify`'s feed sweep (`Verify.classifyFeed`) decides what it
/// means; keeping the two apart is the same split `AppStoreProbeObservation`
/// and `Verify.classifyAppStore` use, so the judgement can be exercised
/// offline against fixtures.
public struct SparkleFeedReading: Sendable {
    /// `<item>` elements the parser recognised, before any filter.
    public let itemCount: Int
    /// How many of them survive `SparkleAppcastSource.usableItems` — the
    /// channel, minimum/maximum-OS and architecture filters — for a DEFAULT
    /// CHANNEL install on the machine running the sweep. Zero here is the
    /// failure the whole sweep exists for: it is what `latestVersion` turns
    /// into a nil, which every caller renders as "up to date".
    public let usableCount: Int
    /// `sparkle:shortVersionString` of the newest usable item, i.e. the
    /// marketing string this feed would put in front of a user.
    public let headShortVersion: String?
    /// `sparkle:version` of the same item — Sparkle's canonical build key.
    public let headBuildVersion: String?
    /// Its `<enclosure url>`, already resolved against the feed's own address
    /// the way `SparkleAppcastParser` does for the live path (Helium publishes
    /// relative enclosures, so an unresolved one is not a hypothetical).
    public let headEnclosure: URL?
    /// Items declaring a non-empty `sparkle:maximumSystemVersion`. Not a
    /// verdict and not a count of what was filtered: it is the one hint
    /// `latestVersion` itself logs when a feed goes empty on it, repeated here
    /// so the sweep's message can point the same way rather than re-deriving a
    /// filter predicate that would then be free to drift from the real one.
    public let itemsDeclaringMaximumSystemVersion: Int
    /// The OS version the filters were evaluated against, so a report read on
    /// another machine says which Mac's answer it is.
    public let osVersion: String
    /// Bytes of appcast fetched.
    public let byteCount: Int
}

/// A feed read that never got as far as parsing.
public enum SparkleFeedReadFailure: Error, Sendable, Equatable {
    /// The host answered, with something outside 2xx.
    case badStatus(Int)
}

public extension SparkleAppcastSource {

    /// Fetch one appcast and report its shape, without an installed copy to
    /// hang it on.
    ///
    /// This is `duo verify`'s read of a `SparkleFeedCatalog` entry. The catalog
    /// is the one address table nothing on a schedule has ever fetched (#324):
    /// its fill-in half invents an address the bundle never states, and its
    /// superseding half overrides one the bundle does state, and both halves
    /// fail silently — a feed that dies, moves, or reshapes its items produces
    /// a nil out of `latestVersion`, which is indistinguishable from "you are
    /// up to date" everywhere it is displayed.
    ///
    /// **Whose answer this is.** `usableItems` needs an installed copy to
    /// decide which channels are allowed, and the sweeping machine is not
    /// required to have one — `VerifyOptions.useInstalled` is off on a CI
    /// runner for exactly that reason, so requiring a copy would switch the
    /// check off where nobody is watching the apps anyway.
    /// So it asks the question the catalog's promise is actually about: what
    /// would a FRESH DEFAULT-CHANNEL install see today? The probe app carries
    /// no version, so `channel(ofInstalled:)` matches nothing and
    /// `allowedChannels` returns the default channel alone — the floor every
    /// real install is at or above. A beta-tagged item is therefore not
    /// counted as usable, which is correct for this question and worth knowing
    /// when reading a count back (Helium's feed publishes one).
    ///
    /// Throws only on transport failure; a non-2xx comes back as
    /// `.failure(.badStatus)` so the caller can report the code instead of
    /// unwrapping a localized string.
    func readFeed(
        _ feedURL: URL, bundleID: String
    ) async throws -> Result<SparkleFeedReading, SparkleFeedReadFailure> {
        let request = Self.feedRequest(url: feedURL, headers: [:])
        let (data, response) = try await session.versionFeedData(
            for: request, label: "Sparkle verify \(bundleID)")
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return .failure(.badStatus(http.statusCode))
        }

        let items = SparkleAppcastParser.parse(data, relativeTo: feedURL)
        let osVersion = Self.numericSystemVersion()
        let usable = Self.usableItems(
            for: Self.probeApp(bundleID: bundleID, feedURL: feedURL),
            from: items, osVersion: osVersion)
        let head = usable.first
        return .success(SparkleFeedReading(
            itemCount: items.count,
            usableCount: usable.count,
            headShortVersion: head?.shortVersionString,
            headBuildVersion: head?.version,
            headEnclosure: head?.enclosureURL,
            itemsDeclaringMaximumSystemVersion:
                items.filter { $0.maximumSystemVersion?.isEmpty == false }.count,
            osVersion: osVersion,
            byteCount: data.count))
    }

    /// The stand-in the filters are evaluated for. Deliberately versionless and
    /// non-authoritative about its channel: those are exactly the two inputs
    /// that would let the sweeping machine's own installed copy change the
    /// answer, and a sweep whose verdict moves with what happens to be in
    /// `/Applications` is not one anybody can act on.
    private static func probeApp(bundleID: String, feedURL: URL) -> InstalledApp {
        InstalledApp(
            name: bundleID, bundleID: bundleID,
            shortVersion: nil, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
            isMASApp: false, sparkleFeedURL: feedURL,
            releaseChannel: .stable, channelIsAuthoritative: false)
    }
}
