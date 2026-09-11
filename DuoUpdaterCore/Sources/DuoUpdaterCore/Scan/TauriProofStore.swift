import Foundation

/// The disk half of `RuntimeVersion`'s Tauri cache — what lets the verdict a
/// process's binary walk reaches outlive that process.
///
/// `RuntimeVersion.cache` (see its doc comment) already remembers an answer for
/// the life of one process, keyed on the executable's size and modification
/// date. That is enough for the menu-bar app, which walks a candidate's binary
/// at most once per launch. It is not enough for `duo`: every invocation is a
/// fresh process, so without this store `duo list` re-walks every Tauri
/// candidate's executable on every call — measured at 400–730 ms across the
/// bundles this machine's filter admits, out of a total `duo list` runtime of
/// 0.7–1.0 s. This file exists to make the second and later calls skip that
/// walk entirely.
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

    /// The instance `RuntimeVersion` calls through. Production code should
    /// only ever touch this one; the `init(fileURL:)` override below exists for
    /// tests that model two processes sharing one file.
    static let shared = TauriProofStore()

    /// Set only by tests. `nil` means "resolve `defaultFileURL()` fresh on
    /// every access", which is deliberate and not an oversight: a `fileURL`
    /// captured once at init, the way the other on-disk stores do it, would be
    /// fine for them because they are constructed fresh per test or per
    /// short-lived caller. `shared` is not — it is first touched at an
    /// effectively random point across an entire `swift test` run, which is
    /// exactly the shape `DuoStateDirectoryTests` exists to worry about
    /// (`setenv` toggling `DUO_STATE_DIR` mid-suite). Resolving fresh on every
    /// call shrinks that race window from "the rest of the process" to "one
    /// lookup or record call", the same guarantee `DuoStateDirectory.base`
    /// already gives every other reader of `DUO_STATE_DIR`.
    private let fileURLOverride: URL?
    private let lock = NSLock()

    init(fileURL: URL? = nil) {
        self.fileURLOverride = fileURL
    }

    private var fileURL: URL { fileURLOverride ?? Self.defaultFileURL() }

    /// `nil` means "no record for this path at all". `.some(nil)` means "there
    /// is a record, and it says no crate was found" — the two must stay
    /// distinguishable, because the second is a real answer `RuntimeVersion`
    /// should return without walking anything, and the first is not an answer
    /// at all. A record whose `identity` does not match the caller's is treated
    /// as no record, which is what makes a rewritten binary a fresh question.
    func lookup(forBundleAt path: String, identity: String) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = Self.load(from: fileURL)[path], entry.identity == identity else { return nil }
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
        var entries = Self.load(from: fileURL)
        entries[path] = Entry(identity: identity, version: version)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A file that does not exist, cannot be parsed, or decodes to something
    /// that is no longer this shape reads as empty rather than throwing —
    /// costs one re-proof per entry that was lost and nothing else, the same
    /// failure mode every other JSON-backed store in this package chooses.
    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    static func defaultFileURL() -> URL {   // internal: asserted by DuoStateDirectoryTests
        let base = DuoStateDirectory.isTestProcess
            && ProcessInfo.processInfo.environment["DUO_STATE_DIR"] == nil
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-tauri-proofs-tests", isDirectory: true)
            : DuoStateDirectory.base
        return base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("tauri-proofs.json")
    }
}
