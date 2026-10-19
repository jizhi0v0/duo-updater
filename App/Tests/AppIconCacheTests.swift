import AppKit
import Observation
import Testing

/// The icon cache re-reads a path once the bundle there has been replaced by
/// something other than the GUI's own install (the `duo` CLI, a vendor updater, a
/// drag in Finder) — in `revalidatePass`, never inside a lookup. Identity of the
/// returned `NSImage` is the probe: `NSWorkspace.icon(forFile:)` hands back a new
/// image on every read, so the same instance means a cache hit and a different one
/// a re-read. Each case names the mutation it fails under. Serialized: `revision`
/// is global, and a pass in one case would bump it under another's assertion.
@MainActor
@Suite(.serialized)
struct AppIconCacheTests {

    /// A minimal `.app` in `dir`; returns the bundle path.
    private static func makeBundle(in dir: URL, version: String) throws -> String {
        let bundle = dir.appendingPathComponent("Probe.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "app.duo.test.iconprobe",
                                    "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return bundle.path
    }

    private static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIconCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Swap the bundle at `path` for a fresh copy, the way `duo install` does (a
    /// new bundle renamed over the old path).
    private static func replace(_ path: String, in dir: URL) throws {
        let staging = dir.appendingPathComponent("staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let fresh = try makeBundle(in: staging, version: "2.0")
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                                 withItemAt: URL(fileURLWithPath: fresh))
    }

    /// An unchanged bundle stays a hit through a pass, and the pass redraws
    /// nothing. Mutation: re-reading every cached path regardless of its stamp.
    @Test func anUnchangedBundleIsLeftAlone() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let first = AppIconCache.icon(for: path)
        let revision = AppIconCache.revision.value
        await AppIconCache.revalidatePass([path])
        #expect(AppIconCache.icon(for: path) === first)
        #expect(AppIconCache.revision.value == revision)
    }

    /// The lookup itself never checks the disk: right after a swap it still
    /// returns the cached image, and the pass is what replaces it. Mutations:
    /// comparing stamps in `icon(for:)` (the synchronous re-read in `body` this
    /// design exists to avoid); a pass that never re-reads.
    @Test func aReplacedBundleIsReReadByThePassNotByTheLookup() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let old = AppIconCache.icon(for: path)
        try Self.replace(path, in: dir)

        #expect(AppIconCache.icon(for: path) === old)
        await AppIconCache.revalidatePass([path])
        let reread = AppIconCache.icon(for: path)
        #expect(reread !== old)
        #expect(AppIconCache.icon(for: path) === reread)
    }

    /// A view that drew the icon is told to draw again once the pass replaces it.
    /// Mutations: not bumping `revision`; `icon(for:)` not reading it.
    @Test func aReReadRedrawsWhatDrewTheIcon() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        _ = AppIconCache.icon(for: path)
        try Self.replace(path, in: dir)

        let changed = Flag()
        withObservationTracking { _ = AppIconCache.icon(for: path) } onChange: { changed.set() }
        await AppIconCache.revalidatePass([path])
        #expect(changed.isSet)
    }

    /// Read while the bundle was absent (mid-swap), then the copy lands.
    /// Mutation: treating a missing stamp as matching any stamp.
    @Test func anIconReadWhileTheBundleWasMissingIsReReadOnceItLands() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("Probe.app").path
        let missing = AppIconCache.icon(for: path)
        _ = try Self.makeBundle(in: dir, version: "1.0")
        await AppIconCache.revalidatePass([path])
        #expect(AppIconCache.icon(for: path) !== missing)
    }

    /// The same Info.plist rewritten in place (new mtime, same inode) also counts.
    /// Mutation: dropping the mtime from the stamp.
    @Test func anInfoPlistRewrittenInPlaceIsReRead() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let old = AppIconCache.icon(for: path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)],
                                              ofItemAtPath: path + "/Contents/Info.plist")
        await AppIconCache.revalidatePass([path])
        #expect(AppIconCache.icon(for: path) !== old)
    }

    /// A pass only re-reads paths that are cached; it is not a second prefetch.
    /// Mutation: reading uncached paths in the pass.
    @Test func aPassDoesNotReadUncachedPaths() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let revision = AppIconCache.revision.value
        await AppIconCache.revalidatePass([path])
        #expect(AppIconCache.revision.value == revision)
    }

    /// Only "no such file" answers mean absent; a permission error (standing in
    /// for EIO or a dead mount, which a test cannot summon) is unreadable.
    /// Mutations: every failure absent; every failure unreadable.
    @Test func aStatFailureIsAbsentOnlyWhenTheFileIsMissing() throws {
        let dir = try Self.tempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("Locked").path)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(AppIconCache.BundleStamp.probe(dir.appendingPathComponent("Nope.app").path) == .absent)
        let file = dir.appendingPathComponent("flat")
        try Data().write(to: file)
        #expect(AppIconCache.BundleStamp.probe(file.path) == .absent)  // ENOTDIR
        let locked = dir.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        #expect(AppIconCache.BundleStamp.probe(locked.appendingPathComponent("P.app").path) == .unreadable)
    }

    /// A `stat` that fails for a reason other than "no such file" (EIO, a
    /// timed-out network mount) is not a change: re-reading would put that
    /// volume's I/O on the main actor. Mutation: treating `.unreadable` as absent.
    @Test func anUnreadableStampLeavesTheEntryAlone() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let old = AppIconCache.icon(for: path)
        let revision = AppIconCache.revision.value
        let real = AppIconCache.probeBundle
        AppIconCache.probeBundle = { _ in .unreadable }
        defer { AppIconCache.probeBundle = real }

        await AppIconCache.revalidatePass([path])
        #expect(AppIconCache.icon(for: path) === old)
        #expect(AppIconCache.revision.value == revision)
    }

    /// While one pass's `stat`s hang (as on an unresponsive mount), further calls
    /// queue behind it instead of each starting another blocked `stat`, and the
    /// queue holds one pass, not one per call. Mutation: cancelling and replacing
    /// the running pass on every call (each new pass stats again while the first
    /// is still stuck).
    @Test func callsDuringAHungPassQueueAsOne() async throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let gate = Gate()
        // On every way out, so a pass held in its `stat` never outlives the test.
        defer { gate.open() }
        let real = AppIconCache.probeBundle
        AppIconCache.probeBundle = { path in
            gate.enter()
            return real(path)
        }
        defer { AppIconCache.probeBundle = real }

        guard try await Self.firstPassHeld(at: path, by: gate) else {
            Issue.record("the pass never reached its stat: the cache had lost the entry on every try")
            return
        }
        // The first pass is now stuck in its `stat`.
        for _ in 0..<4 { AppIconCache.revalidate([path]) }
        // Long enough for every call's pass to have reached its `stat` if each one
        // started its own.
        try await Task.sleep(for: .milliseconds(300))
        #expect(gate.entered == 1)
        // Cached again in case it was dropped meanwhile: the queued pass, like
        // the first, stats only what is cached.
        _ = AppIconCache.icon(for: path)
        gate.open()
        await AppIconCache.revalidationSettled()
        #expect(gate.entered == 2)
    }

    /// Caches `path` and starts a pass, until one is held at `gate`. A pass
    /// stats only paths still cached, and `NSCache` drops entries by itself
    /// "if memory is needed by other applications" (its documentation). A pass
    /// that found the entry gone ended without a `stat`, and waiting for the
    /// gate alone then never ended. `make test` hung here for 19 and 42 min on
    /// 2026-10-18 (`sample`: this wait), and again on 10-19 among WebKit's
    /// memory-pressure warnings; removing the entry by hand reproduces it. So a
    /// pass that ends counts as a miss.
    private static func firstPassHeld(at path: String, by gate: Gate) async throws -> Bool {
        for _ in 0..<3 {
            _ = AppIconCache.icon(for: path)
            AppIconCache.revalidate([path])
            let ended = Flag()
            Task { await AppIconCache.revalidationSettled(); ended.set() }
            while gate.entered == 0, !ended.isSet { try await Task.sleep(for: .milliseconds(5)) }
            if gate.entered > 0 { return true }
        }
        return false
    }
}

/// Holds every `stat` until `open()`, counting how many arrived.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var count = 0
    var entered: Int { lock.withLock { count } }
    func open() { lock.withLock { isOpen = true } }
    func enter() {
        lock.withLock { count += 1 }
        while !lock.withLock({ isOpen }) { usleep(1_000) }
    }
}

/// Set from `withObservationTracking`'s `onChange`, which may run off the main actor.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
