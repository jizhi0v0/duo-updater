import Foundation
import SQLite3

/// Open Screen Sharing (`io.nekohasekai.screensharing`) — the first binding whose
/// preference is a row in a SQLite database.
///
/// The app's Settings → App → Update Track picks `stable` or `nightly`
/// (`OpenScreenSharing/Update/UpdateChecker.swift`, `UpdateTrack`). Its
/// `PreferenceStore` is GRDB, not `UserDefaults`: table `preferences(name, data)`,
/// one row per key, `data` the JSON encoding of the value. With Nightly chosen,
/// read from the real app on 2026-10-17:
///
/// ```
/// updateTrack|"nightly"|blob|226E696768746C7922
/// ```
///
/// The database lives in the app's group container
/// (`AppDatabase.swift`: `AppDirectory.group` + `Screen Sharing.sqlite`), and that
/// directory needs Full Disk Access: a probe with no grants, launched through
/// LaunchServices on macOS 27 the same day, got EPERM from `Data(contentsOf:)` and
/// "authorization denied" from SQLite. So the read is gated like CotEditor's.
///
/// Only `nightly` answers; anything else is nil, so `ReleaseChannel.detect()`
/// keeps speaking. That is `.stable` for every build this app ships — a nightly
/// build and the release copied from it are the same bytes, so nothing in the
/// bundle could say otherwise.
///
/// The channel only selects which recipe answers (the nightly `VendorProbeRecipe`
/// against the stable `GitHubReleaseRule`), so this is in
/// `ChannelBinding.vendorProbeBackedBindings`, not `allResolutions`.
///
/// No watch root: the container also holds the app's caches, and an FSEvents
/// stream there would fire whenever it runs. A switch of track is picked up on the
/// next scan, as for Cindy and Cua Driver.
enum OpenScreenSharingChannel {
    static let bundleID = "io.nekohasekai.screensharing"

    /// The group the app's entitlement names (`P8XK3KHB48.io.nekohasekai.screensharing`
    /// in both 1.0.0 and 1.0.1, also its `AppGroupIdentifier` Info.plist key).
    static let appGroup = "P8XK3KHB48.io.nekohasekai.screensharing"

    static let preferenceName = "updateTrack"
    static let nightlyValue = "nightly"

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(appGroup)/Screen Sharing.sqlite",
                                    isDirectory: false)
    }

    /// Map the stored track to a resolution. Pure and tested. `track` is the
    /// decoded JSON string, nil when the row or the database is missing.
    static func resolve(track: String?) -> ResolvedChannel? {
        track == nightlyValue ? ResolvedChannel(channel: .nightly) : nil
    }

    static func resolveCurrent() -> ResolvedChannel? {
        guard FullDiskAccessNeeds.shared.mayRead(.openScreenSharingChannel, for: [bundleID])
        else { return nil }
        return resolve(track: readTrack(at: databaseURL))
    }

    /// The `updateTrack` row, JSON-decoded. Read-only; nil when the file, table,
    /// row or JSON is missing or unreadable — the app's own default (`stable`) is
    /// what an absent row means to it too.
    static func readTrack(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT data FROM preferences WHERE name = ?1", -1, &statement, nil) == SQLITE_OK,
              sqlite3_bind_text(statement, 1, preferenceName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0)
        else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        return try? JSONDecoder().decode(String.self, from: data)
    }
}
