import Foundation
import Testing

@testable import DuoUpdaterCore

/// `www.snipaste.com/versions`, fetched 2026-10-16, verbatim.
private let snipasteVersionsBody = #"""
{"win_store_version":"2.11.3", "win_store_date":"2026.01.18","win_desktop_version":"2.11.3", "win_desktop_date":"2026.01.18","mac_version":"2.11.3", "mac_date":"2026.01.18","linux_version":"2.11.3", "linux_date":"2026.01.18"}
"""#

/// Three slices of `docs.snipaste.com/wiki/Changelog.md`, fetched 2026-10-16,
/// verbatim and in the file's order: the newest release, 2.10.4 (nested
/// bullets), and the two Linux beta headings that sit directly above the 2.8.8
/// release.
private let snipasteChangelogFixture = #"""
## v2.11.3
> 2026.01.18

* [PRO] Support customizing some in-app shortcuts (Preferences - Control - In-App Shortcuts) [#2189](https://github.com/Snipaste/feedback/issues/2189) [#3317](https://github.com/Snipaste/feedback/issues/3317) [#3584](https://github.com/Snipaste/feedback/issues/3584)
* [PRO] Text extraction: support Tencent and OCR.space APIs
* Other improvements and bug fixes [#3572](https://github.com/Snipaste/feedback/issues/3572) [#3579](https://github.com/Snipaste/feedback/issues/3579) [#3580](https://github.com/Snipaste/feedback/issues/3580) [#3597](https://github.com/Snipaste/feedback/issues/3597)

## v2.10.4
> 2025.01.17

* [PRO] Color picker can now display HSV and other color values
* [PRO] Support binding keyboard shortcuts to custom output commands
* New option: never show auxiliary lines
* Cleaner interface in whiteboard mode
* Write relevant metadata to screenshots for iCloud categorization
* When screen settings changes cause some pinned images to become invisible:
  * No longer automatically move off-screen pins back into view, to preserve layout when screen settings are restored
  * Added "Restore off-screen images" option to tray icon menu for manual recovery
* Fixed screen flicker issue when taking screenshots on some Linux environments [#3158](https://github.com/Snipaste/feedback/issues/3158)
* Fixed magnifier not refreshing in certain situations [#3145](https://github.com/Snipaste/feedback/issues/3145)
* Fixed toolbar not showing in certain situations
* Improved compatibility with dictionary apps
* Upgrade OpenSSL to 3.4.0 [#3190](https://github.com/Snipaste/feedback/issues/3190)
* Other improvements and bug fixes [#3153](https://github.com/Snipaste/feedback/issues/3153) [#3155](https://github.com/Snipaste/feedback/issues/3155)

## v2.8.9 Beta (Linux)
> 2024.01.08

* Able to take screenshots in any workspace [#2816](https://github.com/Snipaste/feedback/issues/2816)
* Fix misaligned screenshot for some multi-monitor setup [#2819](https://github.com/Snipaste/feedback/issues/2819)
* Option to launch on system startup [#2814](https://github.com/Snipaste/feedback/issues/2814)
* Able to move image windows off screen
* Other bug fixes

## v2.8.8 Beta (Linux)
> 2023.09.25

* First release for Linux

## v2.8.8
> 2023.09.25

* Fix unable to take screenshots properly for some multi-monitor setup
"""#

@Test func snipasteReadsTheMacVersionFromTheVersionsJSON() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.Snipaste" })
    #expect(recipe.channel == .stable)
    #expect(VendorProbeRecipe.extractVersion(
        from: snipasteVersionsBody, pattern: recipe.versionPattern) == "2.11.3")
    // Two-part releases exist (2.11, 2.10) and must read.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"mac_version":"2.11", "mac_date":"2025.12.08"}"#,
        pattern: recipe.versionPattern) == "2.11")
    // A suffixed value is not a stable version.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"mac_version":"2.12-Beta"}"#, pattern: recipe.versionPattern) == nil)
    // Another platform's field never stands in for the Mac one.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"win_desktop_version":"2.11.3"}"#, pattern: recipe.versionPattern) == nil)

    let spec = try #require(recipe.install)
    #expect(spec.kind == .dmg)
    guard case .versionTemplate(let template) = spec.urlSource
    else { Issue.record("expected a version template"); return }
    #expect(template == "https://download.snipaste.com/archives/Snipaste-{version}.dmg")
}

@Test func snipasteChangelogSkipsBetaHeadingsAndKeepsNestedItems() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.Snipaste", channel: .stable))
    let log = try #require(
        ChangelogExtractor.extract(from: snipasteChangelogFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["2.11.3", "2.10.4", "2.8.8"])
    #expect(log.entries.map(\.date) == ["2026.01.18", "2025.01.17", "2023.09.25"])
    #expect(log.entries[0].items.count == 3)
    #expect(log.entries[0].items[1] == "[PRO] Text extraction: support Tencent and OCR.space APIs")
    // 12 top-level bullets plus the two nested under one of them.
    #expect(log.entries[1].items.count == 14)
    #expect(log.entries[1].items.contains("Fixed toolbar not showing in certain situations"))
    // The Linux betas above 2.8.8 add nothing to it.
    #expect(log.entries[2].items == [
        "Fix unable to take screenshots properly for some multi-monitor setup",
    ])
}
