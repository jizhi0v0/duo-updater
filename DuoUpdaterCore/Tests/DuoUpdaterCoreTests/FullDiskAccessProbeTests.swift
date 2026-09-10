import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite("FullDiskAccessProbe")
struct FullDiskAccessProbeTests {
    typealias P = FullDiskAccessProbe

    /// One file that opens is the grant, whatever the others say. Mutation:
    /// require every open to succeed — a Mac with no Safari data, or a `700` TCC
    /// directory, would never read as granted.
    @Test func oneFileThatOpensIsTheGrant() {
        #expect(P.verdict([EPERM, nil, ENOENT, EACCES]) == .granted)
    }

    /// TCC's refusal is `EPERM`. Mutation: drop the `EPERM` branch — a Mac without
    /// the grant falls through to preflight, the answer frozen at launch that this
    /// exists to replace.
    @Test func anEPERMIsTheRefusal() {
        #expect(P.verdict([EPERM, EPERM, EPERM, ENOENT]) == .denied)
    }

    /// Mutation: count `EACCES` as a refusal — on a Mac whose TCC directory is
    /// `700` and that has no Safari data, a granted DuoUpdater reads as denied.
    @Test func missingFilesAndFilePermissionsSayNothing() {
        #expect(P.verdict([EACCES, ENOENT, ENOENT, ENOENT]) == .inconclusive)
        #expect(P.verdict([]) == .inconclusive)
    }

    /// The opens themselves, on invented paths — never a real protected file, so
    /// the answer cannot depend on this Mac's grants. Mutation: report every path
    /// as refused (or every one as opened) — one of the two lines fails.
    @Test func opensAreReportedPerPath() throws {
        let missing = "/private/var/empty/ZZFixture-fda-missing"
        #expect(!FileManager.default.fileExists(atPath: missing))
        let present = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-fda-\(UUID().uuidString)").path
        try Data("x".utf8).write(to: URL(fileURLWithPath: present))
        defer { try? FileManager.default.removeItem(atPath: present) }

        #expect(P.openResults([missing, present]) == [ENOENT, nil])
        #expect(P.verdict(P.openResults([missing])) == .inconclusive)
    }

    /// Derived from the list: none of it is another app's container, whose read
    /// without the grant can prompt or post a notice. Mutation: add a
    /// `~/Library/Containers/…` path — this fails and names it.
    @Test func noProbedPathIsAnotherAppsContainer() {
        #expect(!P.defaultPaths.isEmpty)
        for path in P.defaultPaths {
            #expect(!path.contains("/Library/Containers/"), "\(path)")
            #expect(!path.contains("/Library/Group Containers/"), "\(path)")
        }
    }
}
