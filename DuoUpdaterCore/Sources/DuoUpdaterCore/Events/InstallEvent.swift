import Foundation
import CryptoKit

/// One update Duo Updater downloaded and installed: which app, from which
/// version to which, over which source, and what it cost.
///
/// The permanent half of the ledger. A ``RequestEvent`` says a socket carried
/// bytes; this says an app moved from one build to another and what that took.
/// They describe the same transfer at different altitudes and are allowed to
/// disagree — the request events count wire bytes per redirect hop with headers,
/// this counts the body bytes that became a file on disk — which is why both are
/// kept rather than one being derived from the other.
///
/// **Never pruned.** Retention exists to stop a diagnostic log growing without
/// bound; this is not diagnostics, it is the answer to "what has keeping this
/// machine up to date cost me", and that has to survive forever. It can afford
/// to: this machine accumulated 586 of them over the app's whole life, against
/// thousands of request events per day.
public struct InstallEvent: Codable, Sendable, Hashable {

    /// Stable per-app key: the bundle's on-disk path, the same identity rule
    /// `InstalledApp.id` uses, so two installs sharing a bundle id stay distinct.
    public let appID: String
    /// Display name as it was at the time. Stored per event rather than looked up,
    /// so a renamed or deleted app still reads correctly years later.
    public let appName: String
    public let bundleID: String?

    /// Version the app was on before this update — its installed `shortVersion`.
    public let fromVersion: String?
    /// Version this update moved it to — the remote `displayVersion`.
    public let toVersion: String?
    /// `CFBundleVersion` of the build being replaced, when known.
    ///
    /// Recorded because plenty of vendors ship several builds under one marketing
    /// version — Surge put four separate releases out as "6.9.0" — and without the
    /// build number those rows all read "6.9.0 → 6.9.0".
    public let fromBuild: String?
    /// Build the update moved to, in the same namespace as `fromBuild`.
    public let toBuild: String?

    /// Update source that served the bytes ("Sparkle", "Vendor", "GitHub", "pkg").
    public let sourceName: String?
    /// Exact number of bytes transferred for this download.
    public let bytes: Int64
    /// Which route the bytes came down.
    public let downloadKind: TrafficDownloadKind?
    /// Whether the new build was on disk when this was recorded.
    ///
    /// **Nil for every event migrated from `traffic.json`**, which never stored
    /// it — and nil is the honest answer there rather than a guess, because the
    /// alternative is a field that silently means "false" for a decade of history
    /// that was mostly successful.
    public let applied: Bool?

    public init(
        appID: String, appName: String, bundleID: String?,
        fromVersion: String?, toVersion: String?,
        fromBuild: String? = nil, toBuild: String? = nil,
        sourceName: String?, bytes: Int64,
        downloadKind: TrafficDownloadKind? = nil, applied: Bool? = nil
    ) {
        self.appID = appID
        self.appName = appName
        self.bundleID = bundleID
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.fromBuild = fromBuild
        self.toBuild = toBuild
        self.sourceName = sourceName
        self.bytes = bytes
        self.downloadKind = downloadKind
        self.applied = applied
    }

    /// The legacy shape, for the parts of the app that still speak it.
    public func trafficEvent(at date: Date) -> TrafficEvent {
        TrafficEvent(
            date: date, fromVersion: fromVersion, toVersion: toVersion,
            sourceName: sourceName, bytes: bytes,
            fromBuild: fromBuild, toBuild: toBuild, downloadKind: downloadKind)
    }

    /// The id a migrated event gets, derived from what the row actually contains
    /// rather than freshly minted.
    ///
    /// This is what makes re-importing `traffic.json` safe: the same historical
    /// download always lands on the same primary key, so a second import replaces
    /// its own rows instead of doubling a user's lifetime total. A marker in
    /// `meta` stops the import running twice at all — but a flag is a promise and
    /// this is a proof, and the number at stake here is 115 GB of someone's
    /// recorded history.
    public static func migrationID(appID: String, date: Date, bytes: Int64) -> UUID {
        let seed = "duo-traffic-migration\u{0}\(appID)\u{0}\(EventStore.micros(date))\u{0}\(bytes)"
        var digest = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        // Stamped with the version and variant bits so the result is a well-formed
        // UUID rather than sixteen raw hash bytes wearing a UUID's type.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3],
                           digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11],
                           digest[12], digest[13], digest[14], digest[15]))
    }
}
