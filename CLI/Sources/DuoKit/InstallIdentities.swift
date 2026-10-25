import CryptoKit
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
    public struct Recorded: Sendable, Equatable {
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
        /// SHA-256 of where that version was downloaded from, as lowercase hex
        /// (`digest(ofURL:)`). With `lastSeenVersion`, what lets `duo
        /// verify-install` skip a download it has already read
        /// (`InstallVerify.skipsDownload`). The URL itself is not kept: this
        /// file is committed to a public repository and a download URL can
        /// carry a signature or token. Nothing needs it back — only whether it
        /// is the same one. Nil in an entry written before the URL was recorded,
        /// which matches no URL — so that entry downloads once more and records it.
        public var lastSeenURLSHA256: String? = nil
    }

    /// The lowercase-hex SHA-256 of a download URL's exact text.
    public static func digest(ofURL url: String) -> String {
        SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var schemaVersion = 1
    public var entries: [String: Recorded] = [:]
    /// When a run last downloaded every installer — full, unfiltered, and
    /// finished (`InstallVerify.stampFullPass`). A run with nothing newer than
    /// `InstallVerify.fullPassInterval` here owes one (`fullPassOwed`). It
    /// reaches `main` only with the rest of this file, in a committed state pull
    /// request, so a full run whose state is dropped leaves the next run still
    /// owing one. Nil in a file written before this field existed.
    public var lastFullPassAt: Date?

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
        version: String?, urlSHA256: String? = nil, at date: Date
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
            lastSeenAt: date, lastSeenVersion: version, lastSeenURLSHA256: urlSHA256)
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
    /// is recorded; a matching one has its last-seen stamp moved when its version
    /// or download URL did; a changed one is left exactly as recorded (see the
    /// type's doc).
    ///
    /// Only when the version or URL moved: the file is committed back after every run,
    /// four a day, and a stamp that moved every time would make each of those
    /// pull requests rewrite every entry — burying the one line that matters.
    mutating func record(_ recipeID: String, _ now: Recorded) -> [String] {
        guard let recorded = entries[recipeID] else {
            entries[recipeID] = now
            return []
        }
        let changes = Self.changes(from: recorded, to: now)
        if changes.isEmpty,
           recorded.lastSeenVersion != now.lastSeenVersion
            || recorded.lastSeenURLSHA256 != now.lastSeenURLSHA256 {
            entries[recipeID]?.lastSeenAt = now.lastSeenAt
            entries[recipeID]?.lastSeenVersion = now.lastSeenVersion
            entries[recipeID]?.lastSeenURLSHA256 = now.lastSeenURLSHA256
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

extension InstallIdentities.Recorded: Codable {
    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, signedIdentifier, teamIdentifier, packageTeamIdentifier
        case sparklePublicKey, architectures, firstSeenAt, firstSeenVersion
        case lastSeenAt, lastSeenVersion, lastSeenURLSHA256
        /// What an entry written before the digest held: the URL itself, signed
        /// query and all. Read, hashed, and never written back.
        case legacyLastSeenURL = "lastSeenURL"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        signedIdentifier = try c.decodeIfPresent(String.self, forKey: .signedIdentifier)
        teamIdentifier = try c.decodeIfPresent(String.self, forKey: .teamIdentifier)
        packageTeamIdentifier = try c.decodeIfPresent(String.self, forKey: .packageTeamIdentifier)
        sparklePublicKey = try c.decodeIfPresent(String.self, forKey: .sparklePublicKey)
        architectures = try c.decode([String].self, forKey: .architectures)
        firstSeenAt = try c.decode(Date.self, forKey: .firstSeenAt)
        firstSeenVersion = try c.decodeIfPresent(String.self, forKey: .firstSeenVersion)
        lastSeenAt = try c.decode(Date.self, forKey: .lastSeenAt)
        lastSeenVersion = try c.decodeIfPresent(String.self, forKey: .lastSeenVersion)
        if let digest = try c.decodeIfPresent(String.self, forKey: .lastSeenURLSHA256) {
            lastSeenURLSHA256 = digest
        } else {
            lastSeenURLSHA256 = try c.decodeIfPresent(String.self, forKey: .legacyLastSeenURL)
                .map(InstallIdentities.digest(ofURL:))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try c.encodeIfPresent(signedIdentifier, forKey: .signedIdentifier)
        try c.encodeIfPresent(teamIdentifier, forKey: .teamIdentifier)
        try c.encodeIfPresent(packageTeamIdentifier, forKey: .packageTeamIdentifier)
        try c.encodeIfPresent(sparklePublicKey, forKey: .sparklePublicKey)
        try c.encode(architectures, forKey: .architectures)
        try c.encode(firstSeenAt, forKey: .firstSeenAt)
        try c.encodeIfPresent(firstSeenVersion, forKey: .firstSeenVersion)
        try c.encode(lastSeenAt, forKey: .lastSeenAt)
        try c.encodeIfPresent(lastSeenVersion, forKey: .lastSeenVersion)
        try c.encodeIfPresent(lastSeenURLSHA256, forKey: .lastSeenURLSHA256)
    }
}
