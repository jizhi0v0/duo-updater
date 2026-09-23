import Foundation
import Testing
import DuoUpdaterCore
@testable import DuoKit

/// The reverse of `changelogLagComplaint` — #743. `duo verify` cross-checked a
/// changelog against its probe in one direction only, so a probe that reads
/// wrong *consistently* was invisible: it never moves, and every history check
/// compares a row against its own previous value.
///
/// The fixture is the four apps that, on the committed baseline of 2026-09-18,
/// had a changelog row leading every probe row for the same bundle id — measured
/// by running this function over `verify/baseline.json`, not by approximating
/// it. Frozen here rather than re-read from the file, which moves every sweep.
/// Claude for Desktop's rows are the ones from `2095a06c`, the last baseline
/// where its GA endpoint had not yet caught up with the docs page; at HEAD they
/// are equal and the case stops exercising anything.
@Suite struct ChangelogLeadsProbeTests {

    /// bundle id → (changelog reading, probe rows by channel, is it a real bug)
    static let baselineCases: [(app: String, entry: String,
                                probes: [String: [String]], real: Bool)] = [
        // The bug: the CN pair sat frozen at 5.3.14 for weeks while the same
        // sweep's changelog row held 5.5.6, both written with one `lastGoodAt`.
        ("com.workbuddy.workbuddy", "5.5.6", ["stable": ["5.3.14", "5.3.14"]], true),
        // Two numbering namespaces on one channel: the GA redirect and the
        // Squirrel rollout endpoint are both `.stable`.
        ("com.anthropic.claudefordesktop", "2.2553.0",
         ["stable": ["2.110.1", "1.46388.3"]], false),
        // The insider builds share Obsidian's changelog with stable.
        ("md.obsidian", "1.14.2", ["stable": ["1.13.7"]], false),
        // One release spelled two ways.
        ("org.mozilla.thunderbirdbeta", "157.0beta", ["beta": ["157.0b2"]], false),
    ]

    func complaint(_ testCase: (app: String, entry: String,
                                probes: [String: [String]], real: Bool)) -> String? {
        let recipe = ChangelogRecipeRegistry.recipes.first { $0.bundleID == testCase.app }
        return Verify.changelogLeadsProbeComplaint(
            entry: testCase.entry, probeVersionsByChannel: testCase.probes,
            carriesOtherTrainEntries: recipe?.carriesOtherTrainEntries ?? false,
            ordersByLineage: VendorProbeRegistry.ordersByLineage(bundleID: testCase.app))
    }

    /// The issue's acceptance, verbatim: flag WorkBuddy and none of the other
    /// three. A naive reversal flags all four.
    @Test func flagsTheFrozenProbeAndNothingElse() throws {
        let flagged = Self.baselineCases.filter { complaint($0) != nil }.map(\.app)
        #expect(flagged == ["com.workbuddy.workbuddy"])
        let complaint = try #require(complaint(Self.baselineCases[0]))
        #expect(complaint.contains("5.5.6"))
        #expect(complaint.contains("5.3.14"))
    }

    /// Every one of the three false positives is excluded by a DIFFERENT
    /// discriminator, and nothing else is holding any of them back. Without this
    /// the suite above would keep passing if two of the three guards were deleted
    /// and the third happened to cover for them.
    @Test func eachDiscriminatorIsTheOnlyThingHoldingItsCaseBack() throws {
        // Namespace split: drop the second row and the same reading complains.
        let claude = Self.baselineCases[1]
        #expect(complaint(claude) == nil)
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: claude.entry, probeVersionsByChannel: ["stable": ["2.110.1"]]) != nil)

        // Another train's entries: the flag is what silences Obsidian.
        let obsidian = Self.baselineCases[2]
        #expect(complaint(obsidian) == nil)
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: obsidian.entry, probeVersionsByChannel: obsidian.probes,
            carriesOtherTrainEntries: false) != nil)
        #expect(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "md.obsidian" }?.carriesOtherTrainEntries == true)

        // Spelling: `157.0beta` and `157.0b2` are one release, and it is
        // `numericMajorMinor` doing that — `VersionComparator` orders the raw
        // pair as newer ("beta" > "b").
        #expect(complaint(Self.baselineCases[3]) == nil)
        #expect(VersionComparator.isNewer("157.0beta", than: "157.0b2"))
        #expect(Verify.numericMajorMinor("157.0beta")
            == Verify.numericMajorMinor("157.0b2"))
    }

    /// #790/#791: Windscribe's beta and guinea pig changelogs read the GitHub
    /// prereleases, and GitHub carries builds the vendor's own track feed never
    /// lists. On 2026-09-23 it topped out at `v2.25.1-alpha` (2026-09-21, ships a
    /// `_guinea_pig_universal.dmg`) while `ChangeLogs?platform=osx`,
    /// `ChangeLogs/summary` and `CheckUpdate?beta=0…3` all still answered 2.24.12
    /// on every one of 10 requests each — and of the 29 releases just below it, 13
    /// never reached any vendor track at all (2.24.13, 2.24.11, 2.24.9, …).
    @Test func windscribePrereleaseChangelogsCarryBuildsNoTrackOffers() throws {
        let probes = ["stable": ["2.24.12"], "beta": ["2.24.12"], "guineaPig": ["2.24.12"]]
        let recipes = ChangelogRecipeRegistry.recipes
            .filter { $0.bundleID == "com.windscribe.client" }
        let prerelease = recipes.filter { $0.channel == .beta || $0.channel == .guineaPig }
        #expect(prerelease.count == 2)
        for recipe in prerelease {
            #expect(Verify.changelogLeadsProbeComplaint(
                entry: "2.25.1", probeVersionsByChannel: probes,
                carriesOtherTrainEntries: recipe.carriesOtherTrainEntries) == nil)
        }
        // The flag is the only thing holding it back: the same reading complains
        // without it…
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "2.25.1", probeVersionsByChannel: probes) != nil)
        // …and the stable recipe, which `.gitHubReleases` filters to
        // `prerelease: false`, keeps the frozen-probe check.
        let stable = try #require(recipes.first { $0.channel == .stable })
        #expect(!stable.carriesOtherTrainEntries)
    }

    @Test func aMultiChannelAppIsNotItsOwnDisagreement() {
        // Thunderbird's stable and ESR trains share `org.mozilla.thunderbird`.
        // Comparing either changelog against an arbitrary row reads the other
        // train as a lead; against EVERY row, neither is.
        let rows = ["stable": ["156.0"], "esr": ["140.16.0esr"]]
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "156.0", probeVersionsByChannel: rows) == nil)
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "140.16.0esr", probeVersionsByChannel: rows) == nil)
        // …and a lead over both still reports.
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "157.0", probeVersionsByChannel: rows) != nil)
    }

    @Test func nothingToCompareAgainstIsNotAComplaint() {
        // No probe ran (`duo verify --changelog`), or it broke and read nothing.
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "5.5.6", probeVersionsByChannel: [:]) == nil)
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "5.5.6", probeVersionsByChannel: ["stable": []]) == nil)
        // A headline captured into `version` — Figma and Notion both do this —
        // compares as confident nonsense, on either side.
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "AI credit user limits", probeVersionsByChannel: ["stable": ["5.3.14"]]) == nil)
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "5.5.6", probeVersionsByChannel: ["stable": ["nightly-2026-09-18"]]) == nil)
        // Hash builds have no order a version string can show.
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "5.5.6", probeVersionsByChannel: ["stable": ["5.3.14"]],
            ordersByLineage: true) == nil)
    }

    /// Codex numbers both its builds and its notes `YY.MDD`, which puts the date
    /// in the slot a major.minor comparison reads — so a note published for a
    /// build the probe has not seen yet reads as a whole release ahead. Same
    /// yardstick as the lag direction: days, with `staleNotesDays` of tolerance.
    @Test func aDateNumberedSchemeIsMeasuredInDays() {
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "26.910", probeVersionsByChannel: ["stable": ["26.803.41515"]]) == nil)
        #expect(Verify.changelogLeadsProbeComplaint(
            entry: "26.910", probeVersionsByChannel: ["stable": ["26.115.41515"]]) != nil)
    }

    @Test func majorMinorDropsEverythingThatIsNotADigit() {
        #expect(Verify.numericMajorMinor("5.5.6") == "5.5")
        #expect(Verify.numericMajorMinor("140.16.0esr") == "140.16")
        #expect(Verify.numericMajorMinor("157.0b2") == "157.0")
        // Homebrew's `version,build` and `version_revision` spellings.
        #expect(Verify.numericMajorMinor("156.0,1") == "156.0")
        #expect(Verify.numericMajorMinor("3.22.3+105") == "3.22")
        #expect(Verify.numericMajorMinor("31") == "31")
    }

    @Test func onlyTheRegistriesThatReadAVersionAreCompared() {
        let findings = [
            finding("vendor:x:stable", .vendor, "x", "stable", .ok, "1.0"),
            finding("vendor:x:beta", .vendor, "x", "beta", .ok, "1.1"),
            finding("github:x:stable", .github, "x", "stable", .warn, "1.0"),
            // A network failure is not a reading.
            finding("vendor:x:esr", .vendor, "x", "esr", .infra, "0.1"),
            // Another app, and a registry that answers about something else.
            finding("vendor:y:stable", .vendor, "y", "stable", .ok, "9.9"),
            finding("appstore:x:-", .appStore, "x", "-", .ok, "8.8"),
        ]
        let grouped = Verify.probeVersionsByChannel(forBundleID: "x", among: findings)
        #expect(grouped == ["stable": ["1.0", "1.0"], "beta": ["1.1"]])
    }

    private func finding(_ id: String, _ registry: Registry, _ bundle: String,
                         _ channel: String, _ status: FindingStatus,
                         _ version: String?) -> Finding {
        Finding(recipeID: id, registry: registry, bundleID: bundle, channel: channel,
                status: status, version: version, endpointHost: "-")
    }
}
