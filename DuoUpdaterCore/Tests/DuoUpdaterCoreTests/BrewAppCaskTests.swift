import Testing
import Foundation
@testable import DuoUpdaterCore

/// An official cask whose apps have rows is a package row only while none of
/// those rows found an update source (`BrewAppCask.unclaimed`).
@Suite struct BrewAppCaskTests {
    let elements = "/Applications/Karabiner-Elements.app"
    let viewer = "/Applications/Karabiner-EventViewer.app"

    var cask: BrewAppCask {
        BrewAppCask(
            row: BrewInstalledFormula(
                name: "karabiner-elements", installedVersion: "16.3.0", availableVersion: nil, kind: .cask),
            appPaths: [elements, viewer])
    }

    func row(_ path: String, source: String? = nil, status: UpdateStatus = .unknown) -> UpdateResult {
        let app = InstalledApp(
            name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            bundleID: "org.pqrs.\(path.count)", shortVersion: "16.3.0", buildVersion: "16.3.0",
            path: URL(fileURLWithPath: path), isMASApp: false, sparkleFeedURL: nil)
        let remote = source.map {
            RemoteVersion(shortVersion: "16.3.0", version: nil, downloadURL: nil, sourceName: $0)
        }
        return UpdateResult(app: app, remote: remote, status: status)
    }

    func unclaimed(_ rows: [UpdateResult], checked: Bool = true, ignoring: String? = nil) -> Set<String> {
        BrewAppCask.unclaimed([cask], rows: rows, checked: checked) { $0.path.path == ignoring }
    }

    @Test func listedWhenEveryAppFoundNoSource() {
        #expect(unclaimed([row(elements), row(viewer)]) == ["karabiner-elements"])
    }

    /// Before a round answers, every row is an unchecked `.unknown`.
    @Test func notBeforeACheckHasAnswered() {
        #expect(unclaimed([row(elements), row(viewer)], checked: false).isEmpty)
    }

    /// Mutation: require only one app to be sourceless → a Sparkle-updated app's
    /// stale cask joins Upgrade All and brew reinstalls over it.
    @Test func notWhenAnyAppHasItsOwnRoute() {
        #expect(unclaimed([row(elements), row(viewer, source: "Sparkle", status: .upToDate)]).isEmpty)
        #expect(unclaimed([row(elements, source: "Homebrew", status: .upToDate), row(viewer)]).isEmpty)
    }

    /// A source that applied and failed is a route, retried by the next round.
    @Test func notWhenACheckFailed() {
        #expect(unclaimed([row(elements, status: .error("timed out")), row(viewer)]).isEmpty)
    }

    @Test func notWhenAnAppHasNoRow() {
        #expect(unclaimed([row(elements)]).isEmpty)
    }

    @Test func notWhenThePersonIgnoredAnApp() {
        #expect(unclaimed([row(elements), row(viewer)], ignoring: viewer).isEmpty)
    }

    /// Only official casks that install an app are app casks: a third-party one
    /// keeps its own package row (`appLessCasks`), and an untrusted-tap copy is
    /// an unchecked row.
    @Test func appCasksAreTheOfficialCasksWithAppRows() {
        let info = Data(#"""
        {"casks":[
          {"token":"karabiner-elements","tap":"homebrew/cask","installed":"16.3.0"},
          {"token":"codex","tap":"homebrew/cask","installed":"0.163.0"},
          {"token":"aerospace","tap":"nikitabobko/tap","installed":"0.21.3-Beta"},
          {"token":"untrusted","tap":null,"installed":"1.0"}]}
        """#.utf8)
        let app = BrewFormulaService.CaskFacts(installsAnApp: true, appPaths: [elements], needsSudo: true)
        let none = BrewFormulaService.CaskFacts(installsAnApp: false, needsSudo: false)
        let casks = BrewFormulaService.appCasks(
            installedInfo: info,
            facts: ["karabiner-elements": app, "codex": none, "aerospace": app, "untrusted": app])
        #expect(casks.map(\.row.name) == ["karabiner-elements"])
        #expect(casks.first?.appPaths == [elements])
        #expect(casks.first?.row.needsSudo == true)
        #expect(casks.first?.row.kind == .cask)
    }
}
