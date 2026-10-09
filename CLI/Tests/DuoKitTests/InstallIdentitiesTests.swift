import Testing
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
