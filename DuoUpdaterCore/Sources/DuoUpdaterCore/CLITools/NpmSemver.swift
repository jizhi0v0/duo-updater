import Foundation

/// A semantic version as npm reads one (node-semver, strict mode): `1.2.3`,
/// `1.2.3-beta.4`, `v1.2.3`; build metadata (`+…`) is kept out of comparisons.
///
/// `VersionComparator` is not used for npm versions because the two orders differ
/// where it matters here: semver puts `4.0.0-alpha.13` *below* `4.0.0` and
/// compares prerelease identifiers by semver's rules, which is what decides
/// whether an offer would be a downgrade.
public struct NpmVersion: Sendable, Hashable, Comparable, CustomStringConvertible {

    public enum Identifier: Sendable, Hashable {
        case numeric(Int)
        case alphanumeric(String)
    }

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [Identifier]

    public init(major: Int, minor: Int, patch: Int, prerelease: [Identifier] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// nil for anything node-semver's strict parser rejects: a missing component,
    /// a leading zero, an empty prerelease identifier.
    public init?(_ text: String) {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("v") || s.hasPrefix("=") { s = s.dropFirst() }
        if let plus = s.firstIndex(of: "+") {
            let build = s[s.index(after: plus)...]
            guard Self.validIdentifiers(build, numericRule: false) != nil else { return nil }
            s = s[..<plus]
        }
        var pre: [Identifier] = []
        if let dash = s.firstIndex(of: "-") {
            guard let identifiers = Self.validIdentifiers(s[s.index(after: dash)...], numericRule: true)
            else { return nil }
            pre = identifiers
            s = s[..<dash]
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let major = Self.number(parts[0]), let minor = Self.number(parts[1]),
              let patch = Self.number(parts[2]) else { return nil }
        self.init(major: major, minor: minor, patch: patch, prerelease: pre)
    }

    /// `0` or digits without a leading zero.
    static func number(_ s: Substring) -> Int? {
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }), s == "0" || s.first != "0" else { return nil }
        return Int(s)
    }

    /// Dot-separated `[0-9A-Za-z-]+`; under `numericRule` (prerelease, not build)
    /// a purely numeric identifier may not have a leading zero.
    static func validIdentifiers(_ s: Substring, numericRule: Bool) -> [Identifier]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        var out: [Identifier] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return nil }
            if part.allSatisfy(\.isNumber) {
                if numericRule && part.count > 1 && part.first == "0" { return nil }
                guard let value = Int(part) else { return nil }
                out.append(.numeric(value))
            } else {
                out.append(.alphanumeric(String(part)))
            }
        }
        return out
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// The first word of the prerelease — `beta` in `2026.9.1-beta.1`, `alpha` in
    /// `4.0.0-alpha.13` — or nil for a release or an all-numeric prerelease
    /// (`0.1.0-0`).
    public var prereleaseName: String? {
        for identifier in prerelease {
            if case .alphanumeric(let word) = identifier {
                return String(word.prefix { $0.isLetter }).lowercased().nilIfEmpty
            }
        }
        return nil
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard isPrerelease else { return core }
        return core + "-" + prerelease.map {
            switch $0 {
            case .numeric(let n): return String(n)
            case .alphanumeric(let s): return s
            }
        }.joined(separator: ".")
    }

    /// semver precedence (§11): numbers, then a release above its prereleases,
    /// then the prerelease identifiers left to right — numeric below
    /// alphanumeric, numbers numerically, words in ASCII order, a shorter list
    /// below a longer one it prefixes.
    public static func < (lhs: NpmVersion, rhs: NpmVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.isPrerelease, rhs.isPrerelease) {
        case (false, false): return false
        case (false, true): return false
        case (true, false): return true
        case (true, true): break
        }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            switch (a, b) {
            case let (.numeric(x), .numeric(y)): return x < y
            case (.numeric, .alphanumeric): return true
            case (.alphanumeric, .numeric): return false
            case let (.alphanumeric(x), .alphanumeric(y)): return Array(x.utf8).lexicographicallyPrecedes(Array(y.utf8))
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

/// An npm version range — what `engines.node` holds — read the way npm checks
/// engines: node-semver's `satisfies(version, range, { includePrerelease: true })`
/// (`npm-install-checks`' `checkEngine`, read in npm 11.6.2's bundled copy on
/// 2026-10-02; `npm-pick-manifest` 11.0.1 picks versions through it).
///
/// The grammar: `||` separates alternatives; inside one, comparators separated by
/// spaces must all hold. A comparator is `<`, `<=`, `>`, `>=`, `=` or nothing,
/// then a version that may be partial (`1`, `1.2`) or use `x`/`X`/`*` for a
/// missing part; `~` and `^` ranges; and `A - B` hyphen ranges. Partial versions
/// widen as node-semver's desugaring does (`<=1.2` is `<1.3.0-0`, `>1` is
/// `>=2.0.0`, `^0.2.3` is `>=0.2.3 <0.3.0-0`).
///
/// With `includePrerelease` a prerelease version is held against the comparators
/// like any other — no "same tuple" rule — which is the only mode npm uses for
/// engines, and so the only one implemented.
///
/// A range node-semver would throw on reads as nil, and `satisfies` is then false
/// for every version, as npm's is.
public struct NpmRange: Sendable, Equatable, CustomStringConvertible {

    public struct Comparator: Sendable, Equatable {
        public enum Operator: String, Sendable { case lt = "<", le = "<=", gt = ">", ge = ">=", eq = "=" }
        public let op: Operator
        public let version: NpmVersion

        func test(_ v: NpmVersion) -> Bool {
            switch op {
            case .lt: return v < version
            case .le: return v <= version
            case .gt: return v > version
            case .ge: return v >= version
            case .eq: return v == version
            }
        }
    }

    /// Alternatives; each one's comparators must all hold. An empty set is "any".
    public let sets: [[Comparator]]
    public let description: String

    public init?(_ text: String) {
        var sets: [[Comparator]] = []
        for alternative in text.components(separatedBy: "||") {
            guard let set = Self.parseSet(alternative.trimmingCharacters(in: .whitespaces)) else { return nil }
            sets.append(set)
        }
        self.sets = sets
        self.description = text
    }

    public func satisfies(_ version: NpmVersion) -> Bool {
        sets.contains { set in set.allSatisfy { $0.test(version) } }
    }

    /// The lowest version above `current` that satisfies the range, judged by
    /// each alternative's own lower bound — `24.16.0` for `>=24.16.0 <25 ||
    /// >=26.1.0` at 24.13.0. For "needs Node ≥ X"; nil when no alternative
    /// starts above `current` (a range that only caps, or one already met).
    public func minimum(above current: NpmVersion) -> NpmVersion? {
        sets.compactMap { set -> NpmVersion? in
            let floors = set.filter { $0.op == .ge || $0.op == .gt || $0.op == .eq }
            guard let floor = floors.map(\.version).max(), floor > current else { return nil }
            // `>X` has no least member; X itself is the honest thing to show.
            guard set.allSatisfy({ $0.op == .gt ? $0.version == floor || $0.test(floor) : $0.test(floor) })
            else { return nil }
            // `>=24` desugars to `>=24.0.0-0`; the release is what to show.
            return floor.prerelease == [.numeric(0)]
                ? NpmVersion(major: floor.major, minor: floor.minor, patch: floor.patch) : floor
        }.min()
    }

    // MARK: - Parsing

    /// One alternative: a hyphen range, or space-separated comparators.
    static func parseSet(_ raw: String) -> [Comparator]? {
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.isEmpty { return [] }
        let hyphen = text.components(separatedBy: " - ")
        if hyphen.count == 2 {
            guard let from = Partial(hyphen[0].trimmingCharacters(in: .whitespaces)),
                  let to = Partial(hyphen[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return hyphenRange(from, to)
        }
        guard hyphen.count == 1 else { return nil }
        var out: [Comparator] = []
        for token in tokens(text) {
            guard let comparators = parseComparator(token) else { return nil }
            out += comparators
        }
        return out
    }

    /// Splits on spaces, first joining an operator to the version after it —
    /// node-semver accepts `>= 1.2.3`, `~ 1.2` and `^ 1.2`.
    static func tokens(_ text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [String] = []
        let operators: Set<String> = ["<", "<=", ">", ">=", "=", "~", "~>", "^"]
        var pending = ""
        for word in words {
            if operators.contains(word) {
                pending += word
            } else {
                out.append(pending + word)
                pending = ""
            }
        }
        if !pending.isEmpty { out.append(pending) }
        return out
    }

    static func parseComparator(_ token: String) -> [Comparator]? {
        var rest = Substring(token)
        if rest.hasPrefix("~>") || rest.hasPrefix("~") {
            rest = rest.dropFirst(rest.hasPrefix("~>") ? 2 : 1)
            return Partial(String(rest)).flatMap(tilde)
        }
        if rest.hasPrefix("^") {
            return Partial(String(rest.dropFirst())).flatMap(caret)
        }
        var op = ""
        for candidate in ["<=", ">=", "<", ">", "="] where rest.hasPrefix(candidate) {
            op = candidate
            rest = rest.dropFirst(candidate.count)
            break
        }
        guard let partial = Partial(String(rest)) else { return nil }
        return xRange(op, partial)
    }

    /// A version with any trailing part missing or written `x`/`X`/`*`.
    struct Partial {
        let major: Int?
        let minor: Int?
        let patch: Int?
        let prerelease: [NpmVersion.Identifier]

        init?(_ text: String) {
            var s = Substring(text)
            if s.hasPrefix("v") || s.hasPrefix("=") { s = s.dropFirst() }
            if let plus = s.firstIndex(of: "+") {
                guard NpmVersion.validIdentifiers(s[s.index(after: plus)...], numericRule: false) != nil
                else { return nil }
                s = s[..<plus]
            }
            var pre: [NpmVersion.Identifier] = []
            if let dash = s.firstIndex(of: "-") {
                guard let identifiers = NpmVersion.validIdentifiers(s[s.index(after: dash)...], numericRule: true)
                else { return nil }
                pre = identifiers
                s = s[..<dash]
            }
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...3).contains(parts.count) else { return nil }
            var values: [Int?] = []
            for part in parts {
                if ["x", "X", "*"].contains(part) {
                    values.append(nil)
                } else if let n = NpmVersion.number(part) {
                    // node-semver reads `1.x.3` as `1.x`: after a wildcard, the
                    // rest is wildcard too.
                    values.append(values.contains(where: { $0 == nil }) ? nil : n)
                } else {
                    return nil
                }
            }
            while values.count < 3 { values.append(nil) }
            // A prerelease on a partial version is dropped, as node-semver does.
            if values.contains(where: { $0 == nil }) { pre = [] }
            major = values[0]
            minor = values[1]
            patch = values[2]
            prerelease = pre
        }

        var full: NpmVersion? {
            guard let major, let minor, let patch else { return nil }
            return NpmVersion(major: major, minor: minor, patch: patch, prerelease: prerelease)
        }
    }

    static func v(_ major: Int, _ minor: Int, _ patch: Int, zero: Bool = false) -> NpmVersion {
        NpmVersion(major: major, minor: minor, patch: patch, prerelease: zero ? [.numeric(0)] : [])
    }

    /// `>=0.0.0-0`: everything, prereleases included.
    static let anything: [Comparator] = []
    /// `<0.0.0-0`: nothing.
    static let nothing: [Comparator] = [Comparator(op: .lt, version: v(0, 0, 0, zero: true))]

    static func ge(_ v: NpmVersion) -> Comparator { Comparator(op: .ge, version: v) }
    static func lt(_ v: NpmVersion) -> Comparator { Comparator(op: .lt, version: v) }

    /// `~1.2.3` `>=1.2.3 <1.3.0-0`; `~1.2` `>=1.2.0 <1.3.0-0`; `~1` `>=1.0.0 <2.0.0-0`.
    ///
    /// Lower bounds without `-0`, unlike `^` and `>=` under `includePrerelease` —
    /// node-semver's `replaceTilde` never adds it, so `~1` excludes `1.0.0-rc.1`.
    static func tilde(_ p: Partial) -> [Comparator]? {
        guard let major = p.major else { return anything }
        guard let minor = p.minor else { return [ge(v(major, 0, 0)), lt(v(major + 1, 0, 0, zero: true))] }
        let upper = lt(v(major, minor + 1, 0, zero: true))
        guard let full = p.full else { return [ge(v(major, minor, 0)), upper] }
        return [ge(full), upper]
    }

    /// `^` allows changes that keep the left-most non-zero part.
    static func caret(_ p: Partial) -> [Comparator]? {
        guard let major = p.major else { return anything }
        guard let minor = p.minor else { return [ge(v(major, 0, 0, zero: true)), lt(v(major + 1, 0, 0, zero: true))] }
        guard let full = p.full else {
            let upper = major == 0 ? v(0, minor + 1, 0, zero: true) : v(major + 1, 0, 0, zero: true)
            return [ge(v(major, minor, 0, zero: true)), lt(upper)]
        }
        let upper: NpmVersion
        if major != 0 {
            upper = v(major + 1, 0, 0, zero: true)
        } else if minor != 0 {
            upper = v(0, minor + 1, 0, zero: true)
        } else {
            upper = v(0, 0, full.patch + 1, zero: true)
        }
        // `replaceCaret` adds `-0` to a full release's lower bound only under a
        // zero major (`^0.2.3` is `>=0.2.3-0`, `^1.2.3` is `>=1.2.3`).
        let lower = major == 0 && !full.isPrerelease ? v(0, minor, full.patch, zero: true) : full
        return [ge(lower), lt(upper)]
    }

    /// A primitive comparator, its partial version widened (`replaceXRange`).
    static func xRange(_ op: String, _ p: Partial) -> [Comparator]? {
        if let full = p.full {
            switch op {
            case "<": return [lt(full)]
            case "<=": return [Comparator(op: .le, version: full)]
            case ">": return [Comparator(op: .gt, version: full)]
            case ">=": return [ge(full)]
            default: return [Comparator(op: .eq, version: full)]
            }
        }
        guard let major = p.major else {
            return op == "<" || op == ">" ? nothing : anything
        }
        switch op {
        case ">":
            // `>1` is `>=2.0.0`, `>1.2` is `>=1.3.0`.
            return p.minor.map { [ge(v(major, $0 + 1, 0, zero: true))] } ?? [ge(v(major + 1, 0, 0, zero: true))]
        case ">=":
            return [ge(v(major, p.minor ?? 0, 0, zero: true))]
        case "<":
            return [lt(v(major, p.minor ?? 0, 0, zero: true))]
        case "<=":
            return p.minor.map { [lt(v(major, $0 + 1, 0, zero: true))] } ?? [lt(v(major + 1, 0, 0, zero: true))]
        default:
            // `1.x` / `=1.2`: the whole family.
            if let minor = p.minor {
                return [ge(v(major, minor, 0, zero: true)), lt(v(major, minor + 1, 0, zero: true))]
            }
            return [ge(v(major, 0, 0, zero: true)), lt(v(major + 1, 0, 0, zero: true))]
        }
    }

    /// `1.2.3 - 2.3.4` is `>=1.2.3 <=2.3.4`; a partial upper end covers its family
    /// (`1.2.3 - 2.3` is `<2.4.0-0`).
    static func hyphenRange(_ from: Partial, _ to: Partial) -> [Comparator] {
        var out: [Comparator] = []
        if let major = from.major {
            // `>=from-0` for a release, as `hyphenReplace` writes it under `includePrerelease`.
            let full = from.full.map { $0.isPrerelease ? $0 : v($0.major, $0.minor, $0.patch, zero: true) }
            out.append(ge(full ?? v(major, from.minor ?? 0, 0, zero: true)))
        }
        if let major = to.major {
            if let full = to.full {
                out.append(full.isPrerelease ? Comparator(op: .le, version: full) : lt(v(major, full.minor, full.patch + 1, zero: true)))
            } else if let minor = to.minor {
                out.append(lt(v(major, minor + 1, 0, zero: true)))
            } else {
                out.append(lt(v(major + 1, 0, 0, zero: true)))
            }
        }
        return out
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
