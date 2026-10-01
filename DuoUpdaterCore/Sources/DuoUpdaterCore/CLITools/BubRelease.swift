import Foundation

/// The version a plain `bub` requirement resolves to on PyPI — what `bub update
/// bub` would take.
///
/// Read from `https://pypi.org/pypi/bub/json`'s `releases` rather than its
/// `info.version`, so the two rules a resolver applies to an unpinned requirement
/// are applied here, visibly:
/// - **no pre-releases** while any final release exists (PEP 440's default, which
///   pip and uv both follow). PyPI has `0.1.0a1` and `0.3.0a1` for bub;
/// - **no yanked files** (PEP 592: a yanked file is only chosen by an `==` pin).
///   None of bub's are yanked (2026-10-01), so this rule is untested by the live
///   feed and pinned by the tests instead.
///
/// Measured 2026-10-01: 24 releases, `0.5.0` the newest; `info.version` agreed.
/// `cache-control: max-age=900` on the response, so the version-feed cache
/// policy's revalidation is what keeps a fresh release from hiding for 15 minutes.
public struct BubRelease: Sendable {

    public static let pypi = URL(string: "https://pypi.org/pypi/bub/json")!

    public enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
    }

    let session: URLSession

    public init(session: URLSession = .updates) {
        self.session = session
    }

    public func latestVersion() async throws -> String {
        var request = URLRequest(url: Self.pypi)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.http(status) }
        guard let version = Self.latest(fromJSON: data) else { throw Failure.unreadable }
        return version
    }

    /// The newest release that has at least one file not yanked and is not a
    /// pre-release; when every release is a pre-release, the newest of those —
    /// the resolvers' own fallback for a project with no final release.
    static func latest(fromJSON data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releases = json["releases"] as? [String: Any]
        else { return nil }
        let installable = releases.compactMap { version, files -> String? in
            guard let files = files as? [[String: Any]],
                  files.contains(where: { ($0["yanked"] as? Bool) != true })
            else { return nil }
            return version
        }
        let finals = installable.filter { !isPrerelease($0) }
        return (finals.isEmpty ? installable : finals).max {
            VersionComparator.compare($0, $1) == .orderedAscending
        }
    }

    /// PEP 440 pre- and dev-releases: `a`, `b`, `rc` (and their long spellings)
    /// and `.dev`. A `.post` release is final, so it is taken out before looking
    /// for letters; PyPI's keys are already normalized, which is why any letter
    /// left over is one of those markers.
    static func isPrerelease(_ version: String) -> Bool {
        let withoutPost = version.lowercased().replacingOccurrences(
            of: #"[.\-_]?post[.\-_]?\d*"#, with: "", options: .regularExpression)
        return withoutPost.contains { $0.isLetter }
    }
}
