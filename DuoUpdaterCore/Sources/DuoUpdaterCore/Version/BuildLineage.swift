import Foundation

/// The order of a vendor's builds, for a vendor whose build ids have none of their
/// own.
///
/// **Why this exists.** Some apps version by commit hash. super.engineering
/// (`com.zarifpour.superconductor`) reports the first eight hex digits of its
/// commit as both `CFBundleShortVersionString` and `CFBundleVersion` ("8545a7d8"),
/// and its update manifest names the same commit. `VersionComparator` has no way to
/// order two such strings — it splits them into digit and letter runs and compares
/// whichever leading run it finds, so "8545a7d8" outranks "19d32d9a" because 8545 >
/// 19. Replayed over every consecutive pair in the vendor's own release history
/// (626 pairs, `changelog.json` fetched 2026-09-10), it called the newer build newer
/// 313 times and older 313 times. That is a coin flip on every "is this newer?"
/// the engine asks: half of all updates never offered, and some older builds
/// offered as updates.
///
/// The vendor does publish an order — its release history, newest first — so a
/// recipe that declares `VendorProbeRecipe.buildLineage` reads it, and the
/// resulting `RemoteVersion.buildLineage` becomes the whole answer to "is this
/// newer" wherever the engine asks it. Anything the lineage cannot place (a build
/// it does not list) is "cannot tell", never a guess in either direction.
///
/// Compared by exact equality, never by prefix: the recipe's entry pattern is
/// written to yield exactly the form the installed bundle reports, the same way
/// its `versionPattern` is.
public struct BuildLineage: Sendable, Hashable {

    /// Build ids, newest first. Empty ids and repeats are dropped (first
    /// occurrence kept), so a position is unambiguous.
    public let newestFirst: [String]

    public init(newestFirst builds: [String]) {
        var seen = Set<String>()
        newestFirst = builds.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Where `build` sits — 0 is the newest — or nil when the lineage does not
    /// list it.
    public func position(of build: String) -> Int? {
        newestFirst.firstIndex(of: build)
    }

    /// Whether `candidate` is a newer build than `current`: true or false when the
    /// lineage places both, nil when it cannot place one of them. The same build is
    /// never newer than itself, whether or not the lineage lists it.
    public func isNewer(_ candidate: String, than current: String) -> Bool? {
        if candidate == current { return false }
        guard let c = position(of: candidate), let i = position(of: current) else {
            return nil
        }
        return c < i
    }

    /// Every capture-group-1 match of `pattern` in `body`, in document order (the
    /// whole match when the pattern has no group). Nil when the pattern is invalid
    /// or matches nothing — a lineage with no builds in it can place nothing, and
    /// the caller has to be able to tell that from one that simply lacks a build.
    public static func extract(from body: String, pattern: String) -> BuildLineage? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = body as NSString
        let builds = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> String? in
                let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard range.location != NSNotFound else { return nil }
                return ns.substring(with: range)
            }
        let lineage = BuildLineage(newestFirst: builds)
        return lineage.newestFirst.isEmpty ? nil : lineage
    }
}

extension RemoteVersion {
    /// The two strings `buildLineage` compares for this remote against an installed
    /// copy: the builds when both sides carry one (`installedBuild` already read in
    /// this remote's `buildNamespace`), otherwise the marketing versions — the same
    /// choice `UpdateChecker.evaluate` makes. Nil when neither pair is complete.
    func lineageComparands(
        installedMarketing: String?, installedBuild: String?
    ) -> (remote: String, installed: String)? {
        if let rv = version, let iv = installedBuild { return (rv, iv) }
        if let rs = shortVersion, let isv = installedMarketing { return (rs, isv) }
        return nil
    }
}
