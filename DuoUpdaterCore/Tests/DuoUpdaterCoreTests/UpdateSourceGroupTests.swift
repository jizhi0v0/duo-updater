import Foundation
import Testing
@testable import DuoUpdaterCore

/// Which section a row lands in when the Apps list is grouped by update source
/// (#1985): the source Update would use, Homebrew for a brew copy no source has
/// anything newer for.
struct UpdateSourceGroupTests {

    private func row(
        _ name: String, source: String?, status: UpdateStatus = .upToDate,
        brewOwner: String? = nil
    ) -> UpdateResult {
        let app = InstalledApp(
            name: name, bundleID: "com.example.\(name.lowercased())",
            shortVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/\(name).app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
        let remote = source.map {
            RemoteVersion(shortVersion: "2.0", version: nil, downloadURL: nil, sourceName: $0)
        }
        var result = UpdateResult(app: app, remote: remote, status: status)
        result.homebrewSourceIdentifier = brewOwner
        return result
    }

    @Test func eachKnownSourceNameHasItsGroup() {
        let expected: [String: UpdateSourceGroup] = [
            "Sparkle": .sparkle, "GitHub": .gitHub, "Electron": .appFeed,
            MyGoUpdateSource.sourceName: .appFeed, "Vendor": .vendor,
            "Homebrew": .homebrew, "App Store": .appStore, "Setapp": .setapp,
            "TestFlight": .testFlight, "Toolbox": .toolbox,
            "Xcode Releases": .xcodeReleases, "Something new": .other,
        ]
        for (name, group) in expected {
            #expect(UpdateSourceGroup(sourceName: name) == group, "\(name)")
        }
    }

    /// Brew had nothing newer and Sparkle has an update: Update uses Sparkle, so
    /// the row is in the Sparkle section.
    ///
    /// Mutation: drop the `status == .upToDate` condition.
    @Test func aBrewCopyWithAnUpdateFromAnotherSourceGroupsUnderThatSource() {
        let r = row("A", source: "Sparkle", status: .updateAvailable(latest: "2.0"), brewOwner: "a")
        #expect(UpdateSourceGroup(r) == .sparkle)
    }

    /// Neither brew nor the other source has anything newer: the row stays under
    /// Homebrew, which installed it.
    ///
    /// Mutation: drop the `homebrewSourceIdentifier != nil` branch.
    @Test func aBrewCopyThatIsUpToDateEverywhereGroupsUnderHomebrew() {
        #expect(UpdateSourceGroup(row("A", source: "Sparkle", brewOwner: "a")) == .homebrew)
        // Not a brew copy: the source that answered.
        #expect(UpdateSourceGroup(row("B", source: "Sparkle")) == .sparkle)
    }

    @Test func managedStatusesGroupWithoutARemote() {
        #expect(UpdateSourceGroup(row("A", source: nil, status: .appStoreManaged)) == .appStore)
        #expect(UpdateSourceGroup(row("B", source: nil, status: .testFlightManaged)) == .testFlight)
        #expect(UpdateSourceGroup(row("C", source: nil, status: .toolboxManaged)) == .toolbox)
        #expect(UpdateSourceGroup(row("D", source: nil, status: .error("offline"))) == .other)
    }

    /// Sections come in `allCases` order and each keeps the rows' own order, so
    /// the tier order and the chosen sort still hold inside a section.
    @Test func sectionsKeepRowOrderAndGroupOrder() {
        let rows = [
            row("Z", source: "Homebrew"),
            row("Y", source: "Sparkle", status: .updateAvailable(latest: "2.0")),
            row("X", source: "Homebrew"),
            row("W", source: "Sparkle"),
            row("V", source: nil, status: .unknown),
        ]
        let sections = UpdateSourceGroup.sections(rows)
        #expect(sections.map(\.group) == [.sparkle, .homebrew, .other])
        #expect(sections.map { $0.rows.map(\.app.name) } == [["Y", "W"], ["Z", "X"], ["V"]])
    }

    /// The grouping function decides, so a group held while the order is frozen
    /// wins over the row's current one.
    @Test func sectionsUseTheGroupTheyAreGiven() {
        let rows = [row("A", source: "Sparkle"), row("B", source: "Sparkle")]
        let sections = UpdateSourceGroup.sections(rows) { $0.app.name == "A" ? .homebrew : UpdateSourceGroup($0) }
        #expect(sections.map(\.group) == [.sparkle, .homebrew])
    }
}
