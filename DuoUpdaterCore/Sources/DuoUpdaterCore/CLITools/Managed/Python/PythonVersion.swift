import Foundation

/// A Python package version as PEP 440 orders it — what PyPI's releases and a
/// venv's dist-info carry. `VersionComparator` splits on digits and letters,
/// which puts `1.0.post1` below `1.0` and `1.0.dev0` beside `1.0a1`; the
/// managed Python rows (uv tool, pipx) order by this instead
/// (`ManagerDescriptor.VersionOrder.pep440`).
///
/// Parsed: epoch (`1!`), release (`1.2.3`), pre-release (`a`/`b`/`rc` and the
/// spellings PEP 440 normalizes to them), post (`.post1`, `-1`), dev (`.dev0`).
/// A local label (`+abc`) is dropped: no index serves one. Anything else is nil.
public struct PythonVersion: Comparable, Sendable, CustomStringConvertible {
    public let epoch: Int
    public let release: [Int]
    /// "a", "b" or "rc", and its number.
    public let pre: (label: String, number: Int)?
    public let post: Int?
    public let dev: Int?
    public let description: String

    public init?(_ text: String) {
        let pattern = #"""
        ^\s*v?(?:(\d+)!)?(\d+(?:\.\d+)*)(?:[-_.]?(a|alpha|b|beta|c|rc|pre|preview)[-_.]?(\d*))?(?:(?:-(\d+))|(?:[-_.]?(post|rev|r)[-_.]?(\d*)))?(?:[-_.]?(dev)[-_.]?(\d*))?(?:\+[a-z0-9]+(?:[-_.][a-z0-9]+)*)?\s*$
        """#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        epoch = group(1).flatMap { Int($0) } ?? 0
        let parts = (group(2) ?? "").split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        release = parts
        if let label = group(3)?.lowercased() {
            let normalized: String
            switch label {
            case "alpha", "a": normalized = "a"
            case "beta", "b": normalized = "b"
            default: normalized = "rc"
            }
            pre = (normalized, group(4).flatMap { Int($0) } ?? 0)
        } else {
            pre = nil
        }
        if let implicit = group(5) {
            post = Int(implicit)
        } else if group(6) != nil {
            post = group(7).flatMap { Int($0) } ?? 0
        } else {
            post = nil
        }
        dev = group(8) != nil ? (group(9).flatMap { Int($0) } ?? 0) : nil
        description = text.trimmingCharacters(in: .whitespaces)
    }

    /// A pre-release or a development release: never the newest a plain
    /// `pip install` or `uv tool upgrade` picks while a final one exists.
    public var isPrerelease: Bool { pre != nil || dev != nil }

    /// PEP 440's order: epoch, release (trailing zeros ignored), then
    /// dev < pre < final < post — `1.0.dev0 < 1.0a1 < 1.0 < 1.0.post1`.
    public static func < (lhs: PythonVersion, rhs: PythonVersion) -> Bool { compare(lhs, rhs) == .orderedAscending }

    public static func == (lhs: PythonVersion, rhs: PythonVersion) -> Bool { compare(lhs, rhs) == .orderedSame }

    static func compare(_ a: PythonVersion, _ b: PythonVersion) -> ComparisonResult {
        if a.epoch != b.epoch { return a.epoch < b.epoch ? .orderedAscending : .orderedDescending }
        let order = compareRelease(a.release, b.release)
        if order != .orderedSame { return order }
        let keyA = a.phaseKey, keyB = b.phaseKey
        for (x, y) in zip(keyA, keyB) where x != y { return x < y ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    static func compareRelease(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// The parts after the release, as numbers to compare in turn: a dev
    /// release of a final version sorts below its pre-releases, a final below
    /// its post-releases, and each phase's dev below the phase itself.
    private var phaseKey: [Int] {
        let preRank: Int
        let preNumber: Int
        if let pre {
            preRank = ["a": 1, "b": 2, "rc": 3][pre.label] ?? 3
            preNumber = pre.number
        } else if dev != nil, post == nil {
            preRank = 0
            preNumber = 0
        } else {
            preRank = 4
            preNumber = 0
        }
        return [preRank, preNumber, post.map { $0 + 1 } ?? 0, dev ?? Int.max]
    }
}

/// A PEP 440 version specifier set — `>=3.10`, `>=3.8,<4`, `!=3.0.*`,
/// `~=3.9` — asked whether a Python interpreter's version satisfies it: what
/// a release's `requires_python` says about the venv it would go into.
public struct PythonSpecifier: Sendable {
    let clauses: [(op: String, version: String)]

    /// Nil for a specifier this cannot read; pip ignores an invalid
    /// `Requires-Python` (it installs with a warning), and so do the callers.
    public init?(_ text: String) {
        var clauses: [(String, String)] = []
        for raw in text.split(separator: ",") {
            let clause = raw.trimmingCharacters(in: .whitespaces)
            guard !clause.isEmpty else { continue }
            guard let op = ["===", "~=", "==", "!=", ">=", "<=", ">", "<"].first(where: { clause.hasPrefix($0) }) else {
                return nil
            }
            let version = clause.dropFirst(op.count).trimmingCharacters(in: .whitespaces)
            let bare = version.hasSuffix(".*") ? String(version.dropLast(2)) : version
            guard PythonVersion(bare) != nil else { return nil }
            clauses.append((op, version))
        }
        self.clauses = clauses
    }

    /// Whether `version` (an interpreter's, "3.12.15") meets every clause.
    public func allows(_ version: PythonVersion) -> Bool {
        clauses.allSatisfy { Self.allows(version, op: $0.op, spelled: $0.version) }
    }

    static func allows(_ version: PythonVersion, op: String, spelled: String) -> Bool {
        if spelled.hasSuffix(".*") {
            guard let prefix = PythonVersion(String(spelled.dropLast(2))) else { return true }
            let matches = version.epoch == prefix.epoch
                && Array(version.release.prefix(prefix.release.count)) + Array(repeating: 0, count: max(0, prefix.release.count - version.release.count))
                    == prefix.release
            switch op {
            case "==": return matches
            case "!=": return !matches
            default: return true
            }
        }
        guard let other = PythonVersion(spelled) else { return true }
        switch op {
        case "==", "===": return version == other
        case "!=": return version != other
        case ">=": return version >= other
        case "<=": return version <= other
        case ">": return version > other
        case "<": return version < other
        case "~=":
            // `~=3.9` is `>=3.9, ==3.*`; `~=3.9.2` is `>=3.9.2, ==3.9.*`.
            guard other.release.count >= 2 else { return version >= other }
            let prefix = Array(other.release.dropLast())
            return version >= other && Array(version.release.prefix(prefix.count)) == prefix
        default: return true
        }
    }
}
