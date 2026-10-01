import Testing
import Foundation
@testable import DuoUpdaterCore

/// npm's version order and range grammar, as npm checks `engines` with them
/// (node-semver `satisfies(v, range, { includePrerelease: true })`). The expected
/// answers are node-semver's; the real `engines.node` strings at the bottom were
/// read from the registry on 2026-10-02.
@Suite struct NpmSemverTests {

    func v(_ s: String) throws -> NpmVersion { try #require(NpmVersion(s)) }

    func sat(_ version: String, _ range: String) throws -> Bool {
        let r = try #require(NpmRange(range), "range \(range) should parse")
        return r.satisfies(try v(version))
    }

    // MARK: - Versions

    @Test func parsesStrictSemverOnly() {
        #expect(NpmVersion("1.2.3")?.description == "1.2.3")
        #expect(NpmVersion("v1.2.3")?.description == "1.2.3")
        #expect(NpmVersion("1.2.3-beta.4+build.5")?.description == "1.2.3-beta.4")
        #expect(NpmVersion("2026.9.1-beta.1")?.prereleaseName == "beta")
        #expect(NpmVersion("0.1.0-0")?.prereleaseName == nil)
        for bad in ["1.2", "1", "01.2.3", "1.2.3-", "1.2.3-01", "1.2.3-a..b", "x.2.3", "", "1.2.3.4"] {
            #expect(NpmVersion(bad) == nil, "\(bad) is not strict semver")
        }
    }

    /// semver §11, and the case `VersionComparator` cannot be trusted with:
    /// a prerelease below its release (prettier's 4.0.0-alpha.13 vs 3.9.9 vs 4.0.0).
    @Test func ordersBySemverPrecedence() throws {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                       "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0"]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            #expect(try v(a) < v(b), "\(a) < \(b)")
            #expect(!(try v(b) < v(a)))
        }
        #expect(try v("3.9.9") < v("4.0.0-alpha.13"))
        #expect(try v("4.0.0-alpha.13") < v("4.0.0"))
        #expect(try v("1.2.3+a") == v("1.2.3+b"))
    }

    // MARK: - Ranges

    @Test func primitiveComparators() throws {
        #expect(try sat("1.2.3", ">=1.2.3"))
        #expect(try !sat("1.2.2", ">=1.2.3"))
        #expect(try sat("1.2.4", ">1.2.3"))
        #expect(try !sat("1.2.3", ">1.2.3"))
        #expect(try sat("1.2.2", "<1.2.3"))
        #expect(try sat("1.2.3", "<=1.2.3"))
        #expect(try sat("1.2.3", "=1.2.3"))
        #expect(try sat("1.2.3", "1.2.3"))
        #expect(try !sat("1.2.4", "1.2.3"))
        // An operator may be separated from its version.
        #expect(try sat("18.0.0", ">= 18"))
        #expect(try sat("18.0.0", ">=  18.0.0   <19"))
    }

    /// node-semver's desugaring of partial versions.
    @Test func partialVersionsWiden() throws {
        #expect(try sat("2.0.0", ">1"))
        #expect(try !sat("1.9.9", ">1"))
        #expect(try sat("1.3.0", ">1.2"))
        #expect(try !sat("1.2.9", ">1.2"))
        #expect(try sat("1.2.9", "<=1.2"))
        #expect(try !sat("1.3.0", "<=1.2"))
        #expect(try !sat("1.2.0", "<1.2"))
        #expect(try sat("1.1.9", "<1.2"))
        #expect(try sat("1.2.0", ">=1.2"))
        #expect(try sat("1.2.5", "1.2"))
        #expect(try !sat("1.3.0", "1.2"))
        #expect(try sat("1.9.0", "1.x"))
        #expect(try sat("1.9.0", "1.*"))
        #expect(try !sat("2.0.0", "1.X"))
        #expect(try sat("24.13.0", ">=18.*"))  // pnpm 12's engines.node
        #expect(try sat("0.0.1", "*"))
        #expect(try sat("99.0.0", ""))
        #expect(try !sat("1.0.0", "<*"))
        #expect(try !sat("1.0.0", ">*"))
        // node-semver reads anything after a wildcard as wildcard: `1.x.3` is `1.x`.
        #expect(try sat("1.0.0", "1.x.3"))
        #expect(try !sat("2.0.0", "1.x.3"))
    }

    @Test func tildeAllowsPatchChanges() throws {
        #expect(try sat("1.2.9", "~1.2.3"))
        #expect(try !sat("1.3.0", "~1.2.3"))
        #expect(try !sat("1.2.2", "~1.2.3"))
        #expect(try sat("1.2.0", "~1.2"))
        #expect(try sat("1.9.0", "~1"))
        #expect(try !sat("2.0.0", "~1"))
        #expect(try sat("0.2.5", "~0.2.3"))
        #expect(try sat("1.2.4", "~> 1.2.3"))
    }

    @Test func caretKeepsTheLeftmostNonZero() throws {
        #expect(try sat("1.9.9", "^1.2.3"))
        #expect(try !sat("2.0.0", "^1.2.3"))
        #expect(try !sat("1.2.2", "^1.2.3"))
        #expect(try sat("0.2.9", "^0.2.3"))
        #expect(try !sat("0.3.0", "^0.2.3"))
        #expect(try sat("0.0.3", "^0.0.3"))
        #expect(try !sat("0.0.4", "^0.0.3"))
        #expect(try sat("1.5.0", "^1.2.x"))
        #expect(try sat("0.0.9", "^0.0.x"))
        #expect(try !sat("0.1.0", "^0.0"))
        #expect(try sat("0.9.0", "^0.x"))
        #expect(try !sat("1.0.0", "^0.x"))
        #expect(try sat("14.17.0", "^ 14.17.0"))
    }

    @Test func hyphenRanges() throws {
        #expect(try sat("1.2.3", "1.2.3 - 2.3.4"))
        #expect(try sat("2.3.4", "1.2.3 - 2.3.4"))
        #expect(try !sat("2.3.5", "1.2.3 - 2.3.4"))
        #expect(try sat("1.2.0", "1.2 - 2.3.4"))
        #expect(try sat("2.3.9", "1.2.3 - 2.3"))
        #expect(try !sat("2.4.0", "1.2.3 - 2.3"))
        #expect(try sat("2.9.9", "1.2.3 - 2"))
        #expect(try !sat("3.0.0", "1.2.3 - 2"))
        #expect(try sat("1.5.0", "1.2.3  -  2"))
    }

    @Test func alternativesAndIntersections() throws {
        #expect(try sat("20.1.0", "^18 || >=20"))
        #expect(try !sat("19.0.0", "^18 || >=20"))
        #expect(try sat("18.5.0", ">=18 <19 || >=20"))
        #expect(try !sat("19.5.0", ">=18 <19 || >=20"))
    }

    /// npm checks engines with `includePrerelease`: a prerelease node is held
    /// against the comparators like any version.
    @Test func prereleaseVersionsAreComparedLikeAnyOther() throws {
        #expect(try sat("25.0.0-nightly20260101", ">=24"))
        #expect(try !sat("25.0.0-nightly20260101", "<25"))
    }

    /// node-semver throws on these; `satisfies` is then false, and npm treats
    /// the engine as not met.
    @Test func invalidRangesParseToNil() {
        for bad in ["node >= 14", ">=1.2.3 - 2", ">=a", "^1.2.3-", "1.2.3 - ", "~~1"] {
            #expect(NpmRange(bad) == nil, "\(bad) should not parse")
        }
    }

    // MARK: - Real engines

    /// The registry's own strings, 2026-10-02, against this Mac's nodes.
    @Test func realEnginesFromTheRegistry() throws {
        let openclaw97 = ">=24.16.0 <25 || >=26.1.0"
        let openclaw833 = ">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0"
        #expect(try !sat("24.13.0", openclaw97))
        #expect(try !sat("24.13.0", openclaw833))
        #expect(try sat("24.13.0", ">=22.19.0"))  // 2026.6.35
        #expect(try sat("26.10.0", openclaw97))
        #expect(try !sat("25.5.0", openclaw97))
        #expect(try sat("25.9.0", openclaw833))
        #expect(try sat("24.13.0", ">=24.0.0"))  // agent-browser
        #expect(try sat("24.13.0", ">=16"))      // agently-cli
        #expect(try !sat("22.21.1", ">=24.0.0"))
    }

    /// "needs Node ≥ X": the lowest lower bound above the current node that its
    /// own alternative accepts.
    @Test func minimumAboveCurrent() throws {
        let range = try #require(NpmRange(">=24.16.0 <25 || >=26.1.0"))
        #expect(range.minimum(above: try v("24.13.0"))?.description == "24.16.0")
        #expect(range.minimum(above: try v("25.2.0"))?.description == "26.1.0")
        #expect(try #require(NpmRange("<20")).minimum(above: v("22.0.0")) == nil)
        #expect(try #require(NpmRange("^20")).minimum(above: v("22.0.0")) == nil)
        #expect(try #require(NpmRange(">=24")).minimum(above: v("22.0.0"))?.description == "24.0.0")
    }
}
