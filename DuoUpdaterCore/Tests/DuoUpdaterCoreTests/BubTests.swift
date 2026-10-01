import Testing
import Foundation
@testable import DuoUpdaterCore

/// A fake home with bub venvs laid out the way each installer leaves them
/// (measured 2026-10-01 in a scratch HOME: the official installer's steps with
/// uv 0.9.18, `uv tool install bub`, pipx 1.17.8's `environment`). Shared by the
/// `Bub*Tests` files; nothing here reads the host's home, process table or uv.
final class BubSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bub-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    func path(_ relative: String) -> String { url(relative).path }

    @discardableResult
    func write(_ relative: String, _ text: String, executable: Bool = false) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }

    func symlink(_ relative: String, to destination: String) throws {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    /// A venv at `venv` (relative to root): `pyvenv.cfg`, an interpreter, and —
    /// unless left out — `bin/bub` and bub's dist-info at `version`.
    func venv(
        _ venv: String, version: String? = "0.4.4", script: Bool = true, interpreter: Bool = true,
        directURL: String? = nil
    ) throws {
        try write(venv + "/pyvenv.cfg", "home = /nowhere\nversion_info = 3.12.12\n")
        if interpreter {
            try write(venv + "/python-real", "#!/bin/sh\n", executable: true)
            try symlink(venv + "/bin/python", to: path(venv + "/python-real"))
        } else {
            try symlink(venv + "/bin/python", to: path(venv + "/gone/python3.12"))
        }
        if script {
            try write(venv + "/bin/bub", "#!\(path(venv))/bin/python\n", executable: true)
        }
        if let version {
            try distInfo(venv, name: "bub", version: version, directURL: directURL)
        }
    }

    func distInfo(_ venv: String, name: String, version: String, directory: String? = nil, directURL: String? = nil) throws {
        let dir = venv + "/lib/python3.12/site-packages/" + (directory ?? "\(name)-\(version).dist-info")
        try write(dir + "/METADATA", "Metadata-Version: 2.5\nName: \(name)\nVersion: \(version)\nSummary: x\n\nBody: Name: other\n")
        if let directURL { try write(dir + "/direct_url.json", directURL) }
    }

    var scanner: BubScanner { BubScanner(home: home) }
    var installerVenv: String { "home/.bub/.venv" }
}

/// bub as a tracked command-line tool: where installs are found, what counts as a
/// change already running, what PyPI's newest release is, and when a one-click
/// update is offered.
@Suite struct BubTests {

    // MARK: - Scanner

    @Test func theInstallersVenvIsFoundWithItsMetadataVersion() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, version: "0.4.4")
        let found = box.scanner.scan()
        #expect(found == [BubInstall(
            path: box.path(box.installerVenv), method: .installer,
            executable: box.path(box.installerVenv + "/bin/bub"), version: "0.4.4", project: .absent)])
    }

    /// `METADATA` is the authority; a directory named `bub-…` that is another
    /// distribution, and a plugin's `bub_web_search-…` one, are not bub.
    @Test func onlyTheBubDistributionCounts() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, version: "0.5.0")
        try box.distInfo(box.installerVenv, name: "bub_web_search", version: "0.0.2")
        try box.distInfo(box.installerVenv, name: "bub-mcp", version: "0.3.0", directory: "bub-mcp-0.3.0.dist-info")
        #expect(box.scanner.scan().map(\.version) == ["0.5.0"])
    }

    @Test func theVersionFallsBackToTheDirectoryName() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, version: nil)
        try box.write(box.installerVenv + "/lib/python3.12/site-packages/bub-0.3.9.dist-info/METADATA", "Name: bub\n")
        #expect(box.scanner.scan().first?.version == "0.3.9")
    }

    @Test func uvToolAndBothPipxHomesAreFoundWithTheirMethods() throws {
        let box = try BubSandbox()
        try box.venv("home/.local/share/uv/tools/bub", version: "0.4.4")
        try box.venv("home/Library/Application Support/pipx/venvs/bub", version: "0.4.3")
        try box.venv("home/.local/pipx/venvs/bub", version: "0.4.2")
        let found = box.scanner.scan()
        #expect(found.map(\.method) == [.uvTool, .pipx, .pipx])
        #expect(found.map(\.version) == ["0.4.4", "0.4.3", "0.4.2"])
        #expect(found.allSatisfy { $0.project == nil })
    }

    @Test func aDirectoryThatIsNotAVenvIsNothing() throws {
        let box = try BubSandbox()
        try box.write(box.installerVenv + "/bin/bub", "#!/bin/sh\n", executable: true)
        #expect(box.scanner.scan().isEmpty)
    }

    @Test func aVenvWithoutBubIsNothing() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, version: nil, script: false)
        #expect(box.scanner.scan().isEmpty)
    }

    @Test func theScriptWithoutThePackageIsPackageMissing() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, version: nil)
        #expect(box.scanner.scan().first?.problem == .packageMissing)
    }

    @Test func thePackageWithoutTheScriptIsExecutableMissing() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, script: false)
        #expect(box.scanner.scan().first?.problem == .executableMissing)
    }

    @Test func aVenvWhosePythonIsGoneIsInterpreterMissing() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, interpreter: false)
        let install = try #require(box.scanner.scan().first)
        #expect(install.problem == .interpreterMissing)
        #expect(install.version == "0.4.4")
    }

    @Test func twoBubDistInfosLeaveTheVersionUnread() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, version: "0.4.4")
        try box.distInfo(box.installerVenv, name: "bub", version: "0.5.0")
        let install = try #require(box.scanner.scan().first)
        #expect(install.version == nil)
        #expect(install.problem == nil)
    }

    @Test(arguments: [
        (#"{"url":"file:///src/bub","dir_info":{"editable":true}}"#, BubInstall.DirectSource.editable),
        (#"{"url":"file:///src/bub","dir_info":{}}"#, .localPath),
        (#"{"url":"https://github.com/bubbuild/bub.git","vcs_info":{"vcs":"git","commit_id":"abc"}}"#, .vcs),
        (#"{"url":"https://example.com/bub-0.5.0-py3-none-any.whl","archive_info":{}}"#, .archive),
        (#"{"url":"file:///tmp/bub-0.5.0-py3-none-any.whl","archive_info":{}}"#, .localPath),
        ("not json", .archive),
    ])
    func directURLJsonNamesWhereThePackageCameFrom(json: String, expected: BubInstall.DirectSource) throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv, directURL: json)
        #expect(box.scanner.scan().first?.directSource == expected)
    }

    @Test func anIndexInstallHasNoDirectSource() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv)
        #expect(box.scanner.scan().first?.directSource == nil)
    }

    /// A venv that is an app's (or links into one) belongs to that app.
    @Test func aVenvInsideAnAppIsNeverAnInstall() throws {
        let box = try BubSandbox()
        try box.venv("Some.app/Contents/Resources/venv")
        try FileManager.default.createDirectory(at: box.url("home/.bub"), withIntermediateDirectories: true)
        try box.symlink(box.installerVenv, to: box.path("Some.app/Contents/Resources/venv"))
        #expect(box.scanner.scan().isEmpty)
    }

    @Test func theProjectIsReadForTheInstallersVenvOnly() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv)
        try box.venv("home/.local/share/uv/tools/bub")
        try box.write("home/.bub/bub-project/pyproject.toml", """
            [project]
            name = "bub-project"
            version = "0.1.0"
            requires-python = ">=3.12"
            dependencies = [
                "bub>=0.4.4",
                "bub-web-search>=0.0.2",
            ]
            """)
        #expect(box.scanner.scan().map(\.project) == [.listsBub, nil])
    }

    /// What an interrupted first `bub update` leaves (measured 2026-10-01): `uv
    /// init --bare`'s manifest, with no dependencies.
    @Test func aProjectWithoutBubIsMissingBub() throws {
        let box = try BubSandbox()
        try box.venv(box.installerVenv)
        try box.write("home/.bub/bub-project/pyproject.toml", """
            [project]
            name = "bub-project"
            version = "0.1.0"
            requires-python = ">=3.12"
            dependencies = []
            """)
        #expect(box.scanner.scan().first?.project == .missingBub)
    }

    @Test(arguments: [
        (#"dependencies = ["bub>=0.5.0"]"#, true),
        ("dependencies = [\n    \"bub-x[a,b]>=1\",\n    \"bub>=0.5.0\",\n]", true),
        (#"dependencies = ["Bub == 0.5.0"]"#, true),
        (#"dependencies = ["bub[trace]>=0.5"]"#, true),
        (#"dependencies = ["bub-web-search>=0.0.2", "bubble"]"#, false),
        (#"dependencies = []"#, false),
        ("[dependency-groups]\ndev = [\"bub\"]", false),
    ])
    func dependsOnBubReadsTheDependencyArray(text: String, expected: Bool) {
        #expect(BubScanner.dependsOnBub(text) == expected)
    }

    // MARK: - Activity

    func process(_ pid: pid_t, _ arguments: String...) -> ClaudeCodeActivity.Process {
        ClaudeCodeActivity.Process(pid: pid, arguments: arguments)
    }

    func installerInstall(_ box: BubSandbox) throws -> BubInstall {
        try box.venv(box.installerVenv)
        return try #require(box.scanner.scan().first)
    }

    /// The two shapes `ps` showed while `bub update bub` ran: by its full path,
    /// and through `~/.local/bin/bub` with the venv's `python3` as the interpreter.
    @Test func bubUpdateFromThisVenvIsBusyHoweverItWasStarted() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        let venv = install.path
        try box.symlink("home/.local/bin/bub", to: install.executable)
        #expect(BubActivity.busy(install, processes: [process(7, venv + "/bin/python", venv + "/bin/bub", "update", "bub")])
                == .bubCommand("update", pid: 7))
        #expect(BubActivity.busy(install, processes: [process(8, venv + "/bin/python3", box.path("home/.local/bin/bub"), "update", "bub")])
                == .bubCommand("update", pid: 8))
        #expect(BubActivity.busy(install, processes: [process(9, venv + "/bin/python", venv + "/bin/bub", "install", "bub-mcp")])
                == .bubCommand("install", pid: 9))
    }

    /// The script resolves into this venv even when another interpreter runs it.
    @Test func theScriptAloneIsEnoughToAttributeIt() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        #expect(BubActivity.busy(install, processes: [process(7, "/usr/bin/python3", install.executable, "uninstall", "x")])
                == .bubCommand("uninstall", pid: 7))
    }

    @Test func runningBubWithoutChangingItIsNotBusy() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        #expect(BubActivity.busy(install, processes: [
            process(7, install.path + "/bin/python", install.executable, "chat"),
            process(8, install.path + "/bin/python", install.executable, "gateway"),
        ]) == nil)
    }

    @Test func anotherVenvsBubUpdateIsNotThisOnesBusiness() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        try box.venv("home/.local/share/uv/tools/bub")
        let other = box.path("home/.local/share/uv/tools/bub")
        #expect(BubActivity.busy(install, processes: [process(7, other + "/bin/python", other + "/bin/bub", "update", "bub")]) == nil)
        // A relative script path cannot be attributed at all.
        #expect(BubActivity.busy(install, processes: [process(8, "/usr/bin/python3", "bub", "update")]) == nil)
    }

    /// The official installer's own steps name the venv.
    @Test func uvNamingTheVenvIsBusy() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        let venv = install.path
        #expect(BubActivity.busy(install, processes: [process(3, "/x/uv", "pip", "install", "--python", venv + "/bin/python", "--upgrade", "bub")]) == .uv(3))
        #expect(BubActivity.busy(install, processes: [process(4, "uv", "pip", "install", "--python=" + venv + "/bin/python", "bub")]) == .uv(4))
        #expect(BubActivity.busy(install, processes: [process(5, "/x/uv", "venv", "--python", "3.12", "--allow-existing", venv)]) == .uv(5))
    }

    /// `uv sync --active` names no venv; its parent `bub update` is what counts.
    @Test func uvNamingNoVenvIsNotBusyOnItsOwn() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        #expect(BubActivity.busy(install, processes: [
            process(3, "/x/uv", "sync", "--active", "--inexact", "--upgrade-package", "bub"),
            process(4, "/x/uv", "pip", "install", "--python", install.path + "-other/bin/python"),
            process(5, "/x/notuv", "venv", install.path),
        ]) == nil)
    }

    // MARK: - PyPI

    func pypi(_ releases: [String: [[String: Any]]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["info": ["version": "ignored"], "releases": releases])
    }

    static var file: [String: Any] { ["packagetype": "bdist_wheel", "yanked": false] }
    static var yanked: [String: Any] { ["packagetype": "bdist_wheel", "yanked": true] }

    @Test func theNewestFinalReleaseWithAnInstallableFileWins() throws {
        let data = try pypi([
            "0.4.4": [Self.file], "0.5.0": [Self.file, Self.file], "0.10.0": [Self.yanked],
            "0.11.0": [], "0.6.0a1": [Self.file], "0.6.0.dev1": [Self.file], "0.3.0": [Self.file],
        ])
        #expect(BubRelease.latest(fromJSON: data) == "0.5.0")
    }

    @Test func aReleaseWithOneFileLeftIsStillInstallable() throws {
        #expect(BubRelease.latest(fromJSON: try pypi(["0.5.0": [Self.yanked, Self.file], "0.4.4": [Self.file]])) == "0.5.0")
    }

    @Test func withOnlyPrereleasesTheNewestOfThemWins() throws {
        #expect(BubRelease.latest(fromJSON: try pypi(["0.1.0a1": [Self.file], "0.1.0b2": [Self.file]])) == "0.1.0b2")
    }

    @Test func aDocumentWithoutReleasesIsUnreadable() throws {
        #expect(BubRelease.latest(fromJSON: Data("{}".utf8)) == nil)
        #expect(BubRelease.latest(fromJSON: try pypi([:])) == nil)
    }

    @Test(arguments: [
        ("0.5.0", false), ("0.1", false), ("1.0.post1", false), ("1.0-post2", false),
        ("0.3.0a1", true), ("0.1.0b2", true), ("1.0rc1", true), ("1.0.dev3", true), ("1.0.post1.dev2", true),
    ])
    func prereleasesAreThePEP440Markers(version: String, expected: Bool) {
        #expect(BubRelease.isPrerelease(version) == expected)
    }

    // MARK: - Check

    func check(latest: String = "0.5.0", uv: String? = "/fake/uv/bin/uv") -> BubCheck {
        BubCheck(latest: { latest }, uv: { _ in uv })
    }

    func install(
        _ method: BubInstall.Method = .installer, version: String? = "0.4.4", problem: BubInstall.Problem? = nil,
        directSource: BubInstall.DirectSource? = nil, project: BubInstall.Project? = .listsBub
    ) -> BubInstall {
        BubInstall(
            path: "/u/.bub/.venv", method: method, executable: "/u/.bub/.venv/bin/bub", version: version,
            problem: problem, directSource: directSource, project: method == .installer ? project : nil)
    }

    @Test func theInstallersVenvIsOfferedBubUpdateBubWithItsUVFirst() async {
        let status = await check().status(of: install(), busy: nil)
        #expect(status.kind == .bub)
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "0.5.0")
        #expect(status.installedVersion == "0.4.4")
        #expect(status.channel == nil)
        #expect(status.withheld == nil)
        #expect(status.oneClick == CLIToolCommand(
            executable: "/u/.bub/.venv/bin/bub", arguments: ["update", "bub"], pathPrefix: "/fake/uv/bin"))
        #expect(status.detail == .bub(install()))
    }

    /// A project with no `bub-project` yet is fine: `bub update` creates it
    /// (measured).
    @Test func noProjectYetIsStillOffered() async {
        #expect(await check().status(of: install(project: .absent), busy: nil).oneClick != nil)
        #expect(await check().status(of: install(project: nil), busy: nil).oneClick != nil)
    }

    @Test func upToDateAndAheadOfferNothing() async {
        let same = await check(latest: "0.4.4").status(of: install(), busy: nil)
        #expect(same.state == .upToDate && same.oneClick == nil && same.withheld == nil)
        let ahead = await check(latest: "0.4.3").status(of: install(), busy: nil)
        #expect(ahead.state == .ahead && ahead.oneClick == nil)
    }

    @Test func uvToolAndPipxAreReportedNotOffered() async {
        for method in [BubInstall.Method.uvTool, .pipx] {
            let status = await check().status(of: install(method), busy: nil)
            #expect(status.state == .updateAvailable)
            #expect(status.latestVersion == "0.5.0")
            #expect(status.oneClick == nil)
            #expect(status.withheld == .unsupportedInstaller)
        }
    }

    /// Not compared, and PyPI is not even asked.
    @Test func aDirectSourceIsNeitherComparedNorOffered() async {
        let asked = BubSandboxRecorder()
        let check = BubCheck(latest: { asked.add("latest"); return "0.5.0" }, uv: { _ in "/fake/uv" })
        let status = await check.status(of: install(directSource: .editable), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.latestVersion == nil)
        #expect(status.oneClick == nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(asked.all.isEmpty)
    }

    @Test func aBrokenInstallIsNeverCompared() async {
        let status = await check().status(of: install(problem: .interpreterMissing), busy: nil)
        #expect(status.state == .unknown && status.withheld == .broken && status.oneClick == nil)
    }

    @Test func anUnreadableVersionIsNeverCompared() async {
        let status = await check().status(of: install(version: nil), busy: nil)
        #expect(status.state == .unknown && status.withheld == .versionUnreadable)
    }

    @Test func pypiUnreachableIsChannelUnreadable() async {
        let check = BubCheck(latest: { throw BubRelease.Failure.http(503) }, uv: { _ in "/fake/uv" })
        let status = await check.status(of: install(), busy: nil)
        #expect(status.state == .unknown && status.withheld == .channelUnreadable && status.latestVersion == nil)
    }

    @Test func noUVMeansUpdaterMissing() async {
        let status = await check(uv: nil).status(of: install(), busy: nil)
        #expect(status.state == .updateAvailable && status.withheld == .updaterMissing && status.oneClick == nil)
    }

    @Test func aChangeAlreadyRunningWithholdsOneClick() async {
        let status = await check().status(of: install(), busy: .bubCommand("update", pid: 4))
        #expect(status.withheld == .busy && status.oneClick == nil)
        #expect(status.note == "bub update is running (pid 4)")
    }

    @Test func aProjectWithoutBubWithholdsOneClick() async {
        let status = await check().status(of: install(project: .missingBub), busy: nil)
        #expect(status.state == .updateAvailable && status.withheld == .broken && status.oneClick == nil)
    }

    @Test func pypiIsAskedOnceForEveryInstall() async {
        let asked = BubSandboxRecorder()
        let check = BubCheck(latest: { asked.add("latest"); return "0.5.0" }, uv: { _ in "/fake/uv" })
        let statuses = await check.statuses(of: [install(), install(.uvTool), install(.pipx)]) { _ in nil }
        #expect(statuses.map(\.state) == [.updateAvailable, .updateAvailable, .updateAvailable])
        #expect(asked.all == ["latest"])
    }

    @Test func aFailedPyPIReadIsNotRetriedPerInstall() async {
        let asked = BubSandboxRecorder()
        let check = BubCheck(latest: { asked.add("latest"); throw BubRelease.Failure.unreadable }, uv: { _ in nil })
        let statuses = await check.statuses(of: [install(), install(.pipx)]) { _ in nil }
        #expect(statuses.map(\.withheld) == [.channelUnreadable, .channelUnreadable])
        #expect(asked.all == ["latest"])
    }

    // MARK: - uv lookup

    /// bub's `_find_uv` order: the venv's scripts, `~/.local/bin`, then `PATH`.
    @Test func uvIsLookedUpWhereBubLooks() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        let system = [box.path("brew/bin"), box.path("usr-local/bin")]
        func found() -> String? { BubCheck.uv(for: install, home: box.home, systemDirectories: system) }

        #expect(found() == nil)
        try box.write("usr-local/bin/uv", "#!/bin/sh\n", executable: true)
        #expect(found() == box.path("usr-local/bin/uv"))
        try box.write("brew/bin/uv", "#!/bin/sh\n", executable: true)
        #expect(found() == box.path("brew/bin/uv"))
        try box.write("home/.local/bin/uv", "#!/bin/sh\n", executable: true)
        #expect(found() == box.path("home/.local/bin/uv"))
        try box.write(box.installerVenv + "/bin/uv", "#!/bin/sh\n", executable: true)
        #expect(found() == install.path + "/bin/uv")
    }

    @Test func aUVThatCannotRunIsNotFound() throws {
        let box = try BubSandbox()
        let install = try installerInstall(box)
        try box.write("home/.local/bin/uv", "not executable")
        #expect(BubCheck.uv(for: install, home: box.home, systemDirectories: []) == nil)
    }

    // MARK: - Provider

    @Test func theProviderIsBubs() {
        #expect(BubProvider().kind == .bub)
    }
}

/// Collects what a seam was asked, from whichever thread asks.
final class BubSandboxRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.withLock { items.append(item) } }
    var all: [String] { lock.withLock { items } }
}
