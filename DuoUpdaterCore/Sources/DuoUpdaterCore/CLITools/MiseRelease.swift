import Foundation

/// What `mise self-update` would install: the release its own rule picks.
///
/// `mise self-update` with no version (`eligible_self_update_version`,
/// `src/cli/version.rs`, v2026.10.6) reads `https://mise.jdx.dev/releases.tsv` —
/// one `v<version>\t<epoch seconds>` line per release, 650 lines on 2026-10-09,
/// newest first (`v2026.10.6\t1791540753`) — keeps the releases published at or
/// before *now minus the minimum release age*, and takes the highest by
/// release order. That age is `self_update.minimum_release_age`, else
/// `minimum_release_age`, else **24 hours**. mise ships about daily, so the
/// newest release is usually not the one it installs: on 2026-10-09 at 18:47
/// UTC 2026.10.6 (55 minutes old) and 2026.10.5 (14 h) were held back and
/// `mise self-update` would install 2026.10.4.
///
/// This applies mise's default, 24 hours, and reports that release as the
/// latest, so the row never offers a release `mise self-update` would refuse
/// to install. A user who set a longer age in mise's own config can see an
/// update the command then declines; the updater reads that as nothing having
/// changed (`MiseUpdater`). The config is not read: it is a TOML file mise
/// layers from several places, and `self_update.*` can also come from the
/// environment, which a GUI app does not see.
///
/// The answer carries `cache-control: max-age=300` and an `ETag`, hence the
/// version-feed cache policy.
public struct MiseRelease: Sendable {

    public static let index = URL(string: "https://mise.jdx.dev/releases.tsv")!

    /// mise's default minimum release age (`effective_release_age`).
    public static let minimumReleaseAge: TimeInterval = 24 * 60 * 60

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        case unreadable
        /// No release in the index is old enough.
        case noneEligible

        public var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .unreadable: return "the release index could not be read"
            case .noneEligible: return "no release is past mise's minimum release age"
            }
        }
    }

    typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch
    let now: @Sendable () -> Date

    public init(session: URLSession = .updates) {
        self.init(
            fetch: { url in
                var request = URLRequest(url: url)
                request.cachePolicy = URLRequest.versionFeedCachePolicy
                request.timeoutInterval = 15
                let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
                return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            },
            now: { Date() })
    }

    /// The seam tests use: no network, and a fixed clock.
    init(fetch: @escaping Fetch, now: @escaping @Sendable () -> Date) {
        self.fetch = fetch
        self.now = now
    }

    public func latest() async throws -> String {
        let (data, status) = try await fetch(Self.index)
        guard status == 200 else { throw Failure.http(status) }
        let cutoff = now().addingTimeInterval(-Self.minimumReleaseAge)
        return try Self.eligible(in: data, cutoff: cutoff)
    }

    /// mise's `select_eligible_release`: every line must be `v<version>` and an
    /// epoch, or the index is refused whole; of those published at or before
    /// `cutoff`, the highest version.
    static func eligible(in data: Data, cutoff: Date) throws -> String {
        var best: (key: [Int], version: String)?
        for raw in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = raw.split(whereSeparator: \.isWhitespace)
            if fields.isEmpty { continue }
            guard fields.count == 2, fields[0].hasPrefix("v"), let seconds = TimeInterval(fields[1]) else {
                throw Failure.unreadable
            }
            let version = String(fields[0].dropFirst())
            guard let key = key(version) else { throw Failure.unreadable }
            guard Date(timeIntervalSince1970: seconds) <= cutoff else { continue }
            if best.map({ $0.key.lexicographicallyPrecedes(key) }) ?? true { best = (key, version) }
        }
        guard let best else { throw Failure.noneEligible }
        return best.version
    }

    /// `2026.10.6`: three runs of ASCII digits, what `mise_release_key` accepts.
    static func isVersion(_ s: String) -> Bool { key(s) != nil }

    static func key(_ s: String) -> [Int]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        guard let x = key(a), let y = key(b) else { return VersionComparator.compare(a, b) }
        if x == y { return .orderedSame }
        return x.lexicographicallyPrecedes(y) ? .orderedAscending : .orderedDescending
    }
}
