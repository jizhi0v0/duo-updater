import Testing
import Foundation
@testable import DuoUpdaterCore

/// Regression coverage for issue #112: a `ChangelogDiskCache` entry written by an
/// older build's parser must not be served to a newer build whose extraction logic
/// has since changed for the same version. See `Changelog.parserGeneration` and
/// `ChangelogDiskCache`'s doc comments for the design (a generation mismatch is a
/// miss, not a TTL).
struct ChangelogDiskCacheTests {

    private static let key = ChangelogDiskCache.Key(
        bundleID: "com.example.app", channel: "stable", version: "1.0")

    private static func makeChangelog(version: String = "1.0") -> Changelog {
        Changelog(entries: [
            Changelog.Entry(version: version, date: "2026-01-01", items: ["Fixed a thing"])
        ])
    }

    /// Fresh scratch directory per test so runs never share on-disk state.
    private func withScratchDirectory<T>(_ body: (URL) async throws -> T) async rethrows -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChangelogDiskCacheTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await body(dir)
    }

    /// The single file `set` wrote for `key`, so a test can corrupt/rewrite it
    /// without reimplementing `ChangelogDiskCache`'s private filename scheme.
    private func onDiskFileURL(in dir: URL) throws -> URL {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.count == 1, "expected exactly one file after a single set(); found \(names)")
        return dir.appendingPathComponent(names[0])
    }

    // MARK: - Same generation: hit

    @Test func sameGenerationEntryIsServed() async {
        await withScratchDirectory { dir in
            let cache = ChangelogDiskCache(directory: dir)
            let changelog = Self.makeChangelog()
            await cache.set(changelog, for: Self.key)
            #expect(await cache.get(for: Self.key) == changelog)
        }
    }

    // MARK: - Older generation on disk: miss, not poisoned

    /// An entry written at generation N-1 must be a miss at generation N. There is
    /// no way to *produce* an N-1 file through the current build (it always writes
    /// `Changelog.parserGeneration`), so this reaches into the file `set` wrote and
    /// rewrites its `parserGeneration` field directly, simulating a build this
    /// process was never compiled as.
    @Test func staleGenerationOnDiskIsAMiss() async throws {
        try await withScratchDirectory { dir in
            let cache = ChangelogDiskCache(directory: dir)
            await cache.set(Self.makeChangelog(), for: Self.key)
            let fileURL = try onDiskFileURL(in: dir)

            // Rewrite the stored JSON with a generation older than the running
            // build's, exactly like a file a previous release wrote to this
            // machine and never revisited.
            var data = try Data(contentsOf: fileURL)
            var json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let staleGeneration = Changelog.parserGeneration - 1
            #expect(staleGeneration >= 0, "parserGeneration must start at 1 or higher for this test to mean anything")
            json["parserGeneration"] = staleGeneration
            data = try JSONSerialization.data(withJSONObject: json)
            try data.write(to: fileURL)

            // A fresh cache instance so nothing survives in the in-memory mirror
            // from the `set` above — this must be a disk-level miss, not an
            // artifact of skipping the file read entirely.
            let reopened = ChangelogDiskCache(directory: dir)
            #expect(await reopened.get(for: Self.key) == nil)
        }
    }

    /// A miss on a stale-generation file must not leave the in-memory mirror
    /// serving that same stale content afterwards — i.e. the miss really is a
    /// miss, not a one-time hiccup papered over by a cache the next call reads
    /// through.
    @Test func staleGenerationMissDoesNotPoisonMemory() async throws {
        try await withScratchDirectory { dir in
            let cache = ChangelogDiskCache(directory: dir)
            await cache.set(Self.makeChangelog(), for: Self.key)
            let fileURL = try onDiskFileURL(in: dir)
            var data = try Data(contentsOf: fileURL)
            var json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            json["parserGeneration"] = Changelog.parserGeneration - 1
            data = try JSONSerialization.data(withJSONObject: json)
            try data.write(to: fileURL)

            let reopened = ChangelogDiskCache(directory: dir)
            #expect(await reopened.get(for: Self.key) == nil)
            // Ask again: if the first miss had wrongly cached the stale changelog
            // into `memory`, this second call would return it instead of nil.
            #expect(await reopened.get(for: Self.key) == nil)
        }
    }

    // MARK: - Pre-generation (old-schema) file: miss, not a crash

    /// A file written before `parserGeneration` existed at all (no such key in the
    /// JSON) must be treated as a miss — `Stored.parserGeneration` is non-optional,
    /// so this exercises the decode-failure path `get` already swallows, per the
    /// deliberate migration decision documented on `Stored`.
    @Test func preGenerationSchemaFileIsAMissNotACrash() async throws {
        try await withScratchDirectory { dir in
            let cache = ChangelogDiskCache(directory: dir)
            await cache.set(Self.makeChangelog(), for: Self.key)
            let fileURL = try onDiskFileURL(in: dir)

            // Old shape: only `changelog` + `fetchedAt`, exactly what `Stored`
            // looked like before this field was added.
            var data = try Data(contentsOf: fileURL)
            var json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any])
            json.removeValue(forKey: "parserGeneration")
            data = try JSONSerialization.data(withJSONObject: json)
            try data.write(to: fileURL)

            let reopened = ChangelogDiskCache(directory: dir)
            #expect(await reopened.get(for: Self.key) == nil)
        }
    }

    // MARK: - set() always stamps the current generation

    @Test func setStampsRunningGeneration() async throws {
        try await withScratchDirectory { dir in
            let cache = ChangelogDiskCache(directory: dir)
            await cache.set(Self.makeChangelog(), for: Self.key)
            let fileURL = try onDiskFileURL(in: dir)
            let json = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
            #expect(json["parserGeneration"] as? Int == Changelog.parserGeneration)
        }
    }
}
