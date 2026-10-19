import Testing
import Foundation
@testable import DuoUpdaterCore

/// Tamio's release notes. Its appcast holds one item whose `<description>` is
/// that release's notes as plain text, so the history and the Keep a Changelog
/// groups come only from the repo's `CHANGELOG.md`.
///
/// The fixture is the real file's first 50 lines, verbatim (vendor commit
/// `5ba4a822`, fetched 2026-10-19): the preamble, the `[Unreleased]` section,
/// and the 0.2.4 and 0.2.3 entries, whose bullets wrap with a two-space indent.
/// The preamble quotes an entry heading, `` (`## [0.2.0] - 2026-11-02`) ``, in
/// the middle of a line; it must not become an entry.
struct TamioChangelogRecipeTests {
    private static let bundleID = "sb.moe.tamio"

    private static let fixture = """
    # Changelog

    All notable changes to Tamio are documented in this file. The format is based
    on [Keep a Changelog](https://keepachangelog.com); versions follow semver.
    Each release's notes come from its section here: on the GitHub release, and in
    the update window that offers it. A tag with no section here is not built.

    Write new entries under **Unreleased**, as **Added**, **Changed**, **Fixed** or
    **Removed**, each item opening with a bold phrase that says what changed for
    the user. To release, rename that heading to the version and date
    (`## [0.2.0] - 2026-11-02`), set `MARKETING_VERSION` to match, and tag
    `v0.2.0`.

    ## [Unreleased]

    ### Fixed
    - **Terminals open on JumpServer bastions.** A JumpServer (Koko) bastion
      closed the session right after signing in, because Tamio sent the window
      size before asking for a shell and the bastion never answered. The size now
      follows the shell, so its asset menu appears. When a server refuses the
      terminal or the shell, the terminal now says so instead of only Connection
      Closed.

    ## [0.2.4] - 2026-10-18

    ### Added
    - **A proxy command for a server.** In Edit Server › Advanced, a Proxy command
      field carries the connection through a command instead of directly to the
      address, the way ssh_config's ProxyCommand does: a Cloudflare Access tunnel
      is `cloudflared access ssh --hostname %h`, where `%h` is the address and
      `%p` the port. Terminals, SFTP, live status, port forwards, snippets and
      agent commands all go through it, and a command that fails to start says
      why. It is kept with the server and synced. Left empty, the server connects
      directly, as before.

    ### Fixed
    - **The group switcher no longer flashes on a click.** Choosing a group, or
      clicking the one already chosen, showed a large glass lens and snapped the
      selection back for a moment; the selection now slides to the new group, and
      the server cards stay put instead of animating as the list changes.

    ## [0.2.3] - 2026-10-18

    ### Added
    - **Home shows one group at a time.** A switcher at the top left of the
      toolbar, beside search and New Server, lists All, every group a server is
      in, and No Group for the servers in none; a click shows only that group's
      cards, and the choice is kept for the next launch. It appears once a
      server has a group.
    """

    private static var recipe: ChangelogRecipe {
        get throws {
            try #require(ChangelogRecipeRegistry.recipes.first { $0.bundleID == bundleID })
        }
    }

    @Test func theRecipeReadsTheRepositorysChangelogFile() throws {
        let recipe = try Self.recipe
        #expect(recipe.source.host == "raw.githubusercontent.com")
        #expect(recipe.source.path == "/missuo/tamio/main/CHANGELOG.md")
        #expect(recipe.markdownSource)
        #expect(recipe.channel == nil, "Tamio publishes one train")
    }

    /// The first entry must be the shipped version: `[Unreleased]` describes a
    /// build nobody can install. The preamble's quoted `## [0.2.0] - 2026-11-02`
    /// must not add a 0.2.0 entry either: it is not at the start of a line, and
    /// no bullet follows it (so even an unanchored pattern finds no items there).
    @Test func theUnreleasedSectionIsNotAnEntry() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        #expect(parsed.entries.map(\.version) == ["0.2.4", "0.2.3"])
        #expect(parsed.entries.first?.date == "2026-10-18")
    }

    @Test func wrappedBulletsComeBackWholeUnderTheirGroups() throws {
        let parsed = try #require(ChangelogService.parse(try Self.recipe, body: Self.fixture))
        let newest = try #require(parsed.entries.first)
        #expect(newest.items.count == 2)
        let first = try #require(newest.items.first)
        #expect(first.hasSuffix("Left empty, the server connects directly, as before."),
                "the item was cut at a line break or ran past its bullet: \(first)")
        #expect(newest.content == [
            .heading("Added"),
            .note(newest.items[0]),
            .heading("Fixed"),
            .note(newest.items[1]),
        ])
        for item in parsed.entries.flatMap(\.items) {
            #expect(!item.contains("###"), "a group heading leaked into an item: \(item)")
        }
    }
}
