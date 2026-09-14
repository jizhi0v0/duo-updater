import Testing
import Foundation
@testable import DuoUpdaterCore

/// `docs.aside.com/changelog/native.md`, fetched 2026-09-14 and trimmed: the page
/// header, the whole 1.0.914.1 entry (the Windows launch, a heading with no notes
/// under it), one line of 1.0.910.1, the start of 1.0.713.3 (paragraphs and a
/// fenced command), and the first two notes of the two oldest-style entries kept
/// here — 1.0.626.1 (a `v` heading with a date line) and 1.0.624.1 (a bare heading).
private let asideChangelogFixture = #"""
> ## Documentation Index
> Fetch the complete documentation index at: https://docs.aside.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Aside Browser

> Changelog for Aside Browser

## v1.0.914.1

### Aside is now officially available on Windows!

### Improved Agent Tabs

* Selecting an agent tab now lets you use it as a regular page without pressing Take over. Automatically taken-over tabs return to Agent Tabs when you switch away.
* Tabs used by external agents connected through MCP or CLI now appear in a single Agent Tabs group in the sidebar.

### Improved memory usage and profile handling

* Tabs now preserve their original profile and navigation history when discarded to save memory after a profile switch.
* Fixed unused color data accumulating in memory as the toolbar adapted to page colors.

### Fixes and Improvements

* Fixed agent tab order changing or nearby sidebar items shifting when selecting agent tabs or returning them to their group.
* Fixed automatic Agent Tabs positioning conflicting with other tab groups or split tabs.
* Fixed toolbar colors and the address bar divider failing to refresh after taking over an agent tab.
* Fixed empty Agent Tabs groups remaining in saved groups and unnecessary agent groups being recreated when restoring closed pages.
* Removed the extra group-deletion confirmation when closing the last tab in a saved tab group.
* Fixed remaining tab groups becoming unresponsive after canceling a tab-close request.
* Improved stability during bookmark animations, Ask Aside tab placement, window shutdown, and toolbar initialization.
* Improved system and tray menus on Windows, and fixed a possible crash when opening and closing overlapping menus.
* Fixed a possible crash from clipboard change notifications during browser shutdown on macOS.
* Fixed request completion handling when a redirect was paused in developer tools.

## v1.0.910.1

### Fixes and Improvements

* Updated Chromium to `152.0.7977.83`.

## v1.0.713.3

### New: Profile Switcher

You can now switch profiles inside a single window.

* In vertical tabs, swipe left/right on a macOS trackpad to smoothly switch profiles.
* In horizontal tabs, click the profile icon to switch to another profile.

### Hidden option: disable window background transparency

We added a hidden option to remove background transparency at the system level.

Disable window background vibrancy:

```
defaults write at.studio.AsideBrowser windowBackgroundVibrancyDisabled -bool true
```

## v1.0.626.1

June 26, 2026

### Fixes and improvements

* Fixed an issue where the profile area and buttons overlapped in the vertical tab sidebar.
* Fixed installed extensions being cut off when there are many extensions. The list is now scrollable.

## 1.0.624.1

June 24, 2026

* \[Improvement] **Browser engine**: Updates the Chromium base from 149.0.7827.156 to 149.0.7827.197.
* \[Improvement] **Bundled Aside components**: Updates the bundled agent, password manager, and local service components to the latest release.
"""#

@Suite struct AsideChangelogRecipeTests {

    private func changelog() throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "at.studio.AsideBrowser"))
        return try #require(ChangelogExtractor.extract(from: asideChangelogFixture, using: recipe))
    }

    /// Both heading spellings, in page order. The page shares one list across
    /// platforms, so 1.0.914.1 leads although the Mac was still on 1.0.910.1.
    @Test func readsEveryEntryWithAndWithoutTheVPrefix() throws {
        #expect(try changelog().entries.map(\.version)
            == ["1.0.914.1", "1.0.910.1", "1.0.713.3", "1.0.626.1", "1.0.624.1"])
    }

    /// The date line only exists on the older entries, and when it does it is the
    /// date, not the first note.
    @Test func takesTheDateLineWhereThereIsOne() throws {
        let entries = try changelog().entries
        #expect(entries.map(\.date) == [nil, nil, nil, "June 26, 2026", "June 24, 2026"])
        let dated = try #require(entries.first { $0.version == "1.0.626.1" })
        #expect(dated.items == [
            "Fixed an issue where the profile area and buttons overlapped in the vertical tab sidebar.",
            "Fixed installed extensions being cut off when there are many extensions. The list is now scrollable.",
        ])
    }

    /// `### Aside is now officially available on Windows!` has nothing under it;
    /// as a heading it still renders, and it is never counted as a note.
    @Test func sectionsRenderAsHeadingsBetweenTheNotes() throws {
        let newest = try #require(try changelog().entries.first)
        #expect(newest.items.count == 14)
        #expect(Array(newest.content.prefix(3)) == [
            .heading("Aside is now officially available on Windows!"),
            .heading("Improved Agent Tabs"),
            .note("Selecting an agent tab now lets you use it as a regular page without pressing "
                + "Take over. Automatically taken-over tabs return to Agent Tabs when you switch away."),
        ])
        #expect(!newest.items.contains { $0.hasPrefix("#") })
    }

    /// Some entries say what changed in a paragraph rather than a bullet; those
    /// are the notes. Fence markers are not.
    @Test func paragraphsAreNotesAndFenceMarkersAreNot() throws {
        let entry = try #require(try changelog().entries.first { $0.version == "1.0.713.3" })
        #expect(entry.items == [
            "You can now switch profiles inside a single window.",
            "In vertical tabs, swipe left/right on a macOS trackpad to smoothly switch profiles.",
            "In horizontal tabs, click the profile icon to switch to another profile.",
            "We added a hidden option to remove background transparency at the system level.",
            "Disable window background vibrancy:",
            "defaults write at.studio.AsideBrowser windowBackgroundVibrancyDisabled -bool true",
        ])
    }

    @Test func inlineCodeLosesItsBackticks() throws {
        let entry = try #require(try changelog().entries.first { $0.version == "1.0.910.1" })
        #expect(entry.items == ["Updated Chromium to 152.0.7977.83."])
    }
}
