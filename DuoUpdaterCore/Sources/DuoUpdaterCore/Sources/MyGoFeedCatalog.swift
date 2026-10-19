import Foundation

/// The MyGo apps `duo verify --mygo` sweeps every night: each one's feed and key,
/// as an audit read them out of its binary.
///
/// **Not consulted by any check.** `MyGoUpdateSource` reads the feed and key out
/// of the installed binary (`MyGoUpdateConfig`), which is the truth for that
/// copy; this table is only what the nightly sweep has to go on, because a
/// sweep runs on a machine with none of these apps installed. That is the same
/// reason `SparkleFeedCatalog` exists for the sweep — a mechanism with no table
/// has nothing to walk.
///
/// What the sweep can catch that nothing else would: a feed that stopped
/// answering or stopped naming a complete release, an archive that is no
/// longer served, and — the one that ends every one-click while detection keeps
/// working — the vendor signing with a key other than the one its installed
/// apps carry.
///
/// An entry is added when an audit has read the key out of a real binary and
/// seen it verify the manifest (`docs/app-audits/<bundle id>.md`), and removed
/// with that audit. A key here that differs from the binary's would only make
/// the sweep complain; it changes nothing for users.
public enum MyGoFeedCatalog {

    public struct Entry: Sendable, Hashable {
        public let bundleID: String
        /// The feed as the binary links it (a tagged feed keeps `{version}`).
        public let feed: String
        /// The key as the binary links it, base64.
        public let publicKey: String

        public var recipeID: String { "mygo:\(bundleID)" }

        public var config: MyGoUpdateConfig {
            MyGoUpdateConfig(feed: feed, publicKey: publicKey)
        }
    }

    public static let entries: [Entry] = [
        // docs/app-audits/com-egoist-pulse.md — Pulse 0.1.11 and 0.1.12 binaries.
        Entry(
            bundleID: "com.egoist.pulse",
            feed: "https://github.com/egoist/pulse-feedback/releases/latest/download/update-darwin-arm64.json",
            publicKey: "WzJsOGNIuf6mcEqo5ff8jub+NoQQOEk4JXreLPYjgyQ="),
        // docs/app-audits/app-getmoshi-desktop.md — Moshi Go 0.5.16 binary.
        Entry(
            bundleID: "app.getmoshi.desktop",
            feed: "https://cdn.getmoshi.app/desktop-go/update-darwin-arm64.json",
            publicKey: "iXWMulHl+4m/dByqrJ8a1YOzcDIBeUOPiZ/AFj6k4VI="),
        // docs/app-audits/dev-leafmark-app.md — Leafmark 0.9.1 and 0.9.2 binaries.
        Entry(
            bundleID: "dev.leafmark.app",
            feed: "https://github.com/KevinXC5/leafmark/releases/latest/download/update-darwin-arm64.json",
            publicKey: "arFeLNqUcZDj4bjo7f1FiZ3ndod0Ghgu6B15b/BKUH8="),
        // docs/app-audits/dev-mayoi-editor.md — Mayoi 0.1.0, 0.10.0 and 0.11.0 binaries.
        Entry(
            bundleID: "dev.mayoi.editor",
            feed: "https://github.com/sorrycc/Mayoi/releases/latest/download/update-darwin-arm64.json",
            publicKey: "kW6/B4DkWNQdyHkFOrU6tpvLfb5xGVvyYhrIQF7Bct4="),
    ]
}
