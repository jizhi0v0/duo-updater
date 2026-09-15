import Testing
import Foundation
@testable import DuoKit

/// `SourceStamp` decides whether a `duo verify` sweep is about the reader's recipes or
/// about whatever was compiled into the binary on PATH. Every case below names the line
/// it pins and was run against that line removed — see the comment on each.
@Suite struct SourceStampTests {

    /// A checkout-shaped tree: every source root present, and enough files to clear the
    /// floor. The bodies are unique so a digest that skipped content still gets a
    /// different byte count, which would let `contentChangeMovesTheDigest` pass for the
    /// wrong reason — so that test rewrites a file to the SAME length.
    private func makeTree(files: Int = SourceStamp.minimumFiles + 5) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceStampTest-\(UUID().uuidString)")
        for (index, relative) in SourceStamp.sourceRoots.enumerated() {
            let directory = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            // Only the first root is filled: the floor is about the total, and a case
            // below empties one root entirely to check the root is still required.
            guard index == 0 else { continue }
            for i in 0..<files {
                try "let n\(i) = \(String(format: "%06d", i))\n"
                    .write(to: directory.appendingPathComponent("F\(i).swift"),
                           atomically: true, encoding: .utf8)
            }
        }
        return root
    }

    /// The point of the whole file. Mutation: hash only the path and the length, not the
    /// bytes — this goes green while the digest stops noticing edited recipes, which is
    /// the exact failure it exists to catch.
    @Test func contentChangeMovesTheDigest() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try SourceStamp.digest(ofCheckoutAt: root)

        // Same length, different bytes: a digest that only weighed sizes would miss it.
        let file = root.appendingPathComponent(SourceStamp.sourceRoots[0] + "/F3.swift")
        let original = try String(contentsOf: file, encoding: .utf8)
        try original.replacingOccurrences(of: "000003", with: "999999")
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(try original.count == String(contentsOf: file, encoding: .utf8).count)

        #expect(try SourceStamp.digest(ofCheckoutAt: root) != before)
    }

    /// Mutation: drop `relative` from the hashed preamble. Renaming a recipe file — or
    /// moving one between roots — then leaves the digest unchanged, so a binary built
    /// before the move reads as current.
    @Test func renamingAFileMovesTheDigest() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try SourceStamp.digest(ofCheckoutAt: root)

        let directory = root.appendingPathComponent(SourceStamp.sourceRoots[0])
        try FileManager.default.moveItem(
            at: directory.appendingPathComponent("F3.swift"),
            to: directory.appendingPathComponent("Renamed.swift"))

        #expect(try SourceStamp.digest(ofCheckoutAt: root) != before)
    }

    /// Two trees with identical content must agree even though they were created in a
    /// different order and live at different paths. Mutation: remove `.sorted` — this
    /// goes red as soon as `enumerator` hands the two trees back differently, which is
    /// the flake that would teach everyone to pass `--allow-stale-binary`. Paths are
    /// relative for the same reason: absolute ones would make every worktree disagree.
    @Test func twoIdenticalCheckoutsAgree() throws {
        let a = try makeTree()
        let b = try makeTree()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
        #expect(try SourceStamp.digest(ofCheckoutAt: a)
                == SourceStamp.digest(ofCheckoutAt: b))
    }

    /// Mutation: delete the `files.count >= minimumFiles` guard. A renamed source root
    /// then digests zero files — and, being empty on both sides, agrees with itself, so
    /// the gate reports "matches" forever while checking nothing.
    @Test func aTreeThatLostItsSourcesIsAnError() throws {
        let root = try makeTree(files: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: SourceStamp.StampError.self) {
            try SourceStamp.digest(ofCheckoutAt: root)
        }
    }

    /// Mutation: return `directory` on the first iteration instead of walking up. `duo
    /// verify` is normally run from the repository root, so a test that only checked the
    /// root would pass — this one starts three levels down, which is where the skill's
    /// recipe work happens.
    @Test func theCheckoutIsFoundFromASubdirectory() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent(SourceStamp.sourceRoots[0] + "/a/b")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

        #expect(SourceStamp.checkoutRoot(from: deep)?.standardizedFileURL.path
                == root.standardizedFileURL.path)
    }

    /// A directory carrying only one source root is not a checkout this can compare
    /// against. Mutation: `allSatisfy` -> `contains` — a stray `CLI/Sources` anywhere
    /// above then claims to be the repository and the digest is taken over a fragment.
    @Test func aPartialTreeIsNotACheckout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceStampPartial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(SourceStamp.sourceRoots[0]),
            withIntermediateDirectories: true)

        #expect(SourceStamp.checkoutRoot(from: root) == nil)
    }

    /// Run from anywhere that is not a checkout there is nothing to be stale against,
    /// and refusing would break `duo verify` for everyone who is not developing it.
    @Test func outsideACheckoutTheGateStandsDown() {
        #expect(SourceStamp.verdict(root: nil, stamp: nil) == .notApplicable)
    }

    /// The three verdicts that matter, over one tree. `.stale` for a missing stamp is
    /// the case that upgrades every binary built before this existed: unknown provenance
    /// is not the same as good provenance, and the fix for both is one `make cli`.
    @Test func theStampDecidesTheVerdict() throws {
        let root = try makeTree()
        let stamp = root.appendingPathComponent("duo.built-from")
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(SourceStamp.verdict(root: root, stamp: stamp) != .matches)

        try SourceStamp.digest(ofCheckoutAt: root)
            .write(to: stamp, atomically: true, encoding: .utf8)
        #expect(SourceStamp.verdict(root: root, stamp: stamp) == .matches)

        // Whitespace is not drift: the stamp is written by a shell redirect, which
        // leaves a trailing newline that `verdict` has to tolerate.
        try (try SourceStamp.digest(ofCheckoutAt: root) + "\n")
            .write(to: stamp, atomically: true, encoding: .utf8)
        #expect(SourceStamp.verdict(root: root, stamp: stamp) == .matches)

        try "not a digest".write(to: stamp, atomically: true, encoding: .utf8)
        #expect(SourceStamp.verdict(root: root, stamp: stamp) != .matches)
    }
}
