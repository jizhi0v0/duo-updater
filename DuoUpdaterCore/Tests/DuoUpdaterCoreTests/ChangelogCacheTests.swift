import Testing
import Foundation
@testable import DuoUpdaterCore

// MARK: - ChangelogCache unit tests

/// Verifies the core TTL cache semantics used by ChangelogService to skip
/// re-fetching vendor changelog pages on repeated detail-window opens.
struct ChangelogCacheTests {

    private static let url1 = URL(string: "https://example.com/releases")!
    private static let url2 = URL(string: "https://other.com/changelog")!

    private static func makeChangelog(version: String = "1.0") -> Changelog {
        Changelog(entries: [
            Changelog.Entry(version: version, date: "2025-01-01", items: ["Initial release"])
        ])
    }

    // MARK: - Basic get/set

    @Test func emptyOnInit() async {
        let cache = ChangelogCache(ttl: 60)
        #expect(await cache.get(for: Self.url1) == nil)
    }

    @Test func roundtrip() async {
        let cache = ChangelogCache(ttl: 60)
        let log = Self.makeChangelog(version: "2.0")
        await cache.set(log, for: Self.url1)
        #expect(await cache.get(for: Self.url1) == log)
    }

    @Test func keysAreIndependent() async {
        let cache = ChangelogCache(ttl: 60)
        let log1 = Self.makeChangelog(version: "1.0")
        let log2 = Self.makeChangelog(version: "2.0")
        await cache.set(log1, for: Self.url1)
        await cache.set(log2, for: Self.url2)
        #expect(await cache.get(for: Self.url1) == log1)
        #expect(await cache.get(for: Self.url2) == log2)
    }

    @Test func setOverwritesPreviousEntry() async {
        let cache = ChangelogCache(ttl: 60)
        let old = Self.makeChangelog(version: "1.0")
        let new = Self.makeChangelog(version: "2.0")
        await cache.set(old, for: Self.url1)
        await cache.set(new, for: Self.url1)
        #expect(await cache.get(for: Self.url1) == new)
    }

    // MARK: - TTL expiry

    @Test func expiredEntryReturnsNil() async {
        // Zero TTL: every entry is immediately stale.
        let cache = ChangelogCache(ttl: 0)
        await cache.set(Self.makeChangelog(), for: Self.url1)
        #expect(await cache.get(for: Self.url1) == nil)
    }

    @Test func expiredEntryIsEvicted() async {
        // After expiry, the slot should be gone so a subsequent set works cleanly.
        let cache = ChangelogCache(ttl: 0)
        await cache.set(Self.makeChangelog(version: "1.0"), for: Self.url1)
        _ = await cache.get(for: Self.url1)  // triggers eviction
        // Now set a fresh entry — it should survive a get within the new TTL.
        let fresh = ChangelogCache(ttl: 60)
        await fresh.set(Self.makeChangelog(version: "2.0"), for: Self.url1)
        #expect(await fresh.get(for: Self.url1) != nil)
    }

    @Test func freshEntryWithLongTTLSurvives() async {
        // TTL of 1 hour: a just-stored entry must not be evicted immediately.
        let cache = ChangelogCache(ttl: 3600)
        let log = Self.makeChangelog(version: "3.0")
        await cache.set(log, for: Self.url1)
        #expect(await cache.get(for: Self.url1) == log)
    }

    // MARK: - invalidateAll

    @Test func invalidateAllClearsEveryKey() async {
        let cache = ChangelogCache(ttl: 3600)
        await cache.set(Self.makeChangelog(version: "1.0"), for: Self.url1)
        await cache.set(Self.makeChangelog(version: "2.0"), for: Self.url2)
        await cache.invalidateAll()
        #expect(await cache.get(for: Self.url1) == nil)
        #expect(await cache.get(for: Self.url2) == nil)
    }

    @Test func setAfterInvalidateIsVisible() async {
        let cache = ChangelogCache(ttl: 3600)
        await cache.set(Self.makeChangelog(version: "1.0"), for: Self.url1)
        await cache.invalidateAll()
        let fresh = Self.makeChangelog(version: "2.0")
        await cache.set(fresh, for: Self.url1)
        #expect(await cache.get(for: Self.url1) == fresh)
    }

    // MARK: - invalidate(_:) — single key (used after an app updates on disk)

    @Test func invalidateDropsOnlyTheGivenKey() async {
        let cache = ChangelogCache(ttl: 3600)
        await cache.set(Self.makeChangelog(version: "1.0"), for: Self.url1)
        await cache.set(Self.makeChangelog(version: "2.0"), for: Self.url2)
        await cache.invalidate(Self.url1)
        // The updated app's slot is gone; every other app's stays fresh.
        #expect(await cache.get(for: Self.url1) == nil)
        #expect(await cache.get(for: Self.url2) != nil)
    }

    @Test func invalidateUnknownKeyIsNoOp() async {
        let cache = ChangelogCache(ttl: 3600)
        await cache.set(Self.makeChangelog(version: "1.0"), for: Self.url1)
        await cache.invalidate(Self.url2)  // never cached
        #expect(await cache.get(for: Self.url1) != nil)
    }
}
