import Testing
@testable import DuoUpdaterCore

/// The "updates available" banner for command-line tools and Homebrew packages:
/// each category's baseline and dedupe (`UpdateAnnouncementLedger`), the one
/// banner a round posts (`UpdateBanner`), and the badge's sum
/// (`BadgeReadout.total`). Pure values; nothing is posted.
struct UpdateAnnouncementsTests {

    static func item(_ name: String, _ version: String, key: String? = nil) -> UpdateAnnouncementItem {
        UpdateAnnouncementItem(key: key ?? "npm:/p/\(name)", name: name, version: version)
    }

    // MARK: ledger

    /// The first pass ever adopts what is pending as the baseline, silently; a
    /// later pass announces only what is new.
    ///
    /// Mutation: drop the `guard seeded` branch.
    @Test func theFirstPassIsASilentBaseline() {
        var ledger = UpdateAnnouncementLedger()
        #expect(ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.1")], liveKeys: nil) == [])
        #expect(ledger.seeded)

        let offered = [Self.item("uv", "0.9.1"), Self.item("fx", "1.0")]
        #expect(ledger.pass(enabled: true, offered: offered, liveKeys: nil) == ["fx"])
    }

    /// An offer is announced once, a new version of it again, and an endpoint
    /// flapping back to a version already announced is not.
    ///
    /// Mutations: drop the `!versions.wasAnnounced` filter; drop the
    /// `versions.record` loop after the first pass.
    @Test func eachVersionIsAnnouncedOnce() {
        var ledger = UpdateAnnouncementLedger()
        _ = ledger.pass(enabled: true, offered: [], liveKeys: nil)

        #expect(ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.1")], liveKeys: nil) == ["uv"])
        #expect(ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.1")], liveKeys: nil) == [])
        #expect(ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.2")], liveKeys: nil) == ["uv"])
        #expect(ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.1")], liveKeys: nil) == [])
    }

    /// With the switch off nothing is announced and nothing recorded — not even
    /// the baseline, which is taken silently the first time it is on.
    ///
    /// Mutation: drop `guard enabled`.
    @Test func aCategorySwitchedOffIsLeftAlone() {
        var ledger = UpdateAnnouncementLedger()
        #expect(ledger.pass(enabled: false, offered: [Self.item("jq", "1.8")], liveKeys: nil) == [])
        #expect(ledger == UpdateAnnouncementLedger())

        #expect(ledger.pass(enabled: true, offered: [Self.item("jq", "1.8")], liveKeys: nil) == [])
        #expect(ledger.seeded)
    }

    /// An item no longer installed is forgotten, so the map cannot grow without
    /// bound — unless the caller cannot tell, and passes nil.
    ///
    /// Mutation: drop the `prune` line.
    @Test func goneItemsAreForgottenOnlyWhenTheCallerKnows() {
        var ledger = UpdateAnnouncementLedger()
        _ = ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.1")], liveKeys: nil)

        _ = ledger.pass(enabled: true, offered: [], liveKeys: ["npm:/p/uv"])
        #expect(ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.1")], liveKeys: nil) == [])

        _ = ledger.pass(enabled: true, offered: [], liveKeys: [])
        #expect(ledger.pass(enabled: true, offered: [Self.item("uv", "0.9.1")], liveKeys: nil) == ["uv"])
    }

    /// Two copies of one tool are two items, and one name in the banner.
    @Test func twoCopiesAreNamedOnce() {
        var ledger = UpdateAnnouncementLedger()
        _ = ledger.pass(enabled: true, offered: [], liveKeys: nil)
        let offered = [
            Self.item("Claude Code", "2.1.285", key: "claude-code:/a"),
            Self.item("Claude Code", "2.1.285", key: "claude-code:/b"),
        ]
        #expect(ledger.pass(enabled: true, offered: offered, liveKeys: nil) == ["Claude Code"])
    }

    // MARK: banner

    static func part(_ category: UpdateBanner.Category, _ enabled: Bool, _ newly: [String], _ pending: Int)
        -> UpdateBanner.Part
    {
        UpdateBanner.Part(category: category, enabled: enabled, newly: newly, pending: pending)
    }

    /// One banner across the categories that are on: their new names, apps
    /// first, and their pending counts summed; a category that is off adds
    /// neither.
    ///
    /// Mutation: drop `.filter(\.enabled)` from `compose`.
    @Test func theBannerCoversOnlyTheCategoriesThatAreOn() {
        let content = UpdateBanner.compose([
            Self.part(.homebrew, false, ["jq"], 4),
            Self.part(.commandLineTools, true, ["uv"], 2),
            Self.part(.apps, true, ["Zed"], 3),
        ])
        #expect(content == UpdateBanner.Content(total: 5, names: ["Zed", "uv"], appsOnly: false))

        #expect(UpdateBanner.compose([
            Self.part(.apps, true, [], 3),
            Self.part(.homebrew, false, ["jq"], 4),
        ]) == nil)
    }

    /// "Update All" updates apps, so the banner offers it only when everything
    /// new is an app.
    ///
    /// Mutation: `appsOnly` always true.
    @Test func updateAllIsOfferedOnlyForApps() {
        #expect(UpdateBanner.compose([
            Self.part(.apps, true, ["Zed"], 1), Self.part(.commandLineTools, true, [], 2),
        ])?.appsOnly == true)
        #expect(UpdateBanner.compose([
            Self.part(.apps, true, ["Zed"], 1), Self.part(.homebrew, true, ["jq"], 1),
        ])?.appsOnly == false)
    }

    // MARK: badge

    /// Apps always count; command-line tools and Homebrew only while their
    /// switches are on.
    ///
    /// Mutations: drop either `counts…` condition.
    @Test func theBadgeFollowsTheSwitches() {
        #expect(BadgeReadout.total(apps: 2, commandLineTools: 3, homebrew: 5,
                                   countsCommandLineTools: true, countsHomebrew: false) == 5)
        #expect(BadgeReadout.total(apps: 2, commandLineTools: 3, homebrew: 5,
                                   countsCommandLineTools: false, countsHomebrew: true) == 7)
        #expect(BadgeReadout.total(apps: 2, commandLineTools: 3, homebrew: 5,
                                   countsCommandLineTools: false, countsHomebrew: false) == 2)
    }
}
