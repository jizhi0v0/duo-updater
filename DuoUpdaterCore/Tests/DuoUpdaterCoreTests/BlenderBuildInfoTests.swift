import Foundation
import Testing
@testable import DuoUpdaterCore

/// The bytes `BlenderBuildInfo` reads, as they sit in the four builds the audit
/// mounted (2026-09-25): the C string literals around `blender_version_init()`'s
/// two format strings, and `buildinfo.c`'s globals before the platform. Each is
/// copied from the real binary, NULs and padding included; only the surrounding
/// megabytes are left out.
private enum Layout {
    static let formats = "%d.%01d.%d%s%s\0%d.%01d.%d%s\0warning: registered duplicate c"

    static let release = "List Item\0%d.%d (sub %d)\0blender.crash.txt\0.crash.txt\0 LTS\0" + formats
    static let beta = "blender.crash.txt\0.crash.txt\0 Beta\0 b\0 LTS\0" + formats
    static let candidate = "blender.crash.txt\0.crash.txt\0 Release Candidate\0 RC\0 LTS\0" + formats
    static let alpha = "blender.crash.txt\0.crash.txt\0 Alpha\0 a\0" + formats

    /// `buildinfo.c`'s globals as the linker lays them out: three strings, the
    /// commit's alignment padding, the 8-byte `build_commit_timestamp` (these are
    /// 5.2.2's bytes), then the branch, the platform and the build type.
    static func buildInfo(date: String, time: String, commit: String, branch: String) -> Data {
        Data("write_through\0year\0zdict\0\(date)\0\(time)\0\(commit)\0".utf8)
            + Data([0, 0, 0, 0, 0, 0, 0, 0x3e, 0x0f, 0xa8, 0x6a, 0, 0, 0, 0])
            + Data("\(branch)\0Darwin\0Release\0 -Wall".utf8)
    }

    /// A body shaped like the executable: unrelated strings, the cycle literals,
    /// more unrelated strings, the build info. `" Alpha"` also appears on its
    /// own, as it does in every build.
    static func binary(_ cycle: String, date: String, time: String, commit: String, branch: String) -> Data {
        Data(("\u{1}\u{2}junk\0 Alpha\0Darwin\0other\0" + cycle + "\0\0filler\0").utf8)
            + buildInfo(date: date, time: time, commit: commit, branch: branch)
    }
}

struct BlenderBuildInfoTests {

    @Test func readsTheReleaseBuild() {
        let info = BlenderBuildInfo.parse(Layout.binary(
            Layout.release, date: "2026-09-15", time: "01:49:19",
            commit: "d13f752e3b9c", branch: "blender-v5.2-release"))
        #expect(info.cycle == .release)
        #expect(info.channel == .stable)
        #expect(info.commit == "d13f752e3b9c")
        #expect(info.branch == "blender-v5.2-release")
        #expect(info.builtAt == Date(timeIntervalSince1970: 1_789_436_959))  // 2026-09-15 01:49:19 UTC
        #expect(info.trackCommit == "d13f752e3b9c")
    }

    @Test func readsBetaAndCandidateFromTheSameReleaseBranch() {
        let beta = BlenderBuildInfo.parse(Layout.binary(
            Layout.beta, date: "2026-07-08", time: "01:34:43",
            commit: "4481d59ccf4e", branch: "blender-v5.2-release"))
        #expect(beta.channel == .beta)
        #expect(beta.trackCommit == "4481d59ccf4e")

        let candidate = BlenderBuildInfo.parse(Layout.binary(
            Layout.candidate, date: "2026-08-24", time: "01:31:02",
            commit: "5adcd79a574f", branch: "blender-v5.2-release"))
        #expect(candidate.channel == .rc)
        #expect(candidate.trackCommit == "5adcd79a574f")
    }

    @Test func readsTheAlphaFromMain() {
        let alpha = BlenderBuildInfo.parse(Layout.binary(
            Layout.alpha, date: "2026-09-25", time: "01:35:56",
            commit: "425ab43ad645", branch: "main"))
        #expect(alpha.channel == .alpha)
        #expect(alpha.trackCommit == "425ab43ad645")
    }

    /// An alpha-cycle build from anywhere but `main` (an experimental branch, a
    /// pull-request build) is not on the builder's alpha track: it keeps its
    /// channel but has no track commit, so the engine says "cannot tell" instead
    /// of offering to replace it with `main`'s newest build.
    @Test func anOffTrackBranchHasNoTrackCommit() {
        let experimental = BlenderBuildInfo.parse(Layout.binary(
            Layout.alpha, date: "2026-09-25", time: "01:35:56",
            commit: "425ab43ad645", branch: "cycles-light-linking"))
        #expect(experimental.channel == .alpha)
        #expect(experimental.trackCommit == nil)

        let candidateOffBranch = BlenderBuildInfo.parse(Layout.binary(
            Layout.candidate, date: "2026-08-24", time: "01:31:02",
            commit: "5adcd79a574f", branch: "main"))
        #expect(candidateOffBranch.trackCommit == nil)
    }

    /// The cycle pair only counts next to the format strings: a stray `" Beta"`
    /// elsewhere must not turn a release into a beta.
    @Test func aCycleWordAwayFromTheFormatsIsIgnored() {
        let data = Data(("x\0 Beta\0 b\0y\0" + Layout.release).utf8)
        #expect(BlenderBuildInfo.cycle(in: data) == .release)
    }

    /// No format strings at all: no claim, so the ordinary detection stands.
    @Test func noAnchorClaimsNothing() {
        let info = BlenderBuildInfo.parse(Data("nothing to see\0Darwin\0".utf8))
        #expect(info.cycle == nil)
        #expect(info.channel == nil)
        #expect(info.commit == nil)
        #expect(info.trackCommit == nil)
    }
}
