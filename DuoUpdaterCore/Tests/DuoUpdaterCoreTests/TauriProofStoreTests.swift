import Testing
import Foundation
@testable import DuoUpdaterCore

/// `TauriProofStore` in isolation — two instances pointed at the same file,
/// modelling two processes sharing it, rather than the global `.shared`
/// singleton `RuntimeVersion` calls through. See `RuntimeVersionTests` for the
/// tests that exercise `.shared` through `RuntimeVersion.read`.
struct TauriProofStoreTests {

    /// A fresh, never-before-used path per test, so tests cannot see each
    /// other's writes.
    private func scratchFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tauri-proof-store-test-\(UUID().uuidString)")
            .appendingPathComponent("tauri-proofs.json")
    }

    @Test func aFoundVersionRoundTripsThroughAnotherInstance() {
        let file = scratchFile(); defer { try? FileManager.default.removeItem(at: file) }
        let writer = TauriProofStore(fileURL: file)
        writer.record("2.11.5", forBundleAt: "/Applications/Shell.app", identity: "100-1700000000.0")

        // A second instance, not the one that wrote — the point being tested
        // is the file, not whatever the writer kept in memory.
        let reader = TauriProofStore(fileURL: file)
        #expect(reader.lookup(forBundleAt: "/Applications/Shell.app", identity: "100-1700000000.0")
            == .some("2.11.5"))
    }

    /// `.some(nil)` — a recorded "no crate found" — must come back distinct
    /// from "no record at all", which is plain `nil`. Collapsing the two would
    /// make a proved absence indistinguishable from a bundle nobody has asked
    /// about, and `RuntimeVersion` relies on telling them apart to avoid
    /// re-walking a binary that was already proved not to be Tauri.
    @Test func anAbsentVerdictRoundTripsAsSomeNilNotAsNoRecord() {
        let file = scratchFile(); defer { try? FileManager.default.removeItem(at: file) }
        let writer = TauriProofStore(fileURL: file)
        writer.record(nil, forBundleAt: "/Applications/Shell.app", identity: "id-1")

        let reader = TauriProofStore(fileURL: file)
        let answer = reader.lookup(forBundleAt: "/Applications/Shell.app", identity: "id-1")
        #expect(answer != nil, "a recorded absence is a record, not the lack of one")
        #expect(answer == .some(nil))
    }

    @Test func aChangedIdentityIsNotAHit() {
        let file = scratchFile(); defer { try? FileManager.default.removeItem(at: file) }
        let writer = TauriProofStore(fileURL: file)
        writer.record("2.11.5", forBundleAt: "/Applications/Shell.app", identity: "id-1")

        let reader = TauriProofStore(fileURL: file)
        #expect(reader.lookup(forBundleAt: "/Applications/Shell.app", identity: "id-2") == nil,
                "a bundle rewritten under the same path must be a fresh question, not a stale hit")
    }

    @Test func aCorruptFileReadsAsEmptyRatherThanThrowing() throws {
        let file = scratchFile(); defer { try? FileManager.default.removeItem(at: file) }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: file)

        let store = TauriProofStore(fileURL: file)
        #expect(store.lookup(forBundleAt: "/Applications/Anything.app", identity: "id") == nil)

        // And a store that read a corrupt file can still write — the failure
        // must not be sticky.
        store.record("1.0.0", forBundleAt: "/Applications/Anything.app", identity: "id")
        #expect(TauriProofStore(fileURL: file)
            .lookup(forBundleAt: "/Applications/Anything.app", identity: "id") == .some("1.0.0"))
    }

    /// A record stamped by a different `TauriProofStore.proverGeneration` must
    /// not be trusted — the same rule `Changelog.parserGeneration` already
    /// enforces, and for the identical reason: it might have been produced by
    /// a `probe`/`firstVersion` rule this build no longer agrees with.
    @Test func aRecordWrittenUnderAnOldGenerationIsIgnored() throws {
        let file = scratchFile(); defer { try? FileManager.default.removeItem(at: file) }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staleGeneration = TauriProofStore.proverGeneration - 1
        let json = """
        {"generation": \(staleGeneration), "entries": \
        {"/Applications/Old.app": {"identity": "id-1", "version": "9.9.9"}}}
        """
        try Data(json.utf8).write(to: file)

        let store = TauriProofStore(fileURL: file)
        #expect(store.lookup(forBundleAt: "/Applications/Old.app", identity: "id-1") == nil,
                "a record stamped with a different proverGeneration must not be trusted")
    }

    /// A file predating the generation field entirely — the flat
    /// `[path: Entry]` shape this store originally shipped with, before this
    /// review round added the stamp — must be treated exactly the same as a
    /// generation mismatch: fails to decode against `FileContents` and reads
    /// as empty, not as a trusted pre-generation store.
    @Test func aFileFromBeforeTheGenerationFieldExistedIsIgnored() throws {
        let file = scratchFile(); defer { try? FileManager.default.removeItem(at: file) }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        {"/Applications/Old.app": {"identity": "id-1", "version": "9.9.9"}}
        """
        try Data(json.utf8).write(to: file)

        let store = TauriProofStore(fileURL: file)
        #expect(store.lookup(forBundleAt: "/Applications/Old.app", identity: "id-1") == nil,
                "a pre-generation file must not be trusted")
    }

    @Test func aSecondWriterMergesRatherThanOverwritingTheFirstsEntry() {
        // Models two processes recording two different bundles against the
        // same file without either instance having read the other's write
        // first — the shape `record`'s read-before-write exists for.
        let file = scratchFile(); defer { try? FileManager.default.removeItem(at: file) }
        let first = TauriProofStore(fileURL: file)
        first.record("2.11.5", forBundleAt: "/Applications/A.app", identity: "id-a")

        let second = TauriProofStore(fileURL: file)
        second.record("3.0.0", forBundleAt: "/Applications/B.app", identity: "id-b")

        let reader = TauriProofStore(fileURL: file)
        #expect(reader.lookup(forBundleAt: "/Applications/A.app", identity: "id-a") == .some("2.11.5"),
                "the second writer's record must not have clobbered the first's")
        #expect(reader.lookup(forBundleAt: "/Applications/B.app", identity: "id-b") == .some("3.0.0"))
    }

    /// `.shared` resolves `resolvedFileURL` once, at construction — see the
    /// doc comment there for the real incident (an `EventStoreTests` `defer`
    /// bug) that motivated it. This is what proves the fix: touch `.shared`
    /// once to force resolution (idempotent — later calls just read the same
    /// stored value), then change `DUO_STATE_DIR` and confirm the resolved
    /// path did not move.
    ///
    /// Deliberately does not assert anything about what `resolvedBefore` IS —
    /// only that a later `setenv` cannot change it. `.shared` may already
    /// have been touched by another test in this process by the time this
    /// one runs, which is fine and expected; it is exactly the "touched at an
    /// effectively random point" shape the doc comment describes.
    @Test func sharedsResolvedPathIsFixedRegardlessOfLaterDUOStateDirChanges() {
        let resolvedBefore = TauriProofStore.shared.resolvedFileURL

        let previous = ProcessInfo.processInfo.environment["DUO_STATE_DIR"]
        setenv("DUO_STATE_DIR", "/tmp/duo-tauri-should-never-be-read-\(UUID().uuidString)", 1)
        defer {
            if let previous { setenv("DUO_STATE_DIR", previous, 1) } else { unsetenv("DUO_STATE_DIR") }
        }

        #expect(TauriProofStore.shared.resolvedFileURL == resolvedBefore,
                ".shared must not re-resolve its file location after a later DUO_STATE_DIR change")
    }
}
