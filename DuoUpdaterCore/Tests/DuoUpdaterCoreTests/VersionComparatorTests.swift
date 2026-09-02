import Testing
@testable import DuoUpdaterCore

@Test func basicOrdering() {
    #expect(VersionComparator.isNewer("1.2.3", than: "1.2.2"))
    #expect(VersionComparator.isNewer("1.3.0", than: "1.2.9"))
    #expect(VersionComparator.isNewer("2.0", than: "1.9.9"))
    #expect(!VersionComparator.isNewer("1.2.3", than: "1.2.3"))
    #expect(!VersionComparator.isNewer("1.2.2", than: "1.2.3"))
}

@Test func missingComponentsAreZero() {
    #expect(VersionComparator.compare("1.2", "1.2.0") == .orderedSame)
    #expect(VersionComparator.isNewer("1.2.1", than: "1.2"))
}

@Test func buildNumbers() {
    #expect(VersionComparator.isNewer("45830", than: "45821"))
    #expect(!VersionComparator.isNewer("45821", than: "45830"))
}

@Test func preReleaseTags() {
    // A final release beats its own pre-release.
    #expect(VersionComparator.isNewer("2.0", than: "2.0-beta1"))
    #expect(VersionComparator.isNewer("2.0-beta2", than: "2.0-beta1"))
}

/// Numeric runs longer than `Int.max` (20+ digits) must still compare by
/// magnitude. Previously these overflowed `Int`, degraded to a text comparison,
/// and could rank a genuinely newer build as older (a missed update).
@Test func hugeBuildNumbers() {
    let big = "99999999999999999999"      // 20 nines, > Int64.max
    let bigger = "100000000000000000000"  // 21 digits
    #expect(VersionComparator.isNewer(bigger, than: big))
    #expect(!VersionComparator.isNewer(big, than: bigger))
    // A huge build is newer than a small one (regression: text<number flipped this).
    #expect(VersionComparator.isNewer(big, than: "5"))
    // Epoch-ms style timestamps.
    #expect(VersionComparator.isNewer("1.0.1717200000000", than: "1.0.1717100000000"))
}

/// Leading zeros are magnitude-equal, not distinct, and don't invert ordering.
@Test func leadingZeros() {
    #expect(VersionComparator.compare("1.007", "1.7") == .orderedSame)
    #expect(VersionComparator.compare("1.08", "1.8") == .orderedSame)
    #expect(VersionComparator.isNewer("1.10", than: "1.09"))
    #expect(VersionComparator.isNewer("1.10", than: "1.9"))
}

/// A leading "v"/"V" tag must not invert ordering against a bare numeric string.
/// Before the fix "v2.0" tokenized as `.text("v")` first, and since text sorts
/// below numbers, "v2.0" compared as OLDER than "2.0" (and "2.0" as NEWER than
/// "v2.0") — a spurious update in one direction, a missed update in the other.
@Test func vPrefixDoesNotInvertOrdering() {
    #expect(VersionComparator.compare("v2.0", "2.0") == .orderedSame)
    #expect(VersionComparator.compare("2.0", "v2.0") == .orderedSame)
    #expect(VersionComparator.compare("V1.4.3", "1.4.3") == .orderedSame)
    #expect(VersionComparator.isNewer("v2.1", than: "2.0"))
    #expect(VersionComparator.isNewer("2.1", than: "v2.0"))
    #expect(!VersionComparator.isNewer("v2.0", than: "2.1"))
    // A bare "v" with no trailing digit is left alone (still a text token).
    #expect(VersionComparator.compare("v", "v") == .orderedSame)
}

@Test func evaluatePrefersBuildVersion() {
    let app = InstalledApp(
        name: "X", bundleID: "x", shortVersion: "1.0", buildVersion: "100",
        path: .init(fileURLWithPath: "/X.app"), isMASApp: false, sparkleFeedURL: nil
    )
    let remote = RemoteVersion(
        shortVersion: "1.1", version: "110", downloadURL: nil, sourceName: "Test"
    )
    #expect(UpdateChecker.evaluate(installed: app, remote: remote) == .updateAvailable(latest: "1.1"))
}

/// A vendor that folds the build into its version string (Oray AweSun:
/// "16.5.0.30757") must compare equal to a bundle that splits it into short
/// "16.5.0" + build "30757" — otherwise the row shows a perpetual update even
/// right after a successful install. The probe has no separate build version
/// (remote.version == nil), so this exercises the short-version fallback.
@Test func evaluateFoldsBuildIntoVendorVersion() {
    func aweSun(short: String, build: String) -> InstalledApp {
        InstalledApp(
            name: "AweSun", bundleID: "com.oray.sunlogin.macclient",
            shortVersion: short, buildVersion: build,
            path: .init(fileURLWithPath: "/AweSun.app"), isMASApp: false, sparkleFeedURL: nil)
    }
    let remote = RemoteVersion(
        shortVersion: "16.5.0.30757", version: nil, downloadURL: nil, sourceName: "Vendor")

    // Installed == target (short 16.5.0 + build 30757) → current, not "update".
    #expect(UpdateChecker.evaluate(installed: aweSun(short: "16.5.0", build: "30757"), remote: remote)
        == .upToDate)
    // Older build of the same marketing version → still detected.
    #expect(UpdateChecker.evaluate(installed: aweSun(short: "16.5.0", build: "30000"), remote: remote)
        == .updateAvailable(latest: "16.5.0.30757"))
    // Older marketing version → still detected.
    #expect(UpdateChecker.evaluate(installed: aweSun(short: "16.3.0", build: "29530"), remote: remote)
        == .updateAvailable(latest: "16.5.0.30757"))
}

/// The build-folding fallback must NOT make a genuinely-behind normal app (whose
/// short version is simply older) look current.
@Test func evaluateBuildFoldingDoesNotMaskRealUpdate() {
    let app = InstalledApp(
        name: "X", bundleID: "x", shortVersion: "1.96.0", buildVersion: "171",
        path: .init(fileURLWithPath: "/X.app"), isMASApp: false, sparkleFeedURL: nil)
    let remote = RemoteVersion(
        shortVersion: "1.97.0", version: nil, downloadURL: nil, sourceName: "Vendor")
    #expect(UpdateChecker.evaluate(installed: app, remote: remote)
        == .updateAvailable(latest: "1.97.0"))
}

// MARK: - Pair comparison

/// The primitive every converted decision site now calls. Worth pinning
/// directly: thirteen call sites delegate their correctness to these three
/// functions, so a regression here is a regression everywhere at once.
@Suite struct VersionSidePairTests {

    private func s(_ m: String?, _ b: String?) -> VersionSide {
        VersionSide(marketing: m, build: b)
    }

    /// Marketing decides when it moves — the ordinary case.
    @Test func marketingDecidesWhenItMoves() {
        #expect(VersionComparator.isNewer(s("1.8.0", "10"), than: s("1.7.3", "999")),
                "a marketing bump wins even when the build number went down")
        #expect(!VersionComparator.isNewer(s("1.7.3", "999"), than: s("1.8.0", "10")))
    }

    /// The build decides only when marketing ties — which for a frozen-marketing
    /// app is every comparison it will ever make.
    @Test func theBuildBreaksAFrozenMarketingTie() {
        #expect(VersionComparator.isNewer(s("1.0", "130"), than: s("1.0", "129")))
        #expect(!VersionComparator.isNewer(s("1.0", "129"), than: s("1.0", "130")))
        #expect(!VersionComparator.isNewer(s("1.0", "130"), than: s("1.0", "130")))
    }

    /// Never across namespaces: a build ("45830") and a marketing version
    /// ("1.96.0") are not on one scale, so a side missing its marketing string is
    /// compared build-to-build or not at all.
    @Test func neverComparesABuildAgainstAMarketingVersion() {
        #expect(!VersionComparator.isNewer(s(nil, "45830"), than: s("1.96.0", nil)),
                "45830 must not be read as newer than 1.96.0")
        #expect(!VersionComparator.isNewer(s("1.96.0", nil), than: s(nil, "45830")))
        #expect(VersionComparator.isNewer(s(nil, "45830"), than: s(nil, "45829")),
                "build-to-build is fine")
    }

    /// "Cannot tell" fails closed. Callers use this to decide whether to offer an
    /// update, wait for a swap, or overwrite an install; guessing "newer" there
    /// is the expensive direction.
    @Test func nothingComparableIsNotNewer() {
        #expect(!VersionComparator.isNewer(VersionSide(), than: s("1.0", "1")))
        #expect(!VersionComparator.isNewer(s("1.0", "1"), than: VersionSide()))
        #expect(!VersionComparator.isNewer(VersionSide(), than: VersionSide()))
    }

    /// `isSame` requires every field BOTH sides carry to agree, and refuses to
    /// call two incomparable sides equal.
    @Test func isSameNeedsEveryComparableFieldToAgree() {
        #expect(VersionComparator.isSame(s("1.0", "130"), as: s("1.0", "130")))
        #expect(!VersionComparator.isSame(s("1.0", "129"), as: s("1.0", "130")),
                "the marketing halves match; the builds do not")
        #expect(VersionComparator.isSame(s("1.0", nil), as: s("1.0", "130")),
                "a field missing on one side proves nothing and is skipped")
        #expect(!VersionComparator.isSame(VersionSide(), as: s("1.0", "130")),
                "nothing comparable is not sameness")
    }

    /// `hasReached` is the landing test: the exact build, or one past it.
    @Test func hasReachedAcceptsTheTargetOrAnythingPastIt() {
        let target = s("1.0", "130")
        #expect(!VersionComparator.hasReached(target, disk: s("1.0", "129")))
        #expect(VersionComparator.hasReached(target, disk: s("1.0", "130")))
        #expect(VersionComparator.hasReached(target, disk: s("1.0", "131")))
    }

    /// Two spellings `compare` calls equal must be equal to `isSame` too, and
    /// therefore to `hasReached`. `isSame` used raw string `==`, so a feed that
    /// said `v1.2.3` against a plist that said `1.2.3` (or `1.0` against `1.0.0`,
    /// `1.02` against `1.2`) was "not newer" AND "not the same": a staged package
    /// read as not the offered version, and a swap landing test that could never
    /// conclude.
    @Test(arguments: [
        ("1.0.0", "1.0"),
        ("1.0", "1.0.0"),
        ("v2.0", "2.0"),
        ("V1.4.3", "1.4.3"),
        ("1.02", "1.2"),
        ("1.007", "1.7"),
        ("007", "7"),
    ])
    func isSameAgreesWithCompareOnEquivalentSpellings(a: String, b: String) {
        #expect(VersionComparator.compare(a, b) == .orderedSame,
                "precondition: the tokenizer must call these equal")
        // Marketing respelled, build identical — the shape that bit.
        #expect(VersionComparator.isSame(s(a, "130"), as: s(b, "130")))
        #expect(VersionComparator.hasReached(s(a, "130"), disk: s(b, "130")))
        // Marketing only (a side with no build).
        #expect(VersionComparator.isSame(s(a, nil), as: s(b, nil)))
        #expect(VersionComparator.hasReached(s(a, nil), disk: s(b, nil)))
        // The build half goes through the same tokenizer.
        #expect(VersionComparator.isSame(s("1.0", a), as: s("1.0", b)))
    }

    /// The tokenizer must not make `isSame` looser than "same build": a real
    /// difference on any comparable field is still a difference, and an
    /// incomparable pair is still not sameness.
    @Test func tokenizedIsSameStillRejectsRealDifferences() {
        #expect(!VersionComparator.isSame(s("1.0.1", "130"), as: s("1.0", "130")),
                "different marketing")
        #expect(!VersionComparator.isSame(s("v2.0", "130"), as: s("2.0", "131")),
                "same marketing, spelled differently, but the builds differ")
        #expect(!VersionComparator.isSame(s("2.0", nil), as: s("2.0-beta1", nil)),
                "a release is not its own pre-release")
        #expect(!VersionComparator.isSame(VersionSide(), as: s("v1.0", "1")),
                "one side empty")
        #expect(!VersionComparator.isSame(s("1.0", nil), as: s(nil, "1")),
                "nothing comparable across the two sides")
        // hasReached keeps its other half: disk past the target still counts.
        #expect(VersionComparator.hasReached(s("v2.0", "130"), disk: s("2.0", "131")))
        #expect(!VersionComparator.hasReached(s("v2.0", "131"), disk: s("2.0", "130")))
    }

    /// `hasReached` must stay `isSame || isNewer`, not "disk is not behind".
    ///
    /// Issue #221 offers `!isNewer(target, than: disk)` as an equivalent
    /// rewrite. It is not, and nothing above catches the difference: with the
    /// rewrite in place every other expectation in this file still passes. The
    /// two forms agree wherever both sides carry a comparable field and part
    /// company exactly where nothing is comparable — `isNewer` answers "cannot
    /// tell" as `false`, so negating it turns "cannot tell" into "landed".
    /// That is the fail-open direction on a swap-landing test: `RelaunchProgress`
    /// would call an unreadable bundle arrived and stop waiting.
    @Test func hasReachedFailsClosedWhenNothingIsComparable() {
        #expect(!VersionComparator.hasReached(s("1.0", "130"), disk: VersionSide()))
        #expect(!VersionComparator.hasReached(VersionSide(), disk: VersionSide()))
        #expect(!VersionComparator.hasReached(s("1.0", nil), disk: s(nil, "1")),
                "marketing against a build is not a comparison")
        #expect(!VersionComparator.hasReached(s(nil, "130"), disk: s("1.0", nil)))
    }

    /// The tokenizer's separator class is wider than the `v`-prefix and
    /// zero-padding cases above: `.`, `-`, `_`, `+`, a space and parentheses are
    /// all one separator, so these pairs are equal too. Pinned not because any
    /// vendor is known to ship two of them as different builds, but so the next
    /// reader sees the real size of what `isSame` now calls the same — macOS
    /// writes builds as `1.0 (123)` by convention, and that shape is in here.
    @Test func theSeparatorClassIsPartOfWhatIsSameNowAccepts() {
        for (a, b) in [("1.0-1", "1.0.1"), ("1.0 (1)", "1.0.1"), ("1.0_1", "1.0-1"),
                       ("3.5.0(1234)", "3.5.0.1234"), ("1.0.0+1", "1.0.0.1")] {
            #expect(VersionComparator.compare(a, b) == .orderedSame, "\(a) vs \(b)")
            #expect(VersionComparator.isSame(s("1.0", a), as: s("1.0", b)), "builds \(a) vs \(b)")
        }
    }
}
