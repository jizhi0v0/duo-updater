import Testing
import Foundation
@testable import DuoUpdaterCore

/// super.engineering (`com.zarifpour.superconductor`): versions that are commit
/// hashes, ordered by the vendor's own release history (`BuildLineage`).
///
/// Both bodies are the vendor's, verbatim: `latest.json` whole, and the first six
/// releases of `changelog.json` (which ran to 627), both fetched 2026-09-10. What
/// the installed bundle reports was read off that day's real build, mounted from
/// the dmg `latest.json` names: `CFBundleShortVersionString` and `CFBundleVersion`
/// are both `8545a7d8`.
///
/// The pairs the evaluation tests use were picked because `VersionComparator` gets
/// them WRONG — each test first asserts that, so it cannot pass against an engine
/// that ignores the lineage. `c437b979` was `latest.json`'s build on 2026-09-07.
struct SuperconductorTests {

    static let bundleID = "com.zarifpour.superconductor"

    static let latestBody = #"""
        {
          "nightly": {
            "sha": "8545a7d83ced2ee07202688ebbb95bda8b3958a4",
            "url": "https://releases.superconductor.so/nightly/Superconductor-nightly-8545a7d8-arm64.dmg",
            "sha256": "8b8b408598e343e4e94da170d24ccd90fa45a7008485f114eee7c60cc1489ed7",
            "date": "2026-09-10"
          }
        }
        """#

    static let changelogBody = #"""
        {
          "releases": [
            {
              "version": "8545a7d83ced2ee07202688ebbb95bda8b3958a4",
              "date": "2026-09-10",
              "groups": [
                {
                  "title": "Features",
                  "commits": [
                    {
                      "message": "Allow Claude profiles to use settings API keys",
                      "pr": 2214
                    },
                    {
                      "message": "The app now supports a consistent interactive approval and question experience for more chat providers, including async prompt responses.",
                      "pr": 2217
                    },
                    {
                      "message": "Routing settings now let you choose providers, profiles, models, and thinking levels for session defaults and individual actions, with Global, Workspace, and Project overrides.",
                      "pr": 2216
                    }
                  ]
                },
                {
                  "title": "Bug Fixes",
                  "commits": [
                    {
                      "message": "Sidebar sections now expand and collapse reliably when activity updates are pending and the pointer remains over the sidebar.",
                      "pr": 2205
                    },
                    {
                      "message": "Video files like MP4, MKV, and MOV now open in your system media player instead of taking over workspace preview tabs.",
                      "pr": 2213
                    },
                    {
                      "message": "You can open pull request review comments from previous diffs even when their file context is no longer in the current view.",
                      "pr": 2215
                    },
                    {
                      "message": "Structured tool questions now keep multi-select choices and custom text isolated at the provider boundary for more reliable responses.",
                      "pr": 2217
                    },
                    {
                      "message": "Opening Select models in Agents settings without changing a selection no longer marks the setting as modified.",
                      "pr": 2216
                    },
                    {
                      "message": "`sc chat list` now clearly marks parked chat sessions so you can distinguish them from other inactive rows.",
                      "pr": 2219
                    },
                    {
                      "message": "Settings search navigation now redraws the destination section at its scrolled position.",
                      "pr": 2218
                    }
                  ]
                },
                {
                  "title": "Performance",
                  "commits": [
                    {
                      "message": "Settings pages avoid repeated layout work when scrolling long lists.",
                      "pr": 2216
                    },
                    {
                      "message": "Numeric inputs avoid unnecessary redraws when their values and configuration are unchanged.",
                      "pr": 2218
                    }
                  ]
                },
                {
                  "title": "Improvements",
                  "commits": [
                    {
                      "message": "Interactive provider-specific question flows now use dedicated handling paths instead of generic chat-only fallback behavior.",
                      "pr": 2217
                    },
                    {
                      "message": "Routing settings offer searchable pickers, keyboard navigation, inheritance guidance, Undo, and compact click-behavior controls in a responsive layout.",
                      "pr": 2216
                    },
                    {
                      "message": "Agents settings focus on provider availability, model visibility, and advanced setup; branch naming rules now live in Prompts, and Profiles shows where each profile is used.",
                      "pr": 2216
                    },
                    {
                      "message": "You can now scope chat listings to a specific worktree with `sc chat list --worktree PATH` without triggering chat restoration.",
                      "pr": 2219
                    }
                  ]
                }
              ]
            },
            {
              "version": "19d32d9a7d16fc3ccaaa7cfe606b45b90a257b13",
              "date": "2026-09-09",
              "groups": [
                {
                  "title": "Improvements",
                  "commits": [
                    {
                      "message": "Sidebar projects now expand and collapse immediately when clicked during activity updates.",
                      "pr": 2211
                    },
                    {
                      "message": "Sidebar project expand/collapse animations transition smoothly and reverse smoothly when clicked again.",
                      "pr": 2211
                    }
                  ]
                }
              ]
            },
            {
              "version": "fc41dde9c614f5b47b8309b8c900390f93f7c050",
              "date": "2026-09-09",
              "groups": [
                {
                  "title": "Features",
                  "commits": [
                    {
                      "message": "You can now exclude paths from worktree indexing and raise the indexing limits with a worktree_scan block in the settings file (exclusions, max_files, max_directories).",
                      "pr": 2182
                    },
                    {
                      "message": "Keep parked chats addressable after parking",
                      "pr": 2194
                    }
                  ]
                },
                {
                  "title": "Bug Fixes",
                  "commits": [
                    {
                      "message": "Markdown previews now update their text color when switching between dark and light mode.",
                      "pr": 2195
                    },
                    {
                      "message": "Scrolling up while a response streams no longer snaps the chat back to the bottom.",
                      "pr": 2196
                    },
                    {
                      "message": "Opening a workspace or chat rooted at a very large folder, such as your home directory, no longer causes memory to climb into the multi-gigabyte range or the app to become unresponsive.",
                      "pr": 2182
                    },
                    {
                      "message": "Command palette file search now finds files in projects whose stored path differs from the on-disk path in letter case or through a symlink, instead of reporting no matching files.",
                      "pr": 2182
                    },
                    {
                      "message": "Directories you expand in the Files tab stay expanded after the worktree rescans.",
                      "pr": 2182
                    },
                    {
                      "message": "The right panel rerun action now reruns the script shown in the active tab, including shared-group run tabs.",
                      "pr": 2197
                    },
                    {
                      "message": "Working spinners remain visible when switching back to a workspace, including repeated switches through other workspaces.",
                      "pr": 2202
                    },
                    {
                      "message": "Run-output previews no longer show main-pane content through them.",
                      "pr": 2203
                    }
                  ]
                },
                {
                  "title": "Performance",
                  "commits": [
                    {
                      "message": "File-system activity inside ignored or unindexed folders, such as build output and caches, no longer triggers repeated full worktree rescans.",
                      "pr": 2182
                    },
                    {
                      "message": "Sending a chat message while at the bottom now scrolls the new message into view.",
                      "pr": 2196
                    },
                    {
                      "message": "The managed sc watch command respects Git ignore rules, reducing work from ignored dependency and build folders while preserving tracked-file updates. Worktrees with incomplete native coverage use periodic reconciliation.",
                      "pr": 2198
                    },
                    {
                      "message": "Long chat-history refreshes run more efficiently and skip unnecessary work during live turns, reducing pauses in terminal output and app interaction.",
                      "pr": 2199
                    },
                    {
                      "message": "Workspace swipes are smoother and use less CPU by reusing sidebar content and avoiding unnecessary repository refreshes when returning to a workspace.",
                      "pr": 2141
                    },
                    {
                      "message": "Reduced UI stalls during startup and auto-hiding sidebar collapse while Git repositories refresh in the background.",
                      "pr": 2141
                    },
                    {
                      "message": "Terminal chat repaints now adapt to each terminal's rendering cost, with a 16 ms minimum interval to reduce excessive redraws during streaming.",
                      "pr": 2178
                    },
                    {
                      "message": "Inactive workspaces release persisted terminal preview grids from memory after 15 minutes and reload them when reopened, while retaining workspace state and recent chat content.",
                      "pr": 2178
                    },
                    {
                      "message": "Completing or cancelling long chat turns now avoids reprocessing unchanged transcript rows, reducing terminal display synchronization latency.",
                      "pr": 2159
                    },
                    {
                      "message": "Completed terminal tabs now release unused scrollback storage while preserving their visible output and history.",
                      "pr": 2206
                    }
                  ]
                },
                {
                  "title": "Improvements",
                  "commits": [
                    {
                      "message": "Commit titles in the change list now reveal the full message in a tooltip when hovered.",
                      "pr": 2193
                    },
                    {
                      "message": "Sidebar text and icons keep their proportions while resizing the window.",
                      "pr": 2201
                    },
                    {
                      "message": "Shared context previews preserve header height and consistent add-button spacing.",
                      "pr": 2200
                    },
                    {
                      "message": "Worktrees transition smoothly between sidebar sections when pinned, unpinned, or moved by run-state changes, including moves to and from collapsed project rows.",
                      "pr": 2204
                    },
                    {
                      "message": "Cost and usage counters continue their animations through rapid workspace switches, and animated diff counts preserve their current positions when values change mid-animation.",
                      "pr": 2210
                    },
                    {
                      "message": "Command palette file search now says the index is incomplete for folders that exceed the file scan limit, instead of reporting no matching files.",
                      "pr": 2182
                    },
                    {
                      "message": "Sidebar rows appear together at startup instead of animating into view one by one.",
                      "pr": 2141
                    },
                    {
                      "message": "The Run/Stop button animates smoothly between running and inactive states when switching workspaces.",
                      "pr": 2141
                    },
                    {
                      "message": "Enhance Prompt notifications identify completed or failed enhancements, with a compact queue label that preserves the chat title and worktree context.",
                      "pr": 2208
                    }
                  ]
                }
              ]
            },
            {
              "version": "c437b97920667df95c1f1d4ba5775a8412d04824",
              "date": "2026-09-07",
              "groups": [
                {
                  "title": "Improvements",
                  "commits": [
                    {
                      "message": "Add heartbeat timing context to hang diagnostics",
                      "pr": 2192
                    }
                  ]
                }
              ]
            },
            {
              "version": "1f68f34a9fbcd4179b802d4cf23b63d45b7f1ca8",
              "date": "2026-09-03",
              "groups": [
                {
                  "title": "Bug Fixes",
                  "commits": [
                    {
                      "message": "Oh My Pi models such as Claude Fable 5.1 now show their advertised reasoning-effort options across supported thinking modes.",
                      "pr": 2190
                    }
                  ]
                }
              ]
            },
            {
              "version": "5b73c7f492d42b3e97e4f25c19686d545c037826",
              "date": "2026-09-03",
              "groups": [
                {
                  "title": "Features",
                  "commits": [
                    {
                      "message": "GPT-6 Astra is now available in Codex model selection and AI routing, including Max reasoning and Fast mode support.",
                      "pr": 2189
                    }
                  ]
                },
                {
                  "title": "Improvements",
                  "commits": [
                    {
                      "message": "Chat mid-turn steered messages can now be selected and copied, and their indicator remains readable on short message bubbles.",
                      "pr": 2188
                    }
                  ]
                }
              ]
            }
          ]
        }
        """#

    static let installedBuild = "8545a7d8"
    static let historyHead = ["8545a7d8", "19d32d9a", "fc41dde9", "c437b979", "1f68f34a", "5b73c7f4"]

    static func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
    }

    static func lineage() throws -> BuildLineage {
        let spec = try #require(try recipe().buildLineage)
        return try #require(BuildLineage.extract(from: changelogBody, pattern: spec.entryPattern))
    }

    /// An installed copy on `build`, at a path that does not exist.
    static func app(_ build: String) -> InstalledApp {
        let path = "/Applications/ZZFixture-super.engineering.app"
        #expect(!FileManager.default.fileExists(atPath: path))
        return InstalledApp(
            name: "super.engineering", bundleID: bundleID,
            shortVersion: build, buildVersion: build,
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
    }

    /// Built the way the probe builds it, so a remote here carries exactly what a
    /// production one would.
    static func remote(_ build: String, lineage: BuildLineage?) throws -> RemoteVersion {
        VendorProbeSource.makeRemoteVersion(
            recipe: try recipe(), version: build, install: nil, plan: nil,
            resolvedDownload: nil, lineage: lineage)
    }

    // MARK: - What the recipe reads

    @Test func theVersionIsExactlyWhatTheBundleReports() throws {
        // Eight digits, not forty: the full hash never equals the bundle's string
        // and would read as an update forever.
        #expect(VendorProbeRecipe.extractVersion(
            from: Self.latestBody, pattern: try Self.recipe().versionPattern) == Self.installedBuild)
    }

    @Test func theInstallIsTheManifestsArm64DMG() throws {
        let install = try #require(try Self.recipe().install)
        guard case .bodyPattern(let pattern) = install.urlSource else {
            Issue.record("expected a .bodyPattern install URL")
            return
        }
        #expect(VendorProbeRecipe.extractVersion(from: Self.latestBody, pattern: pattern)
            == "https://releases.superconductor.so/nightly/Superconductor-nightly-8545a7d8-arm64.dmg")
        #expect(install.kind == .dmg)
    }

    @Test func thePublishDayIsTheManifestsDate() throws {
        let pattern = try #require(try Self.recipe().publishedAtPattern)
        #expect(VendorProbeRecipe.extractVersion(from: Self.latestBody, pattern: pattern) == "2026-09-10")
    }

    /// Every pattern reads inside the manifest's `"nightly"` object. The updater
    /// looks its entry up by channel name, so a second track would arrive as a
    /// sibling key — listed FIRST here, which is where first-match would take it.
    /// The stable entry is invented (the manifest has carried only `nightly` since
    /// the vendor retired stable); this pins the anchoring, not what a stable entry
    /// would look like.
    @Test func everyPatternReadsTheNightlyEntryOnly() throws {
        let recipe = try Self.recipe()
        let twoTracks = #"""
            {
              "stable": {
                "sha": "0123456789abcdef0123456789abcdef01234567",
                "url": "https://releases.superconductor.so/stable/Superconductor-stable-01234567-arm64.dmg",
                "sha256": "00",
                "date": "2026-01-01"
              },
              "nightly": {
                "sha": "8545a7d83ced2ee07202688ebbb95bda8b3958a4",
                "url": "https://releases.superconductor.so/nightly/Superconductor-nightly-8545a7d8-arm64.dmg",
                "sha256": "8b8b408598e343e4e94da170d24ccd90fa45a7008485f114eee7c60cc1489ed7",
                "date": "2026-09-10"
              }
            }
            """#
        #expect(VendorProbeRecipe.extractVersion(from: twoTracks, pattern: recipe.versionPattern)
            == "8545a7d8")
        #expect(VendorProbeRecipe.extractVersion(
            from: twoTracks, pattern: try #require(recipe.publishedAtPattern)) == "2026-09-10")
        guard case .bodyPattern(let pattern) = try #require(recipe.install).urlSource else {
            Issue.record("expected a .bodyPattern install URL")
            return
        }
        #expect(VendorProbeRecipe.extractVersion(from: twoTracks, pattern: pattern)
            == "https://releases.superconductor.so/nightly/Superconductor-nightly-8545a7d8-arm64.dmg")
    }

    @Test func theLineageIsTheHistoryNewestFirstInTheBundlesForm() throws {
        let lineage = try Self.lineage()
        #expect(lineage.newestFirst == Self.historyHead)
        // The manifest's build is the history's head — the probe refuses to answer
        // otherwise (`buildLineageMissesVersion`).
        #expect(lineage.position(of: Self.installedBuild) == 0)
    }

    /// The bundle itself carries no channel signal — `detect()` reads it as
    /// `.stable` — so it is the Settings choice that has to land on the recipe's
    /// channel, or the probe never applies at all. The binding is authoritative
    /// (`AppScanner` replaces `detect()` with it), which is what makes that work.
    @Test func theSettingsChoiceIsWhatSelectsTheRecipe() throws {
        let detected = ReleaseChannel.detect(
            name: "super.engineering", bundleID: Self.bundleID, keystoneChannel: nil,
            version: Self.installedBuild, bundleFileName: "super.engineering.app")
        #expect(detected == .stable)
        let recipe = try Self.recipe()
        #expect(recipe.channel == .nightly)
        #expect(SuperconductorChannel.resolve(updateChannel: "nightly").channel == recipe.channel)
        #expect(ChannelBinding.hasResolver(bundleID: Self.bundleID))
        #expect(ChannelBinding.boundBundleIDs.contains(Self.bundleID))
        #expect(ChannelBinding.vendorProbeBackedBindings.contains(Self.bundleID))
    }

    /// The one direction this must never get wrong: a copy set to anything but
    /// nightly is not offered the nightly build — and nothing but nightly has a
    /// recipe, so it is offered nothing.
    @Test func aCopyOnAnyOtherTrackIsNeverOfferedNightly() throws {
        let served = Set(VendorProbeRegistry.recipes
            .filter { $0.bundleID == Self.bundleID }.map(\.channel))
        #expect(served == [.nightly])
        for value in ["stable", "Stable", "beta", "release", "preview"] {
            let channel = SuperconductorChannel.resolve(updateChannel: value).channel
            #expect(channel != .nightly, "\(value)")
            #expect(!served.contains(channel), "\(value) would be served a recipe")
        }
        // No recorded choice is the app's own default — the only track there is.
        for absent in [nil, "", "  "] as [String?] {
            #expect(SuperconductorChannel.resolve(updateChannel: absent).channel == .nightly)
        }
        #expect(SuperconductorChannel.resolve(updateChannel: " Nightly ").channel == .nightly)
    }

    /// The file the app actually writes: a flat JSON object with the choice at the
    /// top level, among ninety-odd other settings.
    @Test func theResolverReadsTheSettingFromTheFileTheAppWrites() {
        #expect(SuperconductorChannel.settingsFileURL.path
            .hasSuffix("/.superconductor/settings.json"))
        func read(_ json: String) -> String? {
            SuperconductorChannel.updateChannel(inSettings: Data(json.utf8))
        }
        #expect(read(#"{"ai_routing": {"version": 2}, "update_channel": "nightly", "provider_update_checks": true}"#)
            == "nightly")
        #expect(read(#"{"provider_update_checks": true}"#) == nil)
        #expect(read(#"{"update_channel": null}"#) == nil)
        #expect(read("not json") == nil)
        // A nested key of the same name is some other setting.
        #expect(read(#"{"ai_routing": {"update_channel": "stable"}}"#) == nil)
        // A present value we cannot read as a word is still a choice, and not nightly.
        let odd = read(#"{"update_channel": 2}"#)
        #expect(odd != nil)
        #expect(SuperconductorChannel.resolve(updateChannel: odd).channel != .nightly)
    }

    // MARK: - Ordering

    /// Pins the equality path, which the lineage branch and the comparator both
    /// answer the same way — no lineage mutation turns this red, and none should.
    @Test func theSameBuildIsUpToDate() throws {
        let status = UpdateChecker.evaluate(
            installed: Self.app("8545a7d8"),
            remote: try Self.remote("8545a7d8", lineage: try Self.lineage()))
        #expect(status == .upToDate)
    }

    @Test func anOlderCopyIsOfferedTheUpdateTheComparatorWouldMiss() throws {
        let installed = Self.app("1f68f34a"), older = "1f68f34a", newer = "c437b979"
        // The trap: by digit runs, "c437…" (text) sorts below "1f68…" (number).
        #expect(!VersionComparator.isNewer(newer, than: older))
        #expect(UpdateChecker.evaluate(
            installed: installed, remote: try Self.remote(newer, lineage: nil)) == .upToDate)

        #expect(UpdateChecker.evaluate(
            installed: installed, remote: try Self.remote(newer, lineage: try Self.lineage()))
            == .updateAvailable(latest: newer))
    }

    @Test func aNewerCopyIsNeverOfferedAnOlderBuild() throws {
        let installed = Self.app("c437b979"), older = "1f68f34a"
        #expect(VersionComparator.isNewer(older, than: "c437b979"))
        #expect(UpdateChecker.evaluate(
            installed: installed, remote: try Self.remote(older, lineage: nil))
            == .updateAvailable(latest: older))

        #expect(UpdateChecker.evaluate(
            installed: installed, remote: try Self.remote(older, lineage: try Self.lineage()))
            == .upToDate)
    }

    /// A failed check, not `.unknown`: `.unknown` renders as "no source covers
    /// this app", which is false for an app whose source just answered.
    @Test func aBuildTheLineageCannotPlaceIsAFailedCheck() throws {
        let lineage = try Self.lineage()
        func failed(_ status: UpdateStatus) -> Bool {
            if case .error = status { return true }
            return false
        }
        // An installed build the history does not list (a copy that updated itself
        // past this lineage, or one trimmed from it) …
        #expect(failed(UpdateChecker.evaluate(
            installed: Self.app("0badc0de"), remote: try Self.remote("8545a7d8", lineage: lineage))))
        // … and a remote it does not list.
        #expect(failed(UpdateChecker.evaluate(
            installed: Self.app("8545a7d8"), remote: try Self.remote("0badc0de", lineage: lineage))))
    }

    @Test func theDowngradeNoteTrustsOnlyTheLineage() throws {
        let lineage = try Self.lineage()
        func note(installed: String, remote: String, lineage: BuildLineage?) throws -> String? {
            UpdatePolicy.laggingRemoteVersion(UpdateResult(
                app: Self.app(installed), remote: try Self.remote(remote, lineage: lineage),
                status: .upToDate))
        }
        // "5b73…" is OLDER than "1f68…", but 5 > 1 by digit runs.
        #expect(VersionComparator.isNewer("5b73c7f4", than: "1f68f34a"))
        #expect(try note(installed: "5b73c7f4", remote: "1f68f34a", lineage: nil) == "1f68f34a")
        #expect(try note(installed: "5b73c7f4", remote: "1f68f34a", lineage: lineage) == nil)
        // A copy really ahead of a stale answer still gets its note.
        #expect(try note(installed: "8545a7d8", remote: "c437b979", lineage: lineage) == "c437b979")
    }

    @Test func verifyReportsBehindOnlyWhereTheLineageSaysSo() throws {
        let lineage = try Self.lineage()
        func complaint(installed: String, remote: String, lineage: BuildLineage?) throws -> String? {
            RecipeSanity.remoteBehindInstalled(
                remote: try Self.remote(remote, lineage: lineage),
                installedMarketing: installed, installedBuild: installed)
        }
        #expect(try complaint(installed: "5b73c7f4", remote: "1f68f34a", lineage: nil) != nil)
        #expect(try complaint(installed: "5b73c7f4", remote: "1f68f34a", lineage: lineage) == nil)
        #expect(try complaint(installed: "8545a7d8", remote: "c437b979", lineage: lineage) != nil)
    }

    /// The pre-install re-check on a copy that updated itself PAST the offer
    /// between the click and the re-check. Digit runs read that as the source
    /// walking backwards; the lineage reads it as what it is.
    @Test func aCopyThatOvertookTheOfferIsAlreadyCurrentNotARegression() throws {
        let lineage = try Self.lineage()
        // Offered "5b73…"; the copy is now on the newer "1f68…", which the re-check
        // names too. By digit runs 5 > 1, so the offer looks like the newer one.
        #expect(VersionComparator.isNewer("5b73c7f4", than: "1f68f34a"))
        func decision(
            offered: String, confirmed: String, lineage: BuildLineage?
        ) throws -> PreInstallDecision {
            // The gate reads only the two remotes and the re-check's status; the
            // apps are the copy as it was at the click and as it is now.
            PreInstallGate.decision(
                offered: UpdateResult(
                    app: Self.app("0badc0de"), remote: try Self.remote(offered, lineage: lineage),
                    status: .updateAvailable(latest: offered)),
                confirmed: UpdateResult(
                    app: Self.app(confirmed), remote: try Self.remote(confirmed, lineage: lineage),
                    status: .upToDate))
        }
        #expect(try decision(offered: "5b73c7f4", confirmed: "1f68f34a", lineage: nil)
            == .answerRegressed)
        #expect(try decision(offered: "5b73c7f4", confirmed: "1f68f34a", lineage: lineage)
            == .alreadyCurrent)
        // A re-check that really did walk backwards still says so.
        #expect(try decision(offered: "1f68f34a", confirmed: "5b73c7f4", lineage: lineage)
            == .answerRegressed)
    }

    /// A hash can legitimately contain no digit at all (`deadbeef`); for a lineage
    /// recipe that is not a broken pattern.
    @Test func aDigitlessHashIsNotReportedAsABrokenVersion() throws {
        func saysNoDigits(_ recipe: VendorProbeRecipe) -> Bool {
            RecipeSanity.complaints(version: "deadbeef", recipe: recipe)
                .contains { $0.contains("no digits") }
        }
        #expect(!saysNoDigits(try Self.recipe()))
        let ordinary = try #require(VendorProbeRegistry.recipes.first { $0.buildLineage == nil })
        #expect(saysNoDigits(ordinary))
    }

    // MARK: - Derived from the registry

    /// A lineage recipe's remote must carry the lineage on EVERY branch the probe
    /// builds, or that branch silently falls back to the comparator.
    @Test func everyLineageRecipeCarriesItsLineageOnEveryBranch() throws {
        let lineageRecipes = VendorProbeRegistry.recipes.filter { $0.buildLineage != nil }
        #expect(!lineageRecipes.isEmpty)
        let lineage = BuildLineage(newestFirst: ["b", "a"])
        for recipe in lineageRecipes {
            #expect(recipe.buildLineage?.url.scheme == "https", "\(recipe.recipeID)")
            let detection = VendorProbeSource.makeRemoteVersion(
                recipe: recipe, version: "a", install: nil, plan: nil,
                resolvedDownload: nil, lineage: lineage)
            #expect(detection.buildLineage == lineage, "\(recipe.recipeID) detection-only")
            if let spec = recipe.install {
                let installable = VendorProbeSource.makeRemoteVersion(
                    recipe: recipe, version: "a", install: spec,
                    plan: (url: URL(string: "https://example.invalid/a.dmg")!, checksum: nil),
                    resolvedDownload: nil, lineage: lineage)
                #expect(installable.buildLineage == lineage, "\(recipe.recipeID) installable")
            }
            #expect(VendorProbeRegistry.ordersByLineage(recipeID: recipe.recipeID))
            #expect(VendorProbeRegistry.ordersByLineage(bundleID: recipe.bundleID))
        }
        let ordinary = try #require(VendorProbeRegistry.recipes.first { $0.buildLineage == nil })
        #expect(!VendorProbeRegistry.ordersByLineage(recipeID: ordinary.recipeID))
        #expect(!VendorProbeRegistry.ordersByLineage(bundleID: ordinary.bundleID))
    }

    // MARK: - Release notes

    @Test func theChangelogKeepsTheVendorsSectionsUnderTheBundlesVersion() throws {
        let changelog = try #require(StructuredChangelogDecoder.decode(
            Self.changelogBody, format: .superconductorChangelog, channel: nil, maxEntries: 20))
        #expect(changelog.entries.map(\.version) == Self.historyHead)
        #expect(changelog.entries[0].date == "2026-09-10")
        #expect(Array(changelog.entries[0].items.prefix(2))
            == ["Features", "Allow Claude profiles to use settings API keys"])
        #expect(changelog.entries[3].items
            == ["Improvements", "Add heartbeat timing context to hang diagnostics"])
    }

    @Test func emptyGroupsAndBlankCommitsAreDropped() throws {
        // The two shapes the history really carries: `d08315a7`'s `Features` group
        // has `commits: []`, and one of `880d2417`'s commits has `"message": ""`.
        let body = #"""
            {"releases": [{"version": "d08315a7de8a0a2bf8b5f6e2d6c6f2d0f6d6c6d6", "date": "2026-07-15",
              "groups": [{"title": "Features", "commits": []},
                         {"title": "Bug Fixes", "commits": [{"message": "", "pr": 1202},
                                                             {"message": "load session history for qwen", "pr": 1610}]}]},
                         {"version": "880d2417", "date": "2026-05-30",
              "groups": [{"title": "Bug Fixes", "commits": [{"message": "  ", "pr": null}]}]}]}
            """#
        let changelog = try #require(StructuredChangelogDecoder.decode(
            body, format: .superconductorChangelog, channel: nil, maxEntries: 20))
        #expect(changelog.entries.count == 1)
        #expect(changelog.entries[0].version == "d08315a7")
        #expect(changelog.entries[0].items == ["Bug Fixes", "load session history for qwen"])
    }

    @Test func theChangelogIsTheSameDocumentTheLineageReads() throws {
        let changelogRecipe = try #require(
            ChangelogRecipeRegistry.recipes.first { $0.bundleID == Self.bundleID })
        #expect(changelogRecipe.structuredFormat == .superconductorChangelog)
        #expect(changelogRecipe.source == (try Self.recipe().buildLineage?.url))
    }
}
