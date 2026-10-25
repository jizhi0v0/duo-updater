import Testing
import CryptoKit
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `verify/identities.json`: what each installer was when first seen, and how a
/// later download that differs is reported. Measured end to end on WorkBuddy CN
/// (an entry recorded as `com.workbuddy.workbuddy` against today's
/// `com.tencent.workbuddy.mac` download); these pin the rules that run depends on.
@Suite struct InstallIdentitiesTests {

    private let day1 = Date(timeIntervalSince1970: 1_790_000_000)
    private let day2 = Date(timeIntervalSince1970: 1_790_086_400)

    private func recorded(
        id: String? = "com.example.app", team: String? = "ABCDE12345",
        key: String? = nil, archs: [String] = ["arm64"], version: String? = "1.0",
        at date: Date? = nil
    ) -> InstallIdentities.Recorded {
        let date = date ?? day1
        return InstallIdentities.Recorded(
            bundleIdentifier: id, signedIdentifier: id, teamIdentifier: team,
            packageTeamIdentifier: nil, sparklePublicKey: key, architectures: archs,
            firstSeenAt: date, firstSeenVersion: version,
            lastSeenAt: date, lastSeenVersion: version)
    }

    // MARK: what counts as a change

    @Test func theSameInstallerIsNoChange() {
        #expect(InstallIdentities.changes(
            from: recorded(), to: recorded(version: "2.0", at: day2)).isEmpty)
    }

    @Test func aRenameIsAChange() {
        let changes = InstallIdentities.changes(
            from: recorded(id: "com.workbuddy.workbuddy"), to: recorded(id: "com.tencent.workbuddy.mac"))
        #expect(changes.contains("bundle id com.workbuddy.workbuddy → com.tencent.workbuddy.mac"))
    }

    @Test func anotherTeamIsAChange() {
        #expect(InstallIdentities.changes(
            from: recorded(team: "ABCDE12345"), to: recorded(team: "ZZZZZ99999"))
            == ["Team ABCDE12345 → ZZZZZ99999"])
    }

    /// A key appearing or going is as much a change as a key rotating.
    @Test func aSparkleKeyAppearingIsAChange() {
        #expect(InstallIdentities.changes(from: recorded(key: nil), to: recorded(key: "abc="))
            == ["Sparkle key none → abc="])
    }

    @Test func gainingAnArchitectureIsNoChange() {
        #expect(InstallIdentities.changes(
            from: recorded(archs: ["arm64"]), to: recorded(archs: ["arm64", "x86_64"])).isEmpty)
    }

    @Test func losingAnArchitectureIsAChange() {
        #expect(InstallIdentities.changes(
            from: recorded(archs: ["arm64", "x86_64"]), to: recorded(archs: ["x86_64"]))
            == ["architectures arm64+x86_64 → x86_64"])
    }

    // MARK: what the store does with it

    @Test func aNewRecipeIsRecorded() {
        var store = InstallIdentities()
        #expect(store.record("vendor:a", recorded()).isEmpty)
        #expect(store.entries["vendor:a"] == recorded())
    }

    @Test func aMatchMovesOnlyTheLastSeenStamp() {
        var store = InstallIdentities()
        _ = store.record("vendor:a", recorded())
        #expect(store.record("vendor:a", recorded(version: "2.0", at: day2)).isEmpty)
        let entry = try? #require(store.entries["vendor:a"])
        #expect(entry?.firstSeenAt == day1)
        #expect(entry?.firstSeenVersion == "1.0")
        #expect(entry?.lastSeenAt == day2)
        #expect(entry?.lastSeenVersion == "2.0")
    }

    /// The file is committed back after every run: a stamp that moved on every
    /// run would rewrite every entry four times a day.
    @Test func theSameVersionAgainChangesNothing() {
        var store = InstallIdentities()
        _ = store.record("vendor:a", recorded())
        let before = store
        #expect(store.record("vendor:a", recorded(at: day2)).isEmpty)
        #expect(store == before)
    }

    /// The URL is what an incremental run compares besides the version, so a
    /// new one under the same version is recorded — or that installer would be
    /// downloaded on every run from then on.
    @Test func aNewURLMovesTheLastSeenStamp() {
        var store = InstallIdentities()
        var first = recorded()
        first.lastSeenURLSHA256 = InstallIdentities.digest(ofURL: "https://downloads.example.com/a.dmg")
        _ = store.record("vendor:a", first)
        var moved = recorded(at: day2)
        moved.lastSeenURLSHA256 = InstallIdentities.digest(ofURL: "https://cdn.example.com/a.dmg")
        #expect(store.record("vendor:a", moved).isEmpty)
        #expect(store.entries["vendor:a"]?.lastSeenURLSHA256 == InstallIdentities.digest(ofURL: "https://cdn.example.com/a.dmg"))
        #expect(store.entries["vendor:a"]?.lastSeenAt == day2)
    }

    /// A file written before the URL was recorded still reads.
    @Test func anEntryWithoutAURLStillReads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("identities-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("""
            {"schemaVersion": 1, "entries": {"vendor:a": {"architectures": ["arm64"],
             "firstSeenAt": "2026-09-01T00:00:00Z", "lastSeenAt": "2026-09-01T00:00:00Z",
             "lastSeenVersion": "1.0"}}}
            """.utf8).write(to: url)
        let store = try InstallIdentities.load(from: url)
        #expect(store.entries["vendor:a"]?.lastSeenVersion == "1.0")
        #expect(store.entries["vendor:a"]?.lastSeenURLSHA256 == nil)
    }

    private func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `verify/identities.json` is committed to a public repository, and some
    /// vendors' download URLs carry a signature or token. What is kept of the
    /// URL is its digest: enough to tell "same URL as last time" and nothing else.
    /// A file written before that names the URL; it reads, and what it is saved
    /// as no longer does.
    @Test func aSavedStoreHoldsTheURLsDigestAndAnOldFileIsMigrated() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("identities-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("old.json")
        let signed = "https://cdn.example.com/a.dmg?X-Amz-Signature=SECRET"
        try Data("""
            {"schemaVersion": 1, "entries": {"vendor:a": {"architectures": ["arm64"],
             "firstSeenAt": "2026-09-01T00:00:00Z", "lastSeenAt": "2026-09-01T00:00:00Z",
             "lastSeenVersion": "1.0", "lastSeenURL": "\(signed)"}}}
            """.utf8).write(to: old)

        let migrated = dir.appendingPathComponent("migrated.json")
        try InstallIdentities.load(from: old).save(to: migrated)
        let text = try String(contentsOf: migrated, encoding: .utf8)
        #expect(!text.contains("SECRET"))
        #expect(!text.contains("\"lastSeenURL\""))
        #expect(text.contains("\"lastSeenURLSHA256\" : \"\(sha256Hex(signed))\""))

        // And what was saved reads back as the same store.
        let again = dir.appendingPathComponent("again.json")
        try InstallIdentities.load(from: migrated).save(to: again)
        #expect(try Data(contentsOf: again) == Data(contentsOf: migrated))
    }

    /// Migrating must not change what a run does: an entry that recorded a URL
    /// before still skips that URL's download, and still downloads any other.
    @Test func aMigratedEntryKeepsItsSkipBehaviour() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("identities-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let same = "https://cdn.example.com/a.dmg?X-Amz-Signature=SECRET"
        try Data("""
            {"schemaVersion": 1, "entries": {"vendor:a": {"architectures": ["arm64"],
             "firstSeenAt": "2026-09-01T00:00:00Z", "lastSeenAt": "2026-09-01T00:00:00Z",
             "lastSeenVersion": "1.0", "lastSeenURL": "\(same)"}}}
            """.utf8).write(to: file)
        let recorded = try #require(InstallIdentities.load(from: file).entries["vendor:a"])
        var clean = Baseline.Entry()
        clean.consecutiveActionable = 0
        let previous = InstallVerify.Previous(recorded: recorded, baseline: clean)
        #expect(InstallVerify.skipsDownload(
            version: "1.0", urlSHA256: InstallIdentities.digest(ofURL: same), previous: previous))
        #expect(!InstallVerify.skipsDownload(
            version: "1.0", urlSHA256: InstallIdentities.digest(ofURL: same + "x"), previous: previous))
    }

    /// The report is a 90-day artifact from a public repository: a download URL
    /// goes into it without its query (a presigned signature), fragment or
    /// userinfo.
    @Test func theReportsURLKeepsSchemeHostAndPathOnly() throws {
        func shown(_ text: String) throws -> String {
            InstallVerify.displayURL(try #require(URL(string: text)))
        }
        #expect(try shown("https://cdn.example.com/a/b.dmg?X-Amz-Signature=SECRET&X-Amz-Expires=3600")
            == "https://cdn.example.com/a/b.dmg")
        #expect(try shown("https://user:hunter2@cdn.example.com:8443/a.dmg#frag?x=SECRET")
            == "https://cdn.example.com:8443/a.dmg")
        #expect(try shown("https://github.com/o/r/releases/download/v1/App.dmg")
            == "https://github.com/o/r/releases/download/v1/App.dmg")
    }

    /// The whole point: a change is reported and NOT accepted, so it is
    /// reported again next run until someone edits the entry.
    @Test func aChangeLeavesTheRecordAsItWas() {
        var store = InstallIdentities()
        _ = store.record("vendor:a", recorded(id: "com.old"))
        let before = store.entries["vendor:a"]
        #expect(!store.record("vendor:a", recorded(id: "com.new", at: day2)).isEmpty)
        #expect(store.entries["vendor:a"] == before)
        #expect(!store.record("vendor:a", recorded(id: "com.new", at: day2)).isEmpty)
    }

    @Test func pruningKeepsOnlyLiveRecipes() {
        var store = InstallIdentities()
        _ = store.record("vendor:live", recorded())
        _ = store.record("vendor:gone", recorded())
        store.prune(keeping: ["vendor:live", "vendor:not-yet-seen"])
        #expect(Set(store.entries.keys) == ["vendor:live"])
    }

    // MARK: the file

    @Test func aMissingFileIsAnEmptyStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("identities-\(UUID().uuidString).json")
        #expect(try InstallIdentities.load(from: url) == InstallIdentities())
    }

    @Test func anUnreadableFileIsAnErrorNotAnEmptyStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("identities-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"entries": {"#.utf8).write(to: url)
        #expect(throws: (any Error).self) { try InstallIdentities.load(from: url) }
    }

    @Test func aSavedStoreReadsBackTheSame() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("identities-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var store = InstallIdentities()
        _ = store.record("vendor:a", recorded(key: "abc=", archs: ["arm64", "x86_64"]))
        try store.save(to: url)
        #expect(try InstallIdentities.load(from: url) == store)
    }

    // MARK: an item against the store

    private func item(
        _ status: InstallVerify.Status, bundleID: String? = "com.example.app",
        packageTeam: String? = nil
    ) -> InstallVerify.Item {
        var item = InstallVerify.Item(
            recipeID: "vendor:a", registry: "vendor", bundleID: "com.example.app",
            probeHost: "example.com", status: status)
        item.version = "1.0"
        item.packageTeamIdentifier = packageTeam
        if let bundleID {
            item.identity = ArtifactInspection.Identity(
                signedIdentifier: bundleID, bundleIdentifier: bundleID,
                teamIdentifier: "ABCDE12345", shortVersion: "1.0", bundleVersion: nil,
                architectures: ["arm64"], minimumSystemVersion: nil, sparklePublicKey: nil)
        }
        return item
    }

    @Test func aChangedDownloadBecomesAWarning() {
        var store = InstallIdentities()
        var first = item(.ok, bundleID: "com.old")
        InstallVerify.compare(&first, with: &store, at: day1)
        #expect(first.status == .ok)
        var second = item(.ok, bundleID: "com.new")
        InstallVerify.compare(&second, with: &store, at: day2)
        #expect(second.status == .warn)
        #expect(second.warnings.contains { $0.hasPrefix("identityChanged: bundle id com.old → com.new") })
    }

    /// A failed download says nothing about the vendor: it must not seed the
    /// store with whatever partial identity it carries.
    @Test func aFailedDownloadRecordsNothing() {
        var store = InstallIdentities()
        var failed = item(.failed)
        InstallVerify.compare(&failed, with: &store, at: day1)
        #expect(store.entries.isEmpty)
        var unresolved = item(.unresolved)
        InstallVerify.compare(&unresolved, with: &store, at: day1)
        #expect(store.entries.isEmpty)
    }

    /// A package inside a disk image was never opened: nothing to record.
    @Test func anUnopenedPackageRecordsNothing() {
        var store = InstallIdentities()
        var unopened = item(.ok, bundleID: nil)
        InstallVerify.compare(&unopened, with: &store, at: day1)
        #expect(store.entries.isEmpty)
        var flat = item(.ok, bundleID: nil, packageTeam: "ABCDE12345")
        InstallVerify.compare(&flat, with: &store, at: day1)
        #expect(store.entries["vendor:a"]?.packageTeamIdentifier == "ABCDE12345")
    }
}
