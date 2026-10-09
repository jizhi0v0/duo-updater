import Foundation
import Testing
@testable import DuoUpdaterCore

/// `BundleIDMigration`: a copy still on a vendor's old bundle id is checked and
/// updated as the renamed app, in one direction, for one Team, below one bound.
struct BundleIDMigrationTests {

    private static let entry = BundleIDMigration(
        from: "com.example.old", to: "com.example.new",
        teamID: "TEAM123456", lastFromVersion: "1.4.0", firstToVersion: "2.0.0")
    private static let table = [entry]

    // MARK: - the table itself

    /// Every registered rename points at an id the registries actually serve,
    /// and nothing is still keyed by the old one — otherwise an old-id copy
    /// would match two sets of recipes, or none.
    @Test func everyEntryLandsOnRecipesAndLeavesTheOldIdUnkeyed() {
        let vendorIDs = Set(VendorProbeRegistry.recipes.map(\.bundleID))
        let changelogIDs = Set(ChangelogRecipeRegistry.recipes.map(\.bundleID))
        let githubIDs = Set(GitHubReleaseRegistry.rules.map(\.bundleID))
        let keyed = vendorIDs.union(changelogIDs).union(githubIDs)
        #expect(!BundleIDMigration.all.isEmpty)
        for m in BundleIDMigration.all {
            #expect(m.from != m.to)
            #expect(keyed.contains(m.to), "\(m.to) has no recipe to land on")
            #expect(!keyed.contains(m.from), "\(m.from) is still keyed by a recipe")
            #expect(VersionComparator.compare(m.lastFromVersion, m.firstToVersion) == .orderedAscending)
            #expect(m.covers(installedVersion: m.lastFromVersion))
            #expect(!m.covers(installedVersion: m.firstToVersion))
        }
        let froms = BundleIDMigration.all.map(\.from)
        #expect(Set(froms).count == froms.count, "one old id, one rename")
    }

    // MARK: - recipe lookup

    @Test func anOldIdBelowTheBoundIsFiledUnderTheNewId() {
        #expect(BundleIDMigration.recipeBundleID(
            for: "com.example.old", installedVersion: "1.4.0", in: Self.table) == "com.example.new")
        #expect(BundleIDMigration.recipeBundleID(
            for: "com.example.old", installedVersion: "1.9.9", in: Self.table) == "com.example.new")
    }

    /// At or past the bound, or with no version to compare, an old-id copy is not
    /// the rename that was measured and keeps its own id.
    @Test func anOldIdAtTheBoundOrWithoutAVersionKeepsItsOwnId() {
        for version in ["2.0.0", "2.1", nil] as [String?] {
            #expect(BundleIDMigration.recipeBundleID(
                for: "com.example.old", installedVersion: version, in: Self.table) == "com.example.old")
        }
    }

    @Test func otherIdsAreUntouched() {
        #expect(BundleIDMigration.recipeBundleID(
            for: "com.example.new", installedVersion: "1.0", in: Self.table) == "com.example.new")
        #expect(BundleIDMigration.recipeBundleID(
            for: "com.example.other", installedVersion: "1.0", in: Self.table) == "com.example.other")
    }

    /// Process lookup widens to the paired id in both directions, and to nothing
    /// for an id with no rename.
    @Test func relatedIdsPairBothWays() {
        #expect(BundleIDMigration.relatedBundleIDs(of: "com.example.new", in: Self.table)
                == ["com.example.new", "com.example.old"])
        #expect(BundleIDMigration.relatedBundleIDs(of: "com.example.old", in: Self.table)
                == ["com.example.old", "com.example.new"])
        #expect(BundleIDMigration.relatedBundleIDs(of: "com.example.other", in: Self.table)
                == ["com.example.other"])
    }

    // MARK: - the identity gate

    @Test func theRegisteredDirectionAndTeamPass() {
        #expect(BundleIDMigration.migration(
            installed: "com.example.old", downloaded: "com.example.new", installedVersion: "1.4.0",
            installedTeam: "TEAM123456", downloadedTeam: "TEAM123456", in: Self.table) == Self.entry)
    }

    @Test func everythingElseIsRefused() {
        func gate(_ installed: String, _ downloaded: String, _ version: String?,
                  _ installedTeam: String?, _ downloadedTeam: String?) -> BundleIDMigration? {
            BundleIDMigration.migration(
                installed: installed, downloaded: downloaded, installedVersion: version,
                installedTeam: installedTeam, downloadedTeam: downloadedTeam, in: Self.table)
        }
        // The reverse direction.
        #expect(gate("com.example.new", "com.example.old", "1.4.0", "TEAM123456", "TEAM123456") == nil)
        // Another Team on either side, or none.
        #expect(gate("com.example.old", "com.example.new", "1.4.0", "OTHERTEAM1", "OTHERTEAM1") == nil)
        #expect(gate("com.example.old", "com.example.new", "1.4.0", "TEAM123456", "OTHERTEAM1") == nil)
        #expect(gate("com.example.old", "com.example.new", "1.4.0", nil, "TEAM123456") == nil)
        // An installed copy at or past the bound, or without a version.
        #expect(gate("com.example.old", "com.example.new", "2.0.0", "TEAM123456", "TEAM123456") == nil)
        #expect(gate("com.example.old", "com.example.new", nil, "TEAM123456", "TEAM123456") == nil)
        // A different download.
        #expect(gate("com.example.old", "com.example.other", "1.4.0", "TEAM123456", "TEAM123456") == nil)
    }

    // MARK: - the rollback gate

    /// A rollback across the rename goes either way — old over new is the usual
    /// one — for the entry's Team only, with the old-id copy below the bound.
    @Test func aRollbackAcrossTheRenamePassesBothWaysForTheTeam() {
        #expect(BundleIDMigration.restoreMigration(
            backup: "com.example.old", installed: "com.example.new",
            backupVersion: "1.4.0", installedVersion: "2.0.0",
            backupTeam: "TEAM123456", installedTeam: "TEAM123456", in: Self.table) == Self.entry)
        #expect(BundleIDMigration.restoreMigration(
            backup: "com.example.new", installed: "com.example.old",
            backupVersion: "2.0.0", installedVersion: "1.4.0",
            backupTeam: "TEAM123456", installedTeam: "TEAM123456", in: Self.table) == Self.entry)
    }

    @Test func everyOtherRollbackIsRefused() {
        func gate(_ backup: String, _ installed: String, _ backupVersion: String?,
                  _ installedVersion: String?, _ backupTeam: String?, _ installedTeam: String?
        ) -> BundleIDMigration? {
            BundleIDMigration.restoreMigration(
                backup: backup, installed: installed,
                backupVersion: backupVersion, installedVersion: installedVersion,
                backupTeam: backupTeam, installedTeam: installedTeam, in: Self.table)
        }
        let old = "com.example.old", new = "com.example.new", team = "TEAM123456"
        // Another Team on either side, or none.
        #expect(gate(old, new, "1.4.0", "2.0.0", "OTHERTEAM1", team) == nil)
        #expect(gate(old, new, "1.4.0", "2.0.0", team, "OTHERTEAM1") == nil)
        #expect(gate(old, new, "1.4.0", "2.0.0", nil, team) == nil)
        #expect(gate(new, old, "2.0.0", "1.4.0", team, nil) == nil)
        // The old-id side at or past the bound, or without a version.
        #expect(gate(old, new, "2.0.0", "2.0.0", team, team) == nil)
        #expect(gate(old, new, nil, "2.0.0", team, team) == nil)
        #expect(gate(new, old, "2.0.0", "2.0.0", team, team) == nil)
        // An id the entry does not pair.
        #expect(gate("com.example.other", new, "1.4.0", "2.0.0", team, team) == nil)
        #expect(gate(old, "com.example.other", "1.4.0", "2.0.0", team, team) == nil)
    }

    /// The gate itself, on two real signed bundles with different ids: a
    /// registered rename between them is still refused when the bundles do not
    /// carry the entry's Team (Apple's system apps carry none). The passing
    /// direction needs two Developer ID builds of one renamed app, which is the
    /// real-machine run recorded in the WorkBuddy audit doc.
    @Test func theGateStillRequiresTheEntrysTeam() async throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")
        try #require(FileManager.default.fileExists(atPath: calculator.path))
        try #require(FileManager.default.fileExists(atPath: notes.path))
        let registered = [BundleIDMigration(
            from: "com.apple.calculator", to: "com.apple.Notes",
            teamID: "TEAM123456", lastFromVersion: "1", firstToVersion: "999")]
        await #expect(throws: SignatureVerifier.VerifyError.self) {
            try await offCooperativePool {
                try SignatureVerifier.verifyBundleIdentifierMatch(
                    installedApp: calculator, downloadedApp: notes, migrations: registered)
            }
        }
    }

    // MARK: - the real WorkBuddy entry, through the production lookups

    private static func workBuddy(id: String, version: String) -> InstalledApp {
        InstalledApp(
            name: "WorkBuddy", bundleID: id, shortVersion: version, buildVersion: version,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-WorkBuddy.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    @Test func anOldWorkBuddyCopyIsFiledUnderTheChinaSitesNewId() {
        #expect(Self.workBuddy(id: "com.workbuddy.workbuddy", version: "5.3.14").recipeBundleID
                == "com.tencent.workbuddy.mac")
        #expect(Self.workBuddy(id: "com.workbuddy.workbuddy", version: "5.5.4").recipeBundleID
                == "com.workbuddy.workbuddy")
        #expect(Self.workBuddy(id: "com.tencent.workbuddy.mac", version: "5.7.6").recipeBundleID
                == "com.tencent.workbuddy.mac")
        // The international app is a different product and never renamed.
        #expect(Self.workBuddy(id: "com.workbuddy.workbuddy-ai", version: "5.3.14").recipeBundleID
                == "com.workbuddy.workbuddy-ai")
    }

    /// `VendorProbeSource` picks the recipe by `recipeBundleID`: an old-id copy
    /// reaches the new id's recipe (a refused local port, so no network), and a
    /// copy past the bound reaches none.
    @Test func theVendorProbeFindsTheNewIdsRecipeForAnOldCopy() async throws {
        let recipe = VendorProbeRecipe(
            bundleID: "com.tencent.workbuddy.mac", url: URL(string: "http://127.0.0.1:1/update")!,
            mode: .responseBody, versionPattern: #""productVersion"\s*:\s*"([0-9.]+)""#)
        let source = VendorProbeSource(recipes: [recipe])
        let old = await source.probeDiagnostic(
            for: Self.workBuddy(id: "com.workbuddy.workbuddy", version: "5.3.14"))
        #expect(old?.recipeID == recipe.recipeID)
        #expect(await source.probeDiagnostic(
            for: Self.workBuddy(id: "com.workbuddy.workbuddy", version: "5.5.4")) == nil)
    }

    @Test func theChangelogRecipeIsTheNewIdsForAnOldCopy() throws {
        let result = UpdateResult(
            app: Self.workBuddy(id: "com.workbuddy.workbuddy", version: "5.3.14"),
            remote: nil, status: .upToDate)
        let recipe = try #require(ChangelogRecipeSelection.recipe(for: result))
        #expect(recipe.bundleID == "com.tencent.workbuddy.mac")
    }
}
