import Testing
import Foundation
@testable import DuoUpdaterCore

/// The mechanical guard `TauriProofStore.proverGeneration` needed but didn't
/// have — the same shape `ChangelogParserGenerationGuardTests` already gives
/// `Changelog.parserGeneration`, for the identical reason: a hand-maintained
/// "bump this when X changes" comment is not enforced by anything on its own,
/// so a change to `RuntimeVersion.probe`/`firstVersion` that alters what an
/// ALREADY-PROVED bundle's verdict would come out as could ship without
/// anyone touching the generation number — and every value `TauriProofStore`
/// already has on disk for that bundle would then silently go stale-WRONG
/// (an old build's crate-path rules, misapplied forever to that one bundle)
/// instead of stale-safe.
///
/// Three fixtures, chosen to jointly cover every trigger
/// `TauriProofStore.proverGeneration`'s doc comment lists, driven directly
/// through `RuntimeVersion.probe(reading:for:components:)` rather than
/// through a real bundle on disk — the same choice the "driven through its
/// own seam" section of `RuntimeVersionTests` already makes, and for the same
/// reason: it is the only way to place a payload exactly on a chunk boundary
/// without depending on `FileHandle`'s own read sizes.
///
/// - a plain `tauri-<version>` match — the needle prefix and the digit-run
///   rule in `firstVersion`;
/// - a wry-only binary, which must read as `.absent` — the identifier guard
///   that is the entire reason `.tauri` needs a whole-binary walk to prove
///   absence rather than stopping at "not found in this chunk";
/// - a version cut by a chunk boundary, at the REAL `RuntimeVersion.scanChunkSize`
///   — the window/carry/`isFinal` logic that `scanOverlap` and `scanChunkSize`
///   feed.
///
/// A change to any of those moves this test. The fix is always the same
/// two-part edit: bump `TauriProofStore.proverGeneration` (with a one-line log
/// entry on its doc comment) and update the expected value below to match —
/// exactly the discipline `ChangelogParserGenerationGuardTests` already
/// documents for its own generation number.
@Suite struct TauriProverGenerationGuardTests {

    /// Pinned alongside the three fixture checks below on purpose: bumping the
    /// generation without touching this file is still *possible* (nothing
    /// forces them to be edited in the same commit), but keeping them next to
    /// each other means a reviewer scanning this file sees both move together.
    @Test func pinnedGeneration() {
        #expect(TauriProofStore.proverGeneration == 1)
    }

    @Test func aPlainCratePathIsFound() {
        let outcome = chunks(["junk/registry/src/index/tauri-2.11.5/src/lib.rsmore junk"])
        #expect(outcome == .found("2.11.5"),
                "if this is an intentional change, bump TauriProofStore.proverGeneration")
    }

    @Test func aWryOnlyBinaryIsProvedAbsentNotFound() {
        let outcome = chunks([
            "registry/src/index/wry-0.53.3/src/lib.rs and tauri-runtime-wry-2.11.4/src/lib.rs",
        ])
        #expect(outcome == .absent,
                "if this is an intentional change, bump TauriProofStore.proverGeneration")
    }

    /// `tauri-2.11.50` split so the boundary falls between the `5` and the
    /// `0`, at the exact `scanChunkSize` a real file read would split on —
    /// not a toy chunk size, so a change to that constant moves this test too.
    @Test func aVersionCutByTheRealChunkBoundaryIsReadWhole() {
        let chunkSize = RuntimeVersion.scanChunkSize
        let splitPrefix = " tauri-2.11.5"
        let firstChunk = Data(repeating: UInt8(ascii: "."), count: chunkSize - splitPrefix.utf8.count)
            + Data(splitPrefix.utf8)
        let secondChunk = Data("0 ".utf8)

        let outcome = chunks(bytes: [firstChunk, secondChunk])
        #expect(outcome == .found("2.11.50"),
                "if this is an intentional change, bump TauriProofStore.proverGeneration")
    }

    private func chunks(_ strings: [String]) -> RuntimeVersion.Probe {
        chunks(bytes: strings.map { Data($0.utf8) })
    }

    private func chunks(bytes: [Data]) -> RuntimeVersion.Probe {
        var remaining = bytes
        return RuntimeVersion.probe(
            reading: {
                guard !remaining.isEmpty else { return nil }
                return remaining.removeFirst()
            },
            for: "tauri-", components: 3)
    }
}
