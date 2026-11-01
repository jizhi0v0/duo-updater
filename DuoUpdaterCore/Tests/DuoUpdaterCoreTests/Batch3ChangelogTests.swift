import Foundation
import Testing

@testable import DuoUpdaterCore

/// The release bodies of the four batch-3 apps, as the vendor writes them.
/// `GitHubMarkdownParser` is what turns each into structured notes; these pin the
/// shapes the recipes rely on — plain bullets (LosslessCut), real headings
/// (Super Productivity), a body that opens with download tables (ActivityWatch),
/// and GitHub's PR-list tail with `by @user in …` (GitUp).
@Suite struct Batch3ChangelogTests {

    private func entry(_ body: String, version: String, skipSections: [String] = []) throws
        -> Changelog.Entry
    {
        let changelog = try #require(GitHubMarkdownParser.parse(
            body: body, version: version, date: nil, skipSections: skipSections))
        return try #require(changelog.entries.first)
    }

    /// LosslessCut: a plain bullet list with no headings; the item lines are the
    /// changes themselves.
    @Test func losslessCutBulletsBecomeItems() throws {
        let e = try entry(Self.losslessCut, version: "3.70.2")
        #expect(e.items.count == 5)
        #expect(e.items.contains { $0.contains("Fix detecting silent and black scenes") })
        #expect(e.items.allSatisfy { !$0.hasPrefix("- ") })
    }

    /// Super Productivity: `### Improvements` / `### Fixes` survive as headings,
    /// and the `### Contributors` roll call (boilerplate in every release) is
    /// skipped. Mutation: drop `skipSections` → the contributor line becomes an
    /// item.
    @Test func superProductivityKeepsItsHeadingsAndDropsContributors() throws {
        let e = try entry(Self.superProductivity, version: "19.3.1",
                          skipSections: ["Contributors"])
        #expect(e.items.count == 11, "items: \(e.items)")
        #expect(e.content.contains { block in
            if case .heading(let text) = block { return text.contains("Improvements") }
            return false
        })
        #expect(!e.items.contains { $0.contains("@johannesjo") })
        #expect(!e.items.contains { $0.contains("Full Changelog") })
    }

    /// ActivityWatch: the body opens with `# Installation` / `# Downloads` (and a
    /// download table per edition) before `# Changelog`. Those sections are
    /// skipped, so no release-asset link becomes a "change".
    @Test func activityWatchSkipsTheDownloadTables() throws {
        let e = try entry(Self.activityWatch, version: "0.14.1", skipSections: [
            "Installation", "Downloads", "Classic distribution",
            "Tauri distribution (experimental — native Wayland support on Linux)",
            "Support ActivityWatch", "Contributors", "Changelog",
        ])
        #expect(!e.items.isEmpty)
        #expect(e.items.contains { $0.contains("feat(research): ship an optional") })
        #expect(!e.items.contains { $0.contains("/releases/download/") })
    }

    /// GitUp: the PR list's `by @user in <url>` suffix is stripped, and the
    /// highlights bullets survive.
    @Test func gitUpStripsThePullRequestAttribution() throws {
        let e = try entry(Self.gitUp, version: "1.5.0")
        #expect(e.items.contains { $0.contains("Updated Tahoe design") })
        #expect(!e.items.contains { $0.contains("by @") }, "items: \(e.items)")
    }

    // MARK: - Real bodies (trimmed)

    private static let losslessCut = """
- (Windows) Fix detecting silent and black scenes, which found nothing in 3.70.0 and 3.70.1 #3174 #3178
- Fix extracting attachments showing an error even though they were extracted, and a warning about unprocessable streams when exporting files with attachments
- (Linux) The arm64 build now includes FFmpeg
- (Linux) Docks show LosslessCut's own icon for the AppImage when its launcher is installed under another name, e.g. by AppImageLauncher #3172
- Help links open the documentation on losslesscut.app, and the Discord link in the error report dialog now opens Discord

See [3.70.0](https://github.com/mifi/lossless-cut/releases/tag/v3.70.0) for the full list of changes.
"""

    private static let superProductivity = """
For all current downloads, package links, and platform-specific notes: [check the wiki](https://github.com/super-productivity/super-productivity/wiki/2.01-Downloads-and-Install).

### Improvements

- Collapse project task tables in the daily summary.
- Open the download page directly from the update banner.
- Subtler due badges, mobile play button, and planner calendar colors.

### Fixes

- Ask for confirmation before loading remote sync data when it is missing your previous uploads.
- Show an exact-alarm hint in reminder settings.
- Use locale-correct leading zeros in short dates.
- Allow touch scrolling over recurring task rows.
- Pause issue and calendar polling while offline and catch up on reconnect.
- Keep planner calendar colors up to date.

### Desktop fixes

- Run pending shutdown work when quitting from the tray.
- Prevent two Snap revisions from opening the same local database.

### Contributors

Thanks to everyone who contributed to this release: @johannesjo

**Full Changelog**: https://github.com/super-productivity/super-productivity/compare/v19.3.0...v19.3.1
"""

    private static let activityWatch = """
These are the release notes for ActivityWatch version v0.14.1.

**New to ActivityWatch?** Check out the [website](https://activitywatch.net) and the [README](https://github.com/ActivityWatch/activitywatch/blob/master/README.md).

# Installation

See the [getting started guide in the documentation](https://docs.activitywatch.net/en/latest/getting-started.html).

# Downloads

## Classic distribution

 - [**Windows**](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-v0.14.1-windows-x86_64-setup.exe) (.exe installer)
 - **macOS**: [Intel](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-v0.14.1-macos-x86_64.dmg) | [Apple Silicon](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-v0.14.1-macos-arm64.dmg) (.dmg)
 - **Linux**: [.zip](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-v0.14.1-linux-x86_64.zip) | [.AppImage](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-linux-x86_64.AppImage) | [.deb](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-v0.14.1-linux-x86_64.deb)

## Tauri distribution (experimental — native Wayland support on Linux)

 - [**Windows**](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-tauri-v0.14.1-windows-x86_64-setup.exe) (.exe installer)
 - **macOS**: [Intel](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-tauri-v0.14.1-macos-x86_64.dmg) | [Apple Silicon](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-tauri-v0.14.1-macos-arm64.dmg) (.dmg)
 - **Linux**: [.AppImage](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-tauri-0.14.1-linux-x86_64.AppImage) | [.zip](https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-tauri-v0.14.1-linux-x86_64.zip)

# Support ActivityWatch

ActivityWatch is free and open source, with no feature gates. If it is useful to you, [AW Pro](https://activitywatch.net/subscribe/) is an optional subscription that funds ongoing development.

# Contributors

Thanks to everyone who contributed to this release:

@0xbrayo, @AbdulGoodLooks, @erikbjare, @Gabriel-Dalton, @kvnloo, @TimeToBuildBob

# Changelog

Changes since [v0.14.0](https://github.com/ActivityWatch/activitywatch/releases/tag/v0.14.0):


## 📦 activitywatch

### ✨ Features (3)

 - feat(research): ship an optional geography-free category preset ([#1474](https://github.com/ActivityWatch/activitywatch/issues/1474)) ([`21142d0`](https://github.com/ActivityWatch/activitywatch/commit/21142d0))
 - feat(scripts): automated screenshots with realistic demo data ([#1500](https://github.com/ActivityWatch/activitywatch/issues/1500)) ([`bbcc9b8`](https://github.com/ActivityWatch/activitywatch/commit/bbcc9b8))
 - feat(changelog): add a Support ActivityWatch section to bundle release notes ([#1486](https://github.com/ActivityWatch/activitywatch/issues/1486)) ([`45ae1c8`](https://github.com/ActivityWatch/activitywatch/commit/45ae1c8))

### 🐛 Fixes (7)
<details><summary>Click to expand</summary>
<p>

 - fix(release): don't bundle libwayland into the Tauri AppImage, and gate it ([#1509](https://github.com/ActivityWatch/activitywatch/issues/1509)) ([`2251b6e`](https://github.com/ActivityWatch/activitywatch/commit/2251b6e))
 - fix(build): drop stale Tauri bundles, and stop packaging from failing silently ([#1512](https://github.com/ActivityWatch/activitywatch/issues/1512)) ([`df22b2e`](https://github.com/ActivityWatch/activitywatch/commit/df22b2e))
 - fix(package): Linux Tauri zip: drop move-to-aw-modules.sh and the loose awatcher, rewrite README ([#1508](https://github.com/ActivityWatch/activitywatch/issues/1508)) ([`ed54fd7`](https://github.com/ActivityWatch/activitywatch/commit/ed54fd7))
 - fix(make): use pip's freeze format in the uninstall target ([#1505](https://github.com/ActivityWatch/activitywatch/issues/1505)) ([`017d703`](https://github.com/ActivityWatch/activitywatch/commit/017d703))
 - fix(linux): stop bundling host-ABI libraries in the Qt bundle ([#1484](https://github.com/ActivityWatch/activitywatch/issues/1484)) ([`0ef9191`](https://github.com/ActivityWatch/activitywatch/commit/0ef9191))
 - fix(changelog): use /commits/`<tip>` when submodule is new to the release ([#1504](https://github.com/ActivityWatch/activitywatch/issues/1504)) ([`81885e2`](https://github.com/ActivityWatch/activitywatch/commit/81885e2))
 - fix(changelog): use /commits/`<tip>` when submodule is new to the release ([#1496](https://github.com/ActivityWatch/activitywatch/issues/1496)) ([`d02cc21`](https://github.com/ActivityWatch/activitywatch/commit/d02cc21))

</p>
</details>

### 🔨 Misc (6)

 - chore: migrate issue templates to issue forms ([#1482](https://github.com/ActivityWatch/activit
"""

    private static let gitUp = """
## What's Changed
### The highlights for this release are as follows:
- Updated Tahoe design with modern Sparkle updater APIs
- Updated to libgit2 from version 1.4.4 to 1.9.0, this provides support for:
  - OpenSSH so no more struggling to just use your system SSH keys
  - Shallow clones

### A whole bunch of updates from GitHub PRs:
* Fix some “Stage All” special cases by @Cykelero in https://github.com/git-up/GitUp/pull/1037
* Update libgit2 fork to v1.9.0 by @Cykelero in https://github.com/git-up/GitUp/pull/2683
* Update Homebrew cask name in README by @Quintisimo in https://github.com/git-up/GitUp/pull/2726
* Make reloadHistory tip hiding much faster by @Cykelero in https://github.com/git-up/GitUp/pull/2707
* Make the Text Size preference apply to the text in the diff view, not just the line numbers by @mluisbrown in https://github.com/git-up/GitUp/pull/2727
* Fix highlight range computation for non-ascii characters by @lucasderraugh in https://github.com/git-up/GitUp/pull/2742
* Fix crash when staging lines with the index locked by @Cykelero in https://github.com/git-up/GitUp/pull/2771
* Add GitUpKit to readme intro by @Cykelero in https://github.com/git-up/GitUp/pull/2776
* Allow opening containing repo from subdirectory by @lucasderraugh in https://github.com/git-up/GitUp/pull/2777
* Improve selected files performance lag in Commit View by @delacrixmorgan in https://github.com/git-up/GitUp/pull/2780
* Bump to macOS 12.4 min target by @lucasderraugh in https://github.com/git-up/GitUp/pull/2785
* Move back to CMake for libgit2 compilation by @lucasderraugh in https://github.com/git-up/GitUp/pull/2786
"""
}
