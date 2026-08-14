import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

private func app(
    _ name: String, _ bundleID: String?, _ path: String, version: String = "1.0"
) -> InstalledApp {
    InstalledApp(
        name: name, bundleID: bundleID, shortVersion: version, buildVersion: "1",
        path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
}

private let installed = [
    app("Cursor", "com.todesktop.230313mzl4w4u92", "/Applications/Cursor.app"),
    app("HBuilderX", "com.dcloud.HBuilderX", "/Applications/HBuilderX.app"),
    app("HBuilderX-Alpha", "com.dcloud.HBuilderX", "/Applications/HBuilderX-Alpha.app"),
    app("Code", "com.microsoft.VSCode", "/Applications/Code.app"),
    // Two Xcodes: same name, same bundle id, same marketing version — only the
    // build and the path separate them. This is the case the listing has to serve.
    app("Xcode", "com.apple.dt.Xcode", "/Applications/Xcode-27b1.app",
        version: "27.0 (27A5194q)"),
    app("Xcode", "com.apple.dt.Xcode", "/Applications/Xcode-beta.app",
        version: "27.0 (27A5237l)"),
]

@Suite struct InventorySelectionTests {

    @Test func noArgumentsMeansEverything() throws {
        let selected = try Inventory.select(installed, matching: []).get()
        #expect(selected.count == installed.count)
    }

    @Test func anExactPathWins() throws {
        let selected = try Inventory.select(
            installed, matching: ["/Applications/HBuilderX-Alpha.app"]).get()
        #expect(selected.map(\.name) == ["HBuilderX-Alpha"])
    }

    /// A shared bundle id is not ambiguity — Thunderbird stable/esr and the
    /// Android Studio channels legitimately share one, and naming it means all
    /// of them.
    @Test func aSharedBundleIDSelectsEveryCopy() throws {
        let selected = try Inventory.select(installed, matching: ["com.dcloud.HBuilderX"]).get()
        #expect(Set(selected.map(\.name)) == ["HBuilderX", "HBuilderX-Alpha"])
    }

    @Test func anUnambiguousNamePrefixResolves() throws {
        #expect(try Inventory.select(installed, matching: ["curs"]).get().map(\.name) == ["Cursor"])
    }

    /// The important one: `duo install HBuilderX` must not pick a copy for you.
    @Test func anAmbiguousPrefixIsRefusedAndNamesTheCandidates() {
        let result = Inventory.select(installed, matching: ["HBuilderX"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("/Applications/HBuilderX.app"))
        #expect(failure.description.contains("/Applications/HBuilderX-Alpha.app"))
    }

    /// Two installs of the same app: the listing has to say something that tells
    /// them apart, and the advice has to be advice the user can act on — "name one
    /// exactly" matches both again.
    @Test func candidatesSharingANameAreSeparatedByVersionAndPath() {
        let result = Inventory.select(installed, matching: ["Xcode"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("Xcode 27.0 (27A5194q) — /Applications/Xcode-27b1.app"))
        #expect(failure.description.contains("Xcode 27.0 (27A5237l) — /Applications/Xcode-beta.app"))
        #expect(failure.description.contains("pass the path"))
        #expect(!failure.description.contains("Name one exactly"))
    }

    /// Different names, so naming one exactly IS the fix — the hint must not tell
    /// everyone to type a path.
    @Test func candidatesWithDistinctNamesAreToldToNameOne() {
        let result = Inventory.select(installed, matching: ["HBuilderX"])
        guard case .failure(let failure) = result else {
            Issue.record("expected a refusal, got \(result)")
            return
        }
        #expect(failure.description.contains("Name one exactly"))
    }

    @Test func anUnknownNameIsAnError() {
        #expect(throws: Inventory.SelectionFailure.self) {
            try Inventory.select(installed, matching: ["nope"]).get()
        }
    }

    @Test func theSameAppNamedTwoWaysIsSelectedOnce() throws {
        let selected = try Inventory.select(
            installed, matching: ["/Applications/Cursor.app", "Cursor"]).get()
        #expect(selected.count == 1)
    }
}

@Suite struct CheckRowTests {

    private func row(hasUpdate: Bool, hidden: Bool) -> Check.Row {
        Check.Row(
            name: "Fixture", bundleID: "com.example.fixture", path: "/Applications/Fixture.app",
            installedVersion: "1.0", installedBuild: "1",
            latestVersion: "1.0", source: "Vendor", status: "up-to-date",
            hasUpdate: hasUpdate, hidden: hidden, route: nil)
    }

    /// An up-to-date app still reports a `latestVersion`, so counting on that
    /// made `duo check --all` claim every checked app was an update — and made
    /// it exit 1 unconditionally.
    @Test func beingCurrentIsNotAnUpdate() {
        #expect(!Check.isActionable(row(hasUpdate: false, hidden: false)))
        #expect(Check.isActionable(row(hasUpdate: true, hidden: false)))
    }

    @Test func aHiddenUpdateIsNothingToDo() {
        #expect(!Check.isActionable(row(hasUpdate: true, hidden: true)))
    }
}
