import Testing
import Foundation
@testable import DuoUpdaterCore

/// Every GitHub rule's `versionPattern` must still read the vendor's next major
/// release. A pattern that pins the major (`^v(2\.[0-9]+\.[0-9]+)$`, written to
/// keep a sibling product's tags out) passes every test on the day it lands and
/// then reports "up to date" forever once `v3.0.0` ships. The onboarding
/// benchmark (bench/onboarding, 2026-10) produced exactly that rule. Keep a
/// sibling out the way the app-audit skill says: by asset name on a rule that installs,
/// and on a detection-only rule by excluding the sibling's versions
/// (`^v((?!1\.)[0-9]+(?:\.[0-9]+)+)$`), since an asset pattern turns on one-click.
///
/// The check is offline: it builds tags in the common shapes (`v1.2.3`, `1.2`,
/// the pattern's own literal prefix such as `cua-driver-rs-v`) for majors 0-30,
/// and for each shape the pattern reads asks for the majors one and ten past the
/// highest one it reads. Excluding a lower major is fine; an upper bound is not.
/// A rule whose tags fit none of those shapes is not checked here.
struct GitHubNextMajorTests {

    /// The literal text a pattern requires before its first capture or
    /// metacharacter, e.g. `cua-driver-rs-v` for `^cua-driver-rs-v([0-9]+…`.
    static func literalPrefix(of pattern: String) -> String {
        var s = Substring(pattern)
        if s.hasPrefix("^") { s = s.dropFirst() }
        if s.hasPrefix("\\A") { s = s.dropFirst(2) }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\\" {
                guard let n = it.next(), "-._/".contains(n) else { break }
                out.append(n)
            } else if "([{.*+?|^$".contains(c) {
                break
            } else {
                out.append(c)
            }
        }
        // A trailing optional character (`v?`) is not required.
        if let last = s.dropFirst(out.count).first, last == "?" || last == "*" { out = String(out.dropLast()) }
        return out
    }

    /// For each probed shape, the highest-major tag the pattern reads and the
    /// later major it does not, as "tag → later". Empty when no tag of the
    /// probed shapes matches at all.
    static func nextMajorMisses(pattern: String) -> (checked: Int, misses: [String]) {
        let prefixes = Set(["v", "", "V", literalPrefix(of: pattern)])
        let rests = [".2.3", ".2", ".2.3.4", ".10.1"]
        var checked = 0
        var misses: [String] = []
        for prefix in prefixes.sorted() {
            for rest in rests {
                let read = (0...30).filter {
                    VendorProbeRecipe.extractVersion(from: "\(prefix)\($0)\(rest)", pattern: pattern) != nil
                }
                guard let highest = read.last else { continue }
                checked += 1
                let tag = "\(prefix)\(highest)\(rest)"
                for next in [highest + 1, highest + 10] {
                    let later = "\(prefix)\(next)\(rest)"
                    if VendorProbeRecipe.extractVersion(from: later, pattern: pattern) == nil {
                        misses.append("\(tag) → \(later)")
                    }
                }
            }
        }
        return (checked, misses)
    }

    @Test func aPinnedMajorIsCaught() {
        let pinned = Self.nextMajorMisses(pattern: #"^v(2\.[0-9]+\.[0-9]+)$"#)
        #expect(pinned.checked > 0)
        #expect(pinned.misses.contains("v2.2.3 → v3.2.3"))
        let prefixed = Self.nextMajorMisses(pattern: #"^cua-driver-rs-v(1\.[0-9]+\.[0-9]+)$"#)
        #expect(prefixed.misses.contains("cua-driver-rs-v1.2.3 → cua-driver-rs-v2.2.3"))
    }

    @Test func anOpenPatternPasses() {
        for pattern in [#"v?([0-9]+(?:\.[0-9]+)+)"#, #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                        #"^cua-driver-rs-v([0-9]+\.[0-9]+\.[0-9]+)$"#,
                        // app-audit's detection-only sibling exclusion: 1.x is
                        // another product, every later major is this one.
                        #"^v((?!1\.)[0-9]+(?:\.[0-9]+)+)$"#] {
            let result = Self.nextMajorMisses(pattern: pattern)
            #expect(result.checked > 0, "\(pattern) matched no probed tag")
            #expect(result.misses.isEmpty, "\(pattern): \(result.misses.prefix(3))")
        }
    }

    /// Rules whose major version is the product: the vendor ships each major as
    /// its own app under its own bundle id, so a pinned major is what keeps the
    /// two apart. Bundle id → why.
    static let majorIsTheProduct: [String: String] = [
        "org.audacityteam.audacity":
            "Audacity 3; 4.x ships as Audacity 4.app, org.audacityteam.audacity4 (docs/app-audits/org-audacityteam-audacity.md)",
        "org.audacityteam.audacity4":
            "Audacity 4; the audit splits the shared tag list by major, and no 5.x exists to say which app it would be",
        "org.musescore.MuseScore":
            "MuseScore 4; the vendor ships each major as its own `MuseScore <major>.app`, and main's version.cmake builds 5.x as org.musescore.MuseScoreStudio5 (docs/app-audits/org-musescore-MuseScore.md)",
    ]

    @Test func theExemptionsStillPinAMajor() {
        for (bundleID, _) in Self.majorIsTheProduct {
            let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
            #expect(!rules.isEmpty, "\(bundleID) is exempt but has no GitHub rule; drop it from majorIsTheProduct")
            for rule in rules {
                #expect(!Self.nextMajorMisses(pattern: rule.versionPattern).misses.isEmpty,
                        "\(bundleID) reads the next major now; drop it from majorIsTheProduct")
            }
        }
    }

    @Test func everyRuleReadsTheNextMajor() {
        for rule in GitHubReleaseRegistry.rules where Self.majorIsTheProduct[rule.bundleID] == nil {
            let result = Self.nextMajorMisses(pattern: rule.versionPattern)
            #expect(result.misses.isEmpty,
                    "\(rule.bundleID) [\(rule.channel.rawValue)] \(rule.owner)/\(rule.repo): \(rule.versionPattern) does not read the next major: \(result.misses.prefix(3))")
        }
    }
}
