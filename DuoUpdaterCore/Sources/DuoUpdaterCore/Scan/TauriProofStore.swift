import Foundation

/// The disk half of `RuntimeVersion`'s Tauri cache — what lets the verdict a
/// process's binary walk reaches outlive that process.
///
/// `RuntimeVersion.cache` (see its doc comment) already remembers an answer for
/// the life of one process, keyed on the executable's size and modification
/// date. That is enough for the menu-bar app, which walks a candidate's binary
/// at most once per launch. It is not enough for `duo`: every invocation is a
/// fresh process, so without this store `duo list` re-walks every Tauri
/// candidate's executable on every call. Measured 2026-09-11 during review, on
/// a 14-core M3 Max under load: a cold Tauri sweep across this machine's
/// candidates took 400–730 ms of a 0.7–1.0 s `duo list` — a range, not a
/// promise about any other machine's population of Tauri apps, only about how
/// much of one `duo list` a repeated whole-binary walk can consume. This file
/// exists to make the second and later calls skip that walk entirely.
///
/// Only `.tauri` is stored here, and that is a decision made in
/// `RuntimeVersion.read`, not in this file — see the comment on its `cache` for
/// why Electron and Chromium's `nil` is not a verdict in the same sense and
/// must not be persisted past the process that reached it. This type has no
/// opinion about that; it just remembers whatever `record` is given, against
/// the same size-and-modification-date identity `RuntimeVersion` already uses,
/// so a rewritten binary (an update, or a scan racing an install) is silently a
/// new question rather than a stale hit.
///
/// One entry per bundle path. A new identity for a path overwrites the old
/// entry rather than adding beside it, so the file's size is bounded by "how
/// many bundles have ever been proved on this machine" — a few, since
/// `AppRuntimeDetector`'s filter is what limits which bundles ever reach here —
/// and needs no separate pruning pass.
final class TauriProofStore: @unchecked Sendable {

    /// `version` is `nil` for a proved absence ("no `tauri-` crate in this
    /// binary") — a real, expensive-to-reach answer, not the lack of one. There
    /// is deliberately no way to represent ".unreadable" here: `RuntimeVersion`
    /// never calls `record` for it, so the type does not need to say it either.
    struct Entry: Codable, Equatable {
        var identity: String
        var version: String?
    }

    /// The proof logic's generation, in the sense `Changelog.parserGeneration`
    /// already establishes for this package: every entry on disk is stamped
    /// with the generation that produced it, and a stored entry whose stamp
    /// does not match the running build's — including a file predating this
    /// field entirely, which fails to decode against `FileContents` below and
    /// is treated exactly the same as a mismatch — is not read back. Read the
    /// doc comment there first; the reasoning is identical, only the shape of
    /// "wrong" differs.
    ///
    /// Before this field, an app relaunch or a `duo` invocation cleared
    /// `RuntimeVersion.cache` for free, simply by ending the process that held
    /// it — so a fix to the byte-search rules below took effect the moment the
    /// new build ran. Once a verdict can outlive the build that computed it,
    /// that stops being true: a bug in `probe`/`firstVersion` (three of which
    /// review has already found in this exact file — see the doc comment on
    /// `RuntimeVersion.probe(reading:for:components:)`) would otherwise be
    /// baked into `~/Library/Application Support/com.duoupdater.app/`
    /// forever, or until the vendor app it misjudged happens to update.
    ///
    /// **Bump this whenever a change could alter what a PREVIOUSLY-proved
    /// bundle's verdict would come out as** — not merely a change that widens
    /// what a *newly-encountered* binary can match:
    /// - the needle prefix or component count `RuntimeVersion.read` passes to
    ///   `probe` for `.tauri`;
    /// - `firstVersion`'s rules: the digit run, the identifier guard, how a
    ///   component count is enforced, `isFinal`;
    /// - `probe`'s window/carry/boundary logic — `scanOverlap`, `scanChunkSize`,
    ///   or the loop that stitches chunks together.
    ///
    /// One line per bump — what changed and why:
    /// - 1: baseline, introduced with the field itself.
    static let proverGeneration = 1

    /// The on-disk shape: a generation stamp alongside the entries it stamps,
    /// so a mismatch — including the shape below, which has none at all — is a
    /// decode failure and therefore an empty store rather than a partially
    /// trusted one.
    private struct FileContents: Codable {
        var generation: Int
        var entries: [String: Entry]
    }

    /// The instance `RuntimeVersion` calls through. Production code should
    /// only ever touch this one; the `init(fileURL:)` override below exists for
    /// tests that model two processes sharing one file.
    ///
    /// `resolvedFileURL` is fixed at construction — see `init`'s doc comment
    /// for why that matters specifically for a singleton, and
    /// `TauriProofStoreTests.sharedsResolvedPathIsFixedRegardlessOfLaterDUOStateDirChanges`
    /// for the test that pins it.
    static let shared = TauriProofStore()

    private let lock = NSLock()

    /// Where this instance reads and writes, decided once, here, rather than
    /// re-read on every `lookup`/`record` call.
    ///
    /// That distinction only matters for `shared`, which is a process-wide
    /// singleton touched at an effectively random point across an entire
    /// `swift test` run — by tests that legitimately `setenv("DUO_STATE_DIR",
    /// ...)` for the duration of their own scope and restore it afterward. If
    /// this store re-resolved `DUO_STATE_DIR` on every access, two calls one
    /// test makes — `record` then `lookup`, say — could land on two different
    /// files if another suite's `setenv` fell in between. That is not
    /// hypothetical: `EventStoreTests` carried a `defer` that failed to
    /// restore `DUO_STATE_DIR` to "unset" when it had been unset before
    /// (fixed alongside this store), which meant every `TauriProofStore`
    /// access for the rest of the process silently read and wrote
    /// `/tmp/duo-state-test/com.duoupdater.app/tauri-proofs.json` — a file
    /// every worktree's test run shares — instead of its own scratch file.
    /// Resolving once, at construction, means `shared`'s target is decided
    /// before any of that can reach it, and cannot be moved afterward by
    /// anything another suite does to the environment.
    ///
    /// Every other on-disk store in this package also resolves once, at
    /// construction — the difference is only that they are built fresh per
    /// test or per short-lived caller, so "once" and "fresh enough" have
    /// always been the same thing for them. `shared` is the one long-lived
    /// exception, which is what made it worth writing down here.
    let resolvedFileURL: URL   // internal: asserted by TauriProofStoreTests

    init(fileURL: URL? = nil) {
        self.resolvedFileURL = fileURL ?? Self.defaultFileURL()
    }

    /// `nil` means "no record for this path at all". `.some(nil)` means "there
    /// is a record, and it says no crate was found" — the two must stay
    /// distinguishable, because the second is a real answer `RuntimeVersion`
    /// should return without walking anything, and the first is not an answer
    /// at all. A record whose `identity` does not match the caller's is treated
    /// as no record, which is what makes a rewritten binary a fresh question.
    func lookup(forBundleAt path: String, identity: String) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = Self.load(from: resolvedFileURL)[path], entry.identity == identity
        else { return nil }
        return entry.version
    }

    /// Records one verdict, replacing whatever was there for `path` before.
    ///
    /// Reads the file fresh immediately before writing and merges into it,
    /// rather than writing whatever this instance last loaded — so the app and
    /// `duo` racing to record two different bundles do not clobber one
    /// another's entries. Two writers racing on the *same* path can still lose
    /// one of their two writes; the loser simply re-proves that one bundle next
    /// time it is asked, which costs one walk and nothing else.
    func record(_ version: String?, forBundleAt path: String, identity: String) {
        lock.lock()
        defer { lock.unlock() }
        var entries = Self.load(from: resolvedFileURL)
        entries[path] = Entry(identity: identity, version: version)
        let contents = FileContents(generation: Self.proverGeneration, entries: entries)
        guard let data = try? JSONEncoder().encode(contents) else { return }
        try? FileManager.default.createDirectory(
            at: resolvedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: resolvedFileURL, options: .atomic)
    }

    /// A file that does not exist, cannot be parsed, was stamped by a
    /// different `proverGeneration`, or predates the stamp entirely (which
    /// fails to decode against `FileContents` and lands in the same `try?`)
    /// reads as empty rather than throwing or trusting a verdict this build
    /// might disagree with — costs one re-proof per entry that was lost and
    /// nothing else, the same failure mode every other JSON-backed store in
    /// this package chooses.
    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FileContents.self, from: data),
              decoded.generation == proverGeneration
        else { return [:] }
        return decoded.entries
    }

    /// Where a test process's `.shared` writes, when `DUO_STATE_DIR` is unset.
    ///
    /// Unlike `EventStore`'s equivalent (`duo-events-tests`, a fixed name every
    /// test process shares), this carries a UUID computed once — because
    /// unlike `EventStore`, which prunes itself by age and byte budget, this
    /// store only ever grows: every `record` call adds an entry and nothing
    /// ever removes one. Measured 2026-09-11: after a handful of `swift test`
    /// runs sharing a fixed test path, that file held 40 entries across
    /// 5.9 KB.
    ///
    /// This does NOT mean nothing is left on disk — an earlier version of
    /// this comment overclaimed that. Each run's small file stays in
    /// `TMPDIR` until the operating system's own periodic cleanup removes it,
    /// same as any other scratch file this package writes there; nothing here
    /// deletes it. What the UUID actually buys is narrower: no run ever reads
    /// a PREVIOUS run's entries, and two worktrees testing at once never
    /// share one.
    private static let testProcessScratchName = "duo-tauri-proofs-tests-\(UUID().uuidString)"

    static func defaultFileURL() -> URL {   // internal: asserted by DuoStateDirectoryTests
        let base = DuoStateDirectory.isTestProcess
            && ProcessInfo.processInfo.environment["DUO_STATE_DIR"] == nil
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent(testProcessScratchName, isDirectory: true)
            : DuoStateDirectory.base
        return base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("tauri-proofs.json")
    }
}
