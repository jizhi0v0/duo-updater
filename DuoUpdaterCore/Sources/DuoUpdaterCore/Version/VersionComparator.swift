import Foundation

/// Version comparison modeled on Sparkle's `SUStandardVersionComparator`:
/// split each version into runs of digits and runs of non-digits, then compare
/// component by component — numerically when both sides are numeric, otherwise
/// lexicographically. Missing trailing components are treated as "0".
///
/// Handles the common shapes we see in the wild: "1.2.3", "1.2", "1.96.0",
/// build numbers like "45830", and pre-release tags like "2.0-beta1".
public enum VersionComparator {

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = tokenize(lhs)
        let b = tokenize(rhs)
        let count = max(a.count, b.count)

        for i in 0..<count {
            let l = i < a.count ? a[i] : .number("0")
            let r = i < b.count ? b[i] : .number("0")
            let result = l.compared(to: r)
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }

    /// True when `candidate` is strictly newer than `current`.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    /// The leading numeric ("major") component, ignoring any prefix like "v".
    /// "6.9.1" → 6, "v7.1" → 7, returns nil when there's no number.
    public static func majorComponent(_ version: String) -> Int? {
        for token in tokenize(version) {
            if case let .number(digits) = token { return Int(digits) }
        }
        return nil
    }

    /// True when `candidate`'s major version exceeds `current`'s — the signal
    /// MacUpdater uses to warn that a commercial app may need a new license.
    /// Conservative: returns false when either major component is unreadable.
    public static func isMajorUpgrade(from current: String, to candidate: String) -> Bool {
        guard let a = majorComponent(current), let b = majorComponent(candidate) else {
            return false
        }
        return b > a
    }

    /// True when `version`'s leading numeric component is a four-digit calendar
    /// year (CalVer — JetBrains "2024.1", "2024.11.5", etc.). A year-led scheme
    /// increments its leading number every release, so a "major bump" there is a
    /// date rolling over, never a paid product-line boundary. Only the *leading*
    /// number counts: "12.13.2" (major 12) is not CalVer, "1.2024" isn't either.
    /// Two-digit-year and YYYYMMDD shapes are deliberately excluded — they alias
    /// ordinary semver too readily to detect safely.
    public static func isCalendarVersion(_ version: String) -> Bool {
        for token in tokenize(version) {
            if case let .number(digits) = token {
                guard let n = Int(digits) else { return false }
                return (2000...2099).contains(n)
            }
            // Leading non-numeric run (e.g. a "v" prefix): skip and keep looking.
        }
        return false
    }

    // MARK: - Tokenizing

    private enum Token {
        /// A run of digits kept as its raw string so arbitrarily long build
        /// numbers (epoch-ms, concatenated hashes) compare by magnitude rather
        /// than overflowing `Int` and silently degrading to a text comparison.
        case number(String)
        case text(String)

        func compared(to other: Token) -> ComparisonResult {
            switch (self, other) {
            case let (.number(a), .number(b)):
                return Token.compareNumeric(a, b)
            case let (.text(a), .text(b)):
                // A release ("") outranks a pre-release tag ("beta"): treat a
                // numeric component as newer than an adjacent text one is
                // handled below; here both are text so compare lexically.
                return a.compare(b)
            case (.number, .text):
                // 1.0 > 1.0beta — a numeric component beats a textual one.
                return .orderedDescending
            case (.text, .number):
                return .orderedAscending
            }
        }

        /// Compare two digit runs as non-negative integers of unbounded size:
        /// strip leading zeros, then compare by length, then lexically. Equal
        /// magnitude with differing zero-padding (e.g. "007" vs "7") is equal.
        static func compareNumeric(_ a: String, _ b: String) -> ComparisonResult {
            let x = Substring(a).drop { $0 == "0" }
            let y = Substring(b).drop { $0 == "0" }
            if x.count != y.count {
                return x.count < y.count ? .orderedAscending : .orderedDescending
            }
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        }
    }

    private static func tokenize(_ version: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsDigit: Bool?

        func flush() {
            guard !current.isEmpty else { return }
            if currentIsDigit == true {
                tokens.append(.number(current))
            } else {
                tokens.append(.text(current))
            }
            current = ""
        }

        for ch in version {
            if ch == "." || ch == "_" || ch == "-" || ch == "+" || ch == " "
                || ch == "(" || ch == ")" {
                flush()
                currentIsDigit = nil
                continue
            }
            let isDigit = ch.isNumber
            if let prev = currentIsDigit, prev != isDigit {
                flush()
            }
            current.append(ch)
            currentIsDigit = isDigit
        }
        flush()
        return tokens
    }
}
