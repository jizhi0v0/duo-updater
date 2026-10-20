import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `duo check` and `duo install` say what the menu bar's hint says: the
/// update puts the stable cask over a nightly or beta copy
/// (`UpdateResult.replacesChannelWithStable`). Said, never refused — the install
/// still runs. Mutation: drop either `print` of the note → its test goes red.
@Suite struct CheckChannelReminderTests {

    private func row(replacesChannel: String?) -> Check.Row {
        Check.Row(
            name: "Lapce", bundleID: "io.lapce", path: "/Applications/Lapce.app",
            installedVersion: "0.4.5", installedBuild: "1",
            latestVersion: "0.4.6", latestBuild: nil,
            source: "Homebrew", status: "update 0.4.6",
            hasUpdate: true, hidden: false, route: "homebrew",
            replacesChannel: replacesChannel)
    }

    private func checkLines(_ row: Check.Row) -> [String] {
        var lines: [String] = []
        Check.emitText([row], checked: true, print: { lines.append($0) })
        return lines
    }

    @Test func checkPrintsTheNoteUnderTheRow() throws {
        let lines = checkLines(row(replacesChannel: "nightly"))
        let at = try #require(lines.firstIndex { $0.contains("Lapce  0.4.5  →  0.4.6") })
        #expect(lines[at + 1]
            == "      note: this copy comes from the nightly channel; the update installs the stable cask over it")
    }

    @Test func checkSaysNothingForAnOrdinaryRow() {
        #expect(!checkLines(row(replacesChannel: nil)).contains { $0.contains("note:") })
    }

    /// `--json` carries it as a field, and leaves the field out when there is
    /// nothing to say, so existing consumers see the same rows as before.
    @Test func jsonCarriesTheChannelOnlyWhenSet() throws {
        let encoder = JSONEncoder()
        let with = String(decoding: try encoder.encode(row(replacesChannel: "nightly")), as: UTF8.self)
        let without = String(decoding: try encoder.encode(row(replacesChannel: nil)), as: UTF8.self)
        #expect(with.contains(#""replacesChannel":"nightly""#))
        #expect(!without.contains("replacesChannel"))
    }

    private func planned(copy channel: ReleaseChannel) -> Install.Planned {
        let app = InstalledApp(
            name: "Lapce", bundleID: "io.lapce", shortVersion: "0.4.5", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/Lapce.app"), isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: channel)
        var remote = RemoteVersion(
            shortVersion: "0.4.6", version: nil, downloadURL: nil,
            sourceName: "Homebrew", sourceIdentifier: "lapce")
        remote.offeredChannel = .stable
        return Install.Planned(
            result: UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "0.4.6")),
            route: .homebrew)
    }

    private func installLines(_ item: Install.Planned) -> [String] {
        var lines: [String] = []
        Install.describe([item], refusals: [], print: { lines.append($0) })
        return lines
    }

    @Test func installPrintsTheNoteUnderThePlannedRow() throws {
        let lines = installLines(planned(copy: .nightly))
        let at = try #require(lines.firstIndex { $0.contains("Lapce  0.4.5  →  0.4.6  [homebrew]") })
        #expect(lines[at + 1]
            == "      note: this copy comes from the nightly channel; the update installs the stable cask over it")
    }

    @Test func installSaysNothingForAStableCopy() {
        #expect(!installLines(planned(copy: .stable)).contains { $0.contains("note:") })
    }
}
