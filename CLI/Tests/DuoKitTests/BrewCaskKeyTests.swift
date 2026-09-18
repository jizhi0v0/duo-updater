import Foundation
import Testing
import DuoUpdaterCore
@testable import DuoKit

/// The second half of #743: the Homebrew cross-check was blind on the KEY, not
/// on the direction.
///
/// `brewComplaint` fired correctly for WorkBuddy's international pair and said
/// nothing at all for the Chinese one — not for want of a cask. `workbuddy-cn`
/// existed and had been right the whole time (5.5.6 against the 5.3.14 our
/// frozen probe kept reporting); it quits `com.tencent.workbuddy.mac` while our
/// recipe is keyed `com.workbuddy.workbuddy`, so the bundle-id index simply had
/// no such app. The miss looks exactly like "no cask exists" — both of that
/// family's app audits recorded `无 cask`.
@Suite struct BrewCaskKeyTests {

    @Test func theFallbackFilenameIsTheBundleIdsLastComponent() {
        #expect(Verify.caskAppFilename(forBundleID: "com.workbuddy.workbuddy") == "workbuddy.app")
        #expect(Verify.caskAppFilename(forBundleID: "md.obsidian") == "obsidian.app")
        // The catalog's filename index is case-folded, so this reaches the real
        // `WorkBuddy.app` / `Obsidian.app` artifacts.
        #expect(Verify.caskAppFilename(forBundleID: "") == nil)
    }

    /// A last component that qualifies the app instead of naming it is no key at
    /// all. 52 of the 228 cross-checked bundle ids end this way, across ten stems,
    /// and the only reason none of them resolves today is that no cask happens to
    /// ship an artifact called `App.app` — not a property to rest a filed issue on.
    ///
    /// Every id below is a real one from the two registries, at least one per
    /// stem, and that is the point: five of the ten stems (`app`, `desktop`,
    /// `mac`, `macos`, `client`) are hand-written with no `ReleaseChannel` behind
    /// them, and `macos` is carried by a single id — the shape somebody trims as
    /// dead weight. Trimming a stem fails here, by name, instead of quietly
    /// putting Raycast back on the `macos.app` key.
    ///
    /// `client`'s two ids are both listed rather than one standing for the stem,
    /// because that is the entry whose count is easiest to misread.
    @Test func aQualifierIsNotAName() {
        for bundleID in ["bot.cline.app",                   // app      ×16
                         "ai.opencode.desktop",             // desktop  ×16
                         "com.google.Chrome.beta",          // beta     ×5
                         "com.microsoft.onenote.mac",       // mac      ×5
                         "org.mozilla.nightly",             // nightly  ×3
                         "com.google.Chrome.dev",           // dev      ×2
                         "com.spotify.client",              // client   ×2
                         "com.windscribe.client",           //   …both listed
                         "com.google.Chrome.canary",        // canary   ×1
                         "com.raycast.macos",               // macos    ×1
                         "com.longbridge.app.desktop.preview"] {  // preview ×1
            #expect(Verify.caskAppFilename(forBundleID: bundleID) == nil,
                    "\(bundleID) derives a qualifier, not an app name")
        }
        // Every channel comes from `ReleaseChannel` rather than a hand-copy, so
        // one added there cannot quietly become a cask key. Both sides are folded:
        // `guineaPig`'s raw value is camel-cased and slipped through until they
        // were.
        for channel in ReleaseChannel.allCases {
            #expect(Verify.caskAppFilename(forBundleID: "com.example.app.\(channel.rawValue)") == nil)
        }
        // …and a real name still passes, including one that merely contains a
        // qualifier.
        #expect(Verify.caskAppFilename(forBundleID: "com.tinycast.tinycast") == "tinycast.app")
        #expect(Verify.caskAppFilename(forBundleID: "com.foo.appflowy") == "appflowy.app")
    }

    /// The ids pinned above have to stay real, or the guard they protect can be
    /// removed without the test noticing. Vacuity guard for the list, not a
    /// second copy of it.
    @Test func thePinnedQualifierIdsAreStillInTheRegistries() {
        var ids: Set<String> = []
        for recipe in VendorProbeRegistry.recipes { ids.insert(recipe.bundleID) }
        for rule in GitHubReleaseRegistry.rules { ids.insert(rule.bundleID) }
        for bundleID in ["com.raycast.macos", "com.spotify.client",
                         "com.windscribe.client", "com.microsoft.onenote.mac",
                         "bot.cline.app", "ai.opencode.desktop"] {
            #expect(ids.contains(bundleID), Comment(rawValue:
                "\(bundleID) is no longer in either cross-checked registry — re-pick "
                    + "a live id for its stem rather than dropping it"))
        }
    }

    @Test func aFilenameTwoAppsShareIdentifiesNeither() {
        func facts(_ tokens: [String]) -> [CaskFacts] {
            tokens.map { CaskFacts(token: $0, version: "1.0", autoUpdates: false,
                                   matchedByAppFilename: true) }
        }
        // One cask and its own channel siblings — GIMP's and Emacs's real sets.
        #expect(Verify.unambiguousCasks(facts(["gimp", "gimp@dev"])).count == 2)
        #expect(Verify.unambiguousCasks(
            facts(["emacs-app", "emacs-app@nightly", "emacs-app@pretest"])).count == 3)
        // `Telegram.app` is installed by two unrelated casks on unrelated
        // numbering (`telegram` 12.10, `telegram-desktop` 7.2.9). Picking either
        // would accuse the other's recipe of being five majors behind.
        #expect(Verify.unambiguousCasks(
            facts(["telegram", "telegram-desktop", "telegram-desktop@beta"])).isEmpty)
    }

    /// The complaint the CN pair should have been raising all along, and the note
    /// that keeps a guessed key from reading as a declared one.
    @Test func aFilenameMatchedCaskComplainsAndSaysSo() async throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.workbuddy.workbuddy"
        })
        let complaint = try #require(await Verify.brewComplaint(
            for: recipe, version: "5.3.14",
            casks: { _ in [CaskFacts(token: "workbuddy-cn", version: "5.5.6.38337834-5f969292",
                                     autoUpdates: false, matchedByAppFilename: true)] }))
        #expect(complaint.contains("`workbuddy-cn`"))
        #expect(complaint.contains("matched on the app filename"))
        // The note must not claim the cask declares a COMPETING id: the catalog's
        // bundle-id index is built only from `uninstall: quit:`, and a cask with
        // an `app` artifact and no `uninstall` stanza is the ordinary shape — 36
        // of the 39 casks this fallback reaches declare no quit id at all. The
        // branch knows only that the cask does not claim our id, and sending a
        // reader to compare against a stanza that may not exist is a wrong
        // instruction on a warning that reaches a filed issue.
        #expect(!complaint.contains("declares a different"))
        #expect(complaint.contains("does not declare that bundle id"))
        // A cask reached by the bundle id carries no such caveat.
        let declared = try #require(await Verify.brewComplaint(
            for: recipe, version: "5.3.14",
            casks: { _ in [CaskFacts(token: "workbuddy-cn", version: "5.5.6.38337834",
                                     autoUpdates: false)] }))
        #expect(!declared.contains("matched on the app filename"))

        // The phantom direction rests on the same cask, so it carries the same
        // caveat — it accuses the recipe of being too NEW, which is the reading a
        // guessed key gets wrong most expensively.
        let published = Date(timeIntervalSince1970: 1_786_000_000)
        let phantom = try #require(await Verify.brewComplaint(
            for: recipe, version: "5.9.0", publishedAt: published,
            now: published.addingTimeInterval(TimeInterval(Verify.brewPickupDays) * 86_400),
            casks: { _ in [CaskFacts(token: "workbuddy-cn", version: "5.5.6.38337834",
                                     autoUpdates: false, matchedByAppFilename: true)] }))
        #expect(phantom.contains("STILL at"))
        #expect(phantom.contains("matched on the app filename"))
    }

    /// Brew's `version,build` and `version+revision` spellings put a suffix in the
    /// second component, which a bare two-component split reads as newer — so an
    /// identical version complained. The upstream direction had never hit this
    /// because every cask spelling versions that way was behind a key it could
    /// not resolve; the filename fallback puts several of them in reach.
    @Test func brewsBuildSuffixIsNotAWholeReleaseAhead() async throws {
        let recipe = try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "net.librewolf.librewolf"
        })
        #expect(await Verify.brewComplaint(
            for: recipe, version: "156.0",
            casks: { _ in [CaskFacts(token: "librewolf", version: "156.0,1",
                                     autoUpdates: false, matchedByAppFilename: true)] }) == nil)
        // …and a genuine release ahead still reports.
        #expect(await Verify.brewComplaint(
            for: recipe, version: "156.0",
            casks: { _ in [CaskFacts(token: "librewolf", version: "157.0,1",
                                     autoUpdates: false, matchedByAppFilename: true)] }) != nil)
    }
}
