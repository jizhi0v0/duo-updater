import Foundation
import DuoUpdaterCore

/// What each recipe's installer turned out to be the first time
/// `duo verify-install` read it, kept so a later download that is something else
/// says so (`verify/identities.json`).
///
/// The install gates compare a download with the copy on the user's Mac; a runner
/// has no copy, so this file stands in for one. It is what would have caught
/// WorkBuddy CN: from 5.5.4 every download was `com.tencent.workbuddy.mac`, and a
/// store seeded before then would have held `com.workbuddy.workbuddy` (#1030).
///
/// A change is reported and the recorded identity is **left as it was**, so it
/// keeps being reported until someone decides it is legitimate and edits or
/// deletes the entry; the next run then records what it sees. Accepting it
/// automatically would turn the first sighting of a hijacked installer into the
/// new normal.
public struct InstallIdentities: Codable, Sendable, Equatable {

    /// The fields a vendor changing would make an install gate refuse, or
    /// change what gets installed. Version and OS floor move every release and
    /// are kept only to say when the identity was last confirmed.
    public struct Recorded: Codable, Sendable, Equatable {
        public var bundleIdentifier: String?
        public var signedIdentifier: String?
        public var teamIdentifier: String?
        /// The pkg route's Team, from its Developer ID Installer certificate.
        public var packageTeamIdentifier: String?
        public var sparklePublicKey: String?
        public var architectures: [String]
        public var firstSeenAt: Date
        public var firstSeenVersion: String?
        public var lastSeenAt: Date
        public var lastSeenVersion: String?
    }

    public var schemaVersion = 1
    public var entries: [String: Recorded] = [:]

    public init() {}

    /// Read the file at `url`. A missing file is an empty store — the first run
    /// records everything. A file that is there and cannot be read is an error,
    /// never an empty store: starting over would record whatever the vendors
    /// serve today as correct, which is exactly the change this exists to catch.
    public static func load(from url: URL) throws -> InstallIdentities {
        guard FileManager.default.fileExists(atPath: url.path) else { return InstallIdentities() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InstallIdentities.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// What a download's identity looks like in the store. Nil when there is
    /// nothing to record: a package inside a disk image was never opened.
    static func observed(
        identity: ArtifactInspection.Identity?, packageTeamIdentifier: String?,
        version: String?, at date: Date
    ) -> Recorded? {
        guard identity != nil || packageTeamIdentifier != nil else { return nil }
        return Recorded(
            bundleIdentifier: identity?.bundleIdentifier,
            signedIdentifier: identity?.signedIdentifier,
            teamIdentifier: identity?.teamIdentifier,
            packageTeamIdentifier: packageTeamIdentifier,
            sparklePublicKey: identity?.sparklePublicKey,
            architectures: identity?.architectures ?? [],
            firstSeenAt: date, firstSeenVersion: version,
            lastSeenAt: date, lastSeenVersion: version)
    }

    /// How `now` differs from `recorded`, one line per field. Empty when it is
    /// the same installer. Architectures only count when one is LOST: a build
    /// that becomes universal is not a fault, one that drops arm64 is.
    static func changes(from recorded: Recorded, to now: Recorded) -> [String] {
        func field(_ name: String, _ old: String?, _ new: String?) -> String? {
            old == new ? nil : "\(name) \(old ?? "none") → \(new ?? "none")"
        }
        var out = [
            field("bundle id", recorded.bundleIdentifier, now.bundleIdentifier),
            field("signed identifier", recorded.signedIdentifier, now.signedIdentifier),
            field("Team", recorded.teamIdentifier, now.teamIdentifier),
            field("package Team", recorded.packageTeamIdentifier, now.packageTeamIdentifier),
            field("Sparkle key", recorded.sparklePublicKey, now.sparklePublicKey),
        ].compactMap { $0 }
        let lost = Set(recorded.architectures).subtracting(now.architectures).sorted()
        if !lost.isEmpty {
            out.append("architectures \(recorded.architectures.joined(separator: "+")) → "
                + (now.architectures.isEmpty ? "none" : now.architectures.joined(separator: "+")))
        }
        return out
    }

    /// Fold one download into the store and return what changed. A new recipe
    /// is recorded; a matching one has its last-seen stamp moved; a changed one
    /// is left exactly as recorded (see the type's doc).
    mutating func record(_ recipeID: String, _ now: Recorded) -> [String] {
        guard let recorded = entries[recipeID] else {
            entries[recipeID] = now
            return []
        }
        let changes = Self.changes(from: recorded, to: now)
        if changes.isEmpty {
            entries[recipeID]?.lastSeenAt = now.lastSeenAt
            entries[recipeID]?.lastSeenVersion = now.lastSeenVersion
        }
        return changes
    }

    /// Drop entries for recipes that no longer exist. Derived from the
    /// registries, never from a run's `--only`, so a narrowed run keeps what it
    /// did not look at.
    mutating func prune(keeping live: Set<String>) {
        entries = entries.filter { live.contains($0.key) }
    }
}
