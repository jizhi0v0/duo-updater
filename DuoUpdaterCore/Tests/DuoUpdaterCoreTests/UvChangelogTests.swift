import Testing
import Foundation
@testable import DuoUpdaterCore

/// uv's `CHANGELOG.md` and its per-series archive files into one `Changelog`.
///
/// The fixtures are cut from the files as fetched on 2026-10-02, keeping each
/// shape the parser has to handle: the date line, a prose paragraph before the
/// first heading (0.12.12), the `###` categories, the series stubs, and the
/// archive files' 80-column wrapping and oldest-first order. No network: the
/// fetch is injected.
@Suite struct UvChangelogTests {

    static let current = """
        # Changelog

        <!-- prettier-ignore-start -->


        ## 0.12.21

        Released on 2026-09-29.

        ### Python

        - Update CPython to use OpenSSL 3.5.9 ([#22076](https://github.com/astral-sh/uv/pull/22076))

        ### Enhancements

        - Omit empty `[manifest]` tables from lockfiles that contain only manifest subtables ([#22070](https://github.com/astral-sh/uv/pull/22070))

        ### Bug fixes

        - Prevent `uv python pin --rm` from removing a global `.python-versions` file without `--global` ([#21992](https://github.com/astral-sh/uv/pull/21992))
        - Fix installed-package checks incorrectly reporting post-releases as incompatible ([#22049](https://github.com/astral-sh/uv/pull/22049))

        ## 0.12.12

        Released on 2026-09-09.

        The executables in our macOS and Windows release archives and `uv` and `uv_build` wheels are now code-signed. macOS executables are signed with an Apple Developer ID certificate and notarized by Apple.

        ### Bug fixes

        - Exclude distributions uploaded after the `exclude-newer` cutoff from lockfiles ([#21539](https://github.com/astral-sh/uv/pull/21539))

        ## 0.12.0

        Released on 2026-07-28.

        Since we released uv [0.11.0](https://github.com/astral-sh/uv/releases/tag/0.11.0) in March, we've accumulated changes.

        **We expect most users to be able to upgrade without making changes.**

        ### Breaking changes

        - **Define build systems by default with `uv init`** ([#19197](https://github.com/astral-sh/uv/pull/19197))

          Projects created with `uv init` now declare a build system and are packaged by default.

          ```console
          $ uv init example
          ```

          This stabilizes the `packaged-init` preview feature.
        - **Reject unsupported source distribution and wheel archive formats** ([#18927](https://github.com/astral-sh/uv/pull/18927))

        ### Bug fixes

        - Include extras activated by dependency groups when evaluating conflicts ([#20237](https://github.com/astral-sh/uv/pull/20237))

        ## 0.11.x

        See [changelogs/0.11.x](./changelogs/0.11.x.md)

        ## 0.10.x

        See [changelogs/0.10.x](./changelogs/0.10.x.md)

        ## 0.9.x

        See [changelogs/0.9.x](./changelogs/0.9.x.md)

        <!-- prettier-ignore-end -->
        """

    /// Oldest first, wrapped at 80 columns.
    static let archive09 = """
        <!-- prettier-ignore-start -->

        ## 0.9.0

        Released on 2025-10-07.

        This breaking release is primarily motivated by the release of Python 3.14, which contains some
        breaking changes.

        ### Breaking changes

        - **Python 3.14 is now the default stable version**

          The default Python version has changed from 3.13 to 3.14.

        - **Allow use of free-threaded variants in Python 3.14+ without explicit opt-in**
          ([#16142](https://github.com/astral-sh/uv/pull/16142))

        ## 0.9.18

        Released on 2025-12-16.

        ### Enhancements

        - Add value hints to command line arguments to improve shell completion accuracy
          ([#17080](https://github.com/astral-sh/uv/pull/17080))
        - Improve error handling in `uv publish` ([#17096](https://github.com/astral-sh/uv/pull/17096))

        ### Bug fixes

        - Avoid panics due to reads on failed requests
          ([#17098](https://github.com/astral-sh/uv/pull/17098))

        ## 0.9.19

        Released on 2025-12-19.

        ### Bug fixes

        - Fix a regression ([#17200](https://github.com/astral-sh/uv/pull/17200))
        """

    static func archive(_ versions: [String]) -> String {
        versions.map { "## \($0)\n\nReleased on 2026-01-01.\n\n### Bug fixes\n\n- Fixed something in \($0)\n" }
            .joined(separator: "\n")
    }

    @Test func parsesTheCurrentFile() throws {
        let changelog = try #require(UvChangelog.parse(Self.current))
        #expect(changelog.itemSyntax == .markdown)
        #expect(changelog.entries.map(\.version) == ["0.12.21", "0.12.12", "0.12.0"])
        let newest = changelog.entries[0]
        #expect(newest.date == "2026-09-29")
        #expect(newest.items.count == 4)
        #expect(newest.content.first == .heading("Python"))
        #expect(newest.content.filter { if case .heading = $0 { true } else { false } }.count == 3)
        #expect(newest.items[0] == "Update CPython to use OpenSSL 3.5.9 ([#22076](https://github.com/astral-sh/uv/pull/22076))")
        #expect(!newest.items.contains { $0.contains("Released on") })
    }

    /// The prose before the first heading leads the entry. Kills: dropping the
    /// paragraph-to-bullet step (0.12.12 would have only its one bug fix).
    @Test func prosePrecedingTheHeadingsLeadsTheEntry() throws {
        let entries = try #require(UvChangelog.parse(Self.current)).entries
        #expect(entries[1].items.first?.hasPrefix("The executables in our macOS and Windows release archives") == true)
        #expect(entries[1].items.count == 2)
        let breaking = entries[2]
        #expect(breaking.items.prefix(2) == [
            "Since we released uv [0.11.0](https://github.com/astral-sh/uv/releases/tag/0.11.0) in March, we've accumulated changes.",
            "**We expect most users to be able to upgrade without making changes.**",
        ])
        // The bold title of each breaking change; its indented explanation and
        // code block are not items.
        #expect(breaking.items.contains("**Define build systems by default with `uv init`** ([#19197](https://github.com/astral-sh/uv/pull/19197))"))
        #expect(!breaking.items.contains { $0.contains("uv init example") || $0.contains("packaged-init") })
        #expect(breaking.items.count == 5)
    }

    @Test func readsTheSeriesStubs() {
        let document = UvChangelog.document(Self.current)
        #expect(document.archives.map(\.series) == ["0.11.x", "0.10.x", "0.9.x"])
        #expect(document.archives.map(\.path) == ["changelogs/0.11.x.md", "changelogs/0.10.x.md", "changelogs/0.9.x.md"])
        #expect(UvChangelog.archivePath(["See [x](https://ZZFixture.example/evil.md)"]) == nil)
        #expect(UvChangelog.archivePath(["See [x](./../secrets/0.1.x.md)"]) == nil)
    }

    /// The archives wrap a bullet's link onto the next line. Kills: dropping the
    /// continuation join (the bullet would end mid-sentence without its link).
    @Test func joinsWrappedBullets() throws {
        let entries = UvChangelog.document(Self.archive09).entries
        #expect(entries.map(\.version) == ["0.9.0", "0.9.18", "0.9.19"])
        let release = entries[1]
        #expect(release.items == [
            "Add value hints to command line arguments to improve shell completion accuracy ([#17080](https://github.com/astral-sh/uv/pull/17080))",
            "Improve error handling in `uv publish` ([#17096](https://github.com/astral-sh/uv/pull/17096))",
            "Avoid panics due to reads on failed requests ([#17098](https://github.com/astral-sh/uv/pull/17098))",
        ])
        #expect(release.date == "2025-12-16")
        let breaking = entries[0]
        #expect(breaking.items == [
            "This breaking release is primarily motivated by the release of Python 3.14, which contains some breaking changes.",
            "**Python 3.14 is now the default stable version**",
            "**Allow use of free-threaded variants in Python 3.14+ without explicit opt-in** ([#16142](https://github.com/astral-sh/uv/pull/16142))",
        ])
    }

    /// 0.11.21's grouped bug fixes (`changelogs/0.11.x.md`, cut). Kills: dropping
    /// the label-to-scope rewrite (the group would read as its labels alone, the
    /// changes under them gone).
    @Test func groupedChangesKeepTheirLabel() throws {
        let section = """
            ## 0.11.21

            Released on 2026-06-30.

            ### Bug fixes

            - Improve cache robustness and pruning behavior
              - Allow CI cache pruning without an sdist bucket
                ([#19802](https://github.com/astral-sh/uv/pull/19802))
              - Reject running inside the cache ([#19659](https://github.com/astral-sh/uv/pull/19659))
            - Fix Python discovery and version request edge cases
              - Fix stop-discovery-at regression ([#19769](https://github.com/astral-sh/uv/pull/19769))
            - Avoid normalizing source distribution names twice
              ([#19784](https://github.com/astral-sh/uv/pull/19784))

            ### Documentation

            - Fix a typo ([#19800](https://github.com/astral-sh/uv/pull/19800))
            """
        let entry = try #require(UvChangelog.document(section).entries.first)
        #expect(entry.items == [
            "**Improve cache robustness and pruning behavior**: Allow CI cache pruning without an sdist bucket ([#19802](https://github.com/astral-sh/uv/pull/19802))",
            "**Improve cache robustness and pruning behavior**: Reject running inside the cache ([#19659](https://github.com/astral-sh/uv/pull/19659))",
            "**Fix Python discovery and version request edge cases**: Fix stop-discovery-at regression ([#19769](https://github.com/astral-sh/uv/pull/19769))",
            "Avoid normalizing source distribution names twice ([#19784](https://github.com/astral-sh/uv/pull/19784))",
            "Fix a typo ([#19800](https://github.com/astral-sh/uv/pull/19800))",
        ])
        #expect(entry.content.first == .heading("Bug fixes"))
    }

    final class Fetched: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [String] = []
        func add(_ url: URL) { lock.withLock { urls.append(url.absoluteString) } }
        var all: [String] { lock.withLock { urls } }
    }

    static func fetch(installed: String?, fetched: Fetched, minimum: Int = 5) async throws -> Changelog {
        try await UvChangelog.fetch(installed: installed, force: false, minimum: minimum) { url, _ in
            fetched.add(url)
            switch url.lastPathComponent {
            case "CHANGELOG.md": return Data(Self.current.utf8)
            case "0.11.x.md": return Data(Self.archive(["0.11.0", "0.11.1", "0.11.2"]).utf8)
            case "0.10.x.md": return Data(Self.archive(["0.10.0", "0.10.1"]).utf8)
            case "0.9.x.md": return Data(Self.archive09.utf8)
            default: throw CLIToolReleaseNotesError.http(404)
            }
        }
    }

    /// The current file alone covers a reader on the current series.
    @Test func currentSeriesNeedsNoArchive() async throws {
        let fetched = Fetched()
        let changelog = try await Self.fetch(installed: "0.12.12", fetched: fetched, minimum: 3)
        #expect(fetched.all == [UvChangelog.source.absoluteString])
        #expect(changelog.entries.map(\.version) == ["0.12.21", "0.12.12", "0.12.0"])
    }

    /// Down to the reader's own release, newest first across files, and on while
    /// `relevant` would want more at or below it. Kills: appending an archive in
    /// its own (oldest-first) order, and stopping before the reader's series.
    @Test func olderInstallReadsTheArchivesItNeeds() async throws {
        let fetched = Fetched()
        let changelog = try await Self.fetch(installed: "0.9.18", fetched: fetched)
        #expect(fetched.all == [
            "https://raw.githubusercontent.com/astral-sh/uv/main/CHANGELOG.md",
            "https://raw.githubusercontent.com/astral-sh/uv/main/changelogs/0.11.x.md",
            "https://raw.githubusercontent.com/astral-sh/uv/main/changelogs/0.10.x.md",
            "https://raw.githubusercontent.com/astral-sh/uv/main/changelogs/0.9.x.md",
        ])
        #expect(changelog.entries.map(\.version) == [
            "0.12.21", "0.12.12", "0.12.0", "0.11.2", "0.11.1", "0.11.0", "0.10.1", "0.10.0", "0.9.19", "0.9.18", "0.9.0",
        ])
        // Every release after the reader's own, nothing missing in between.
        let relevant = try #require(CLIToolChangelog.relevant(changelog, installed: "0.9.18", latest: "0.12.21"))
        #expect(relevant.entries.map(\.version) == [
            "0.12.21", "0.12.12", "0.12.0", "0.11.2", "0.11.1", "0.11.0", "0.10.1", "0.10.0", "0.9.19",
        ])

        // On the first release of a series with few after it, the series before
        // is read too, for `relevant`'s five; then no more.
        let early = Fetched()
        let earlyNotes = try await Self.fetch(installed: "0.12.0", fetched: early)
        #expect(early.all.count == 2)
        #expect(try #require(CLIToolChangelog.relevant(earlyNotes, installed: "0.12.0", latest: "0.12.21"))
            .entries.map(\.version) == ["0.12.21", "0.12.12", "0.12.0", "0.11.2", "0.11.1"])
    }

    @Test func unknownInstalledVersionReadsTheCurrentFileOnly() async throws {
        let fetched = Fetched()
        _ = try await Self.fetch(installed: nil, fetched: fetched)
        #expect(fetched.all.count == 1)
    }

    @Test func aPageThatIsNotTheChangelogIsNoSections() async {
        #expect(UvChangelog.parse("404: Not Found") == nil)
        await #expect(throws: CLIToolReleaseNotesError.noSections) {
            try await UvChangelog.fetch(installed: nil, force: false) { _, _ in Data("<html></html>".utf8) }
        }
    }

    /// Two copies on different series read different documents, so the app must
    /// not keep one for both; two on the same series share one.
    ///
    /// Mutation: return "uv" for every version.
    @Test func eachSeriesHasItsOwnReleaseNotesKey() {
        #expect(UvChangelog.releaseNotesKey(installed: "0.9.18") == "uv:0.9")
        #expect(UvChangelog.releaseNotesKey(installed: "0.9.2") == "uv:0.9")
        #expect(UvChangelog.releaseNotesKey(installed: "0.12.21") != UvChangelog.releaseNotesKey(installed: "0.9.18"))
    }
}
