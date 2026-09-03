import Testing
@testable import DuoUpdaterCore

/// `VersionSide.plistVersionField` is the one place that decides whether a raw
/// `Info.plist` value counts as "a version" or as "nothing was declared" — see
/// issue #287. Every reader of `CFBundleShortVersionString` / `CFBundleVersion`
/// across the engine is supposed to funnel through it rather than repeating its
/// own `as? String` + emptiness check, because five independent copies of that
/// check had drifted into five different rules (one didn't trim, one didn't
/// check emptiness at all).
struct VersionSideTests {

    @Test func nilInputStaysNil() {
        #expect(VersionSide.plistVersionField(nil) == nil)
    }

    @Test func nonStringInputIsNil() {
        // A plist can legally hold a number under either key (rare, but the
        // `as? String` cast already handled this — must keep doing so).
        #expect(VersionSide.plistVersionField(42) == nil)
    }

    @Test func emptyStringIsNil() {
        #expect(VersionSide.plistVersionField("") == nil)
    }

    @Test func whitespaceOnlyStringIsNil() {
        // The case that slipped past every reader except AppScanner's
        // shortVersion guard: "   " is non-empty by a bare `isEmpty` check, and
        // tokenizes identically to "" once inside `VersionComparator`.
        #expect(VersionSide.plistVersionField("   ") == nil)
        #expect(VersionSide.plistVersionField("\n\t ") == nil)
    }

    @Test func realVersionPassesThroughUnchanged() {
        #expect(VersionSide.plistVersionField("1.0") == "1.0")
    }

    @Test func realVersionIsTrimmedOfSurroundingWhitespace() {
        #expect(VersionSide.plistVersionField(" 1.0 ") == "1.0")
    }
}
