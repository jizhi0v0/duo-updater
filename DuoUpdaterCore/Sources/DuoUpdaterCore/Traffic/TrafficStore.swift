import Foundation

/// The old per-app download ledger, kept only to read what it already holds.
///
/// The ledger lives in ``EventStore`` now, as `install` events: one store means
/// the network-level and app-level accounts of a single download cannot drift
/// apart, and it gets the ledger the same durability guarantees the totals have.
/// ``EventStore/importLegacyTraffic(from:force:)`` moves this file's contents
/// across once, on first launch after the change.
///
/// **Nothing writes here any more, and the file is never modified or deleted.**
/// It stays as the user's own copy of a history the new store has taken
/// responsibility for — which is worth more than the few bytes reclaiming it
/// would save, the first time somebody wants to check the new numbers against the
/// old ones.
///
/// Homebrew updates were never counted, then or now: `brew` performs its own
/// download, so we never see those bytes and could only guess at them.
public enum TrafficStore {

    /// Read a legacy `traffic.json`. The migration's source.
    public static func loadStats(from url: URL) -> [String: AppTrafficStat] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([String: AppTrafficStat].self, from: data) else {
            Log.install.error("traffic: legacy file unreadable; nothing to import")
            return [:]
        }
        return decoded
    }

    static func defaultFileURL() -> URL {   // internal: asserted by DuoStateDirectoryTests
        DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("traffic.json")
    }
}
