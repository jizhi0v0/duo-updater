import Foundation

/// Homebrew's own release notes, for the self-update row (`HomebrewSelfUpdate`):
/// its GitHub Releases (`Homebrew/brew`), read the way the CLI tools' GitHub
/// notes are (`StarshipChangelog`, `MiseChangelog`).
///
/// The shape, fetched 2026-10-09 (7.0.0 through 7.0.9): GitHub's generated
/// notes. An HTML comment naming `.github/release.yml`, `## What's Changed` with
/// one `* <title> by @user in <pull URL>` bullet per pull request, sometimes
/// `## New Contributors`, then `**Full Changelog**: <compare URL>`. Tags are
/// bare `7.0.9`, none marked prerelease. A major release runs long (7.0.0:
/// 135 changes); a patch is a handful to a few dozen. `GitHubMarkdownParser` drops the
/// contributor and full-changelog sections and the `by @user in <URL>` tails
/// itself, so no cleaning or skip list is needed here.
public enum HomebrewReleaseNotes {

    /// Thirty reached back to 6.0.3, past the last major, on 2026-10-09.
    public static let source = URL(string: "https://api.github.com/repos/Homebrew/brew/releases?per_page=30")!

    /// Newest first, stable `x.y.z` tags only; nil when none yields an entry.
    public static func parse(_ json: String) -> Changelog? {
        StructuredChangelogDecoder.decode(
            json, format: .gitHubReleases, channel: nil, maxEntries: nil,
            tagPattern: #"^(\d+\.\d+\.\d+)$"#)
    }

    /// The releases `update` would bring: newer than what is installed, up to the
    /// latest on offer, newest first. nil when there are none.
    ///
    /// A developer-mode checkout reads `7.0.9-8-g…`, which `VersionComparator`
    /// orders after 7.0.9 and before 7.0.10, so 7.0.9's notes are not listed as
    /// news to it (`HomebrewReleaseNotesTests.developerModeIsReadByItsReleasePart`).
    public static func relevant(_ changelog: Changelog, for update: HomebrewSelfUpdate) -> Changelog? {
        CLIToolChangelog.relevant(changelog, installed: update.installed, latest: update.latest, minimum: 0)
    }

    /// The release list, through the URL cache's revalidation and with the token
    /// `ChangelogService` sends, like every other GitHub Releases changelog.
    public static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        try await DenoChangelog.gitHubReleases(source, force: force, session: session) {
            parse(String(decoding: $0, as: UTF8.self))
        }
    }
}
