import Testing
import Foundation
@testable import DuoUpdaterCore

/// fx: finding a copy, reading its settings and its channel, the verdict.
///
/// Every install is a plain file in a temporary directory; the signature check,
/// the `--version` run, the quarantine check and the channel are injected, so
/// nothing here depends on what is installed or signed on the host, and nothing
/// reaches the network.
@Suite struct FxTests {

    // MARK: - Fixtures

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("fx-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }

        @discardableResult
        func write(_ relative: String, _ text: String = "binary") throws -> URL {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            return url
        }

        func symlink(_ relative: String, to destination: String) throws {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
        }
    }

    /// Records which files `--version` was run on.
    final class Runs: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    /// A scanner over the sandbox's home. Files whose contents start with
    /// "vercel" are Vercel's, "adhoc" another signer's, anything else invalid;
    /// `--version` answers "0.0.11" and records the file.
    func scanner(
        _ box: Sandbox, runs: Runs = Runs(), version: String? = "0.0.11", quarantined: Set<String> = []
    ) -> FxScanner {
        FxScanner(
            home: box.home,
            checkSignature: { url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.hasPrefix("vercel") { return .vercel }
                return text.hasPrefix("adhoc") ? .otherSigner : .invalid
            },
            readVersion: { url in runs.add(url.path); return version },
            isQuarantined: { quarantined.contains($0.lastPathComponent) })
    }

    // MARK: - Scanner

    @Test func conventionalVercelCopyIsRunForItsVersion() async throws {
        let box = try Sandbox()
        try box.write("home/.local/bin/fx", "vercel")
        let runs = Runs()
        let installs = await scanner(box, runs: runs).scan()
        let install = try #require(installs.first)
        #expect(installs.count == 1)
        #expect(install.path == box.path("home/.local/bin/fx"))
        #expect(install.origin == .conventional)
        #expect(install.signature == .vercel)
        #expect(install.version == "0.0.11")
        #expect(runs.all == [install.executable])
    }

    /// Rule 1: an fx that fails the signature check is never run. Still
    /// reported at the conventional path, as not Vercel's.
    @Test func copyThatIsNotVercelsIsNeverRun() async throws {
        let box = try Sandbox()
        try box.write("home/.local/bin/fx", "adhoc")
        let runs = Runs()
        let install = try #require(await scanner(box, runs: runs).scan().first)
        #expect(install.signature == .otherSigner)
        #expect(install.version == nil)
        #expect(runs.all.isEmpty)
    }

    @Test func quarantinedCopyIsNotRun() async throws {
        let box = try Sandbox()
        try box.write("home/.local/bin/fx", "vercel")
        let runs = Runs()
        let install = try #require(await scanner(box, runs: runs, quarantined: ["fx"]).scan().first)
        #expect(install.quarantined)
        #expect(install.version == nil)
        #expect(runs.all.isEmpty)
    }

    /// Identity is the path; the signature and the version come from the file
    /// the link resolves to.
    @Test func symlinkIsFollowedButThePathIsTheIdentity() async throws {
        let box = try Sandbox()
        let target = try box.write("opt/fx-0.0.11/fx", "vercel")
        try box.symlink("home/.local/bin/fx", to: target.path)
        let runs = Runs()
        let install = try #require(await scanner(box, runs: runs).scan().first)
        #expect(install.path == box.path("home/.local/bin/fx"))
        #expect(install.executable == target.resolvingSymlinksInPath().path)
        #expect(runs.all == [target.resolvingSymlinksInPath().path])
    }

    @Test func linkToNothingOrAnEmptyFileIsBroken() async throws {
        let box = try Sandbox()
        try box.symlink("home/.local/bin/fx", to: box.path("gone/fx"))
        let dangling = try #require(await scanner(box).scan().first)
        #expect(dangling.problem == .executableMissing)

        let other = try Sandbox()
        try other.write("home/.local/bin/fx", "")
        let empty = try #require(await scanner(other).scan().first)
        #expect(empty.problem == .executableMissing)
    }

    @Test func nothingInstalledFindsNothing() async throws {
        let box = try Sandbox()
        #expect(await scanner(box).scan().isEmpty)
    }

    /// A user-added path has nothing but its signature to say it is fx.
    @Test func userPathsAreReportedOnlyWhenVercelsAndOnlyOnce() async throws {
        let box = try Sandbox()
        try box.write("home/.local/bin/fx", "vercel")
        try box.write("tools/fx", "vercel")
        try box.write("other/fx", "adhoc")
        let installs = await scanner(box).scan(userPaths: [
            box.path("tools/fx"), box.path("other/fx"), box.path("home/.local/bin/fx"), box.path("tools/fx"),
        ])
        #expect(installs.map(\.path) == [box.path("home/.local/bin/fx"), box.path("tools/fx")])
        #expect(installs.map(\.origin) == [.conventional, .userAdded])
    }

    /// A copy inside an `.app` belongs to that app, by path or once resolved.
    @Test func copiesInsideAnAppAreNotDetected() async throws {
        let box = try Sandbox()
        let inner = try box.write("Apps/Fx.app/Contents/MacOS/fx", "vercel")
        try box.symlink("home/.local/bin/fx", to: inner.path)
        let runs = Runs()
        #expect(await scanner(box, runs: runs).scan(userPaths: [inner.path]).isEmpty)
        #expect(runs.all.isEmpty)
    }

    @Test func versionIsFxsOwnShape() {
        #expect(FxScanner.parseVersion("0.0.12\n") == "0.0.12")
        #expect(FxScanner.parseVersion("v0.0.9") == "0.0.9")
        // The TUI's dev label is not what `--version` prints; nothing else is a version.
        #expect(FxScanner.parseVersion("v0.0.9-e3ad6d8 [dev]") == nil)
        #expect(FxScanner.parseVersion("0.0") == nil)
        #expect(FxScanner.parseVersion("") == nil)
        #expect(FxScanner.parseVersion("fx: unknown subcommand") == nil)
    }

    /// The real child-process path, on a script standing in for fx.
    ///
    /// Under a generous deadline, not the production 5 s: on CI (2026-10-06, run
    /// 37457315378) the good script missed 5 s with the suite saturating the pool,
    /// and wall-clock bounds are not sound in a parallel suite. The deadline only
    /// keeps a hung child from hanging the run.
    @Test func runVersionReadsStandardOutputAndRejectsAFailure() async throws {
        let box = try Sandbox()
        let good = try box.write("bin/good", "#!/bin/sh\necho 0.0.12\necho noise >&2\n")
        let bad = try box.write("bin/bad", "#!/bin/sh\necho 0.0.12\nexit 3\n")
        for url in [good, bad] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let generous = ChildProcess.Deadline(terminateAfter: .seconds(120), killAfter: .seconds(125))
        #expect(await FxScanner.runVersion(good, deadline: generous) == "0.0.12")
        #expect(await FxScanner.runVersion(bad, deadline: generous) == nil)
    }

    @Test func quarantineIsReadFromTheExtendedAttribute() throws {
        let box = try Sandbox()
        let url = try box.write("fx", "x")
        #expect(!FxScanner.hasQuarantine(url))
        let value = "0083;00000000;Safari;"
        #expect(setxattr(url.path, "com.apple.quarantine", value, value.utf8.count, 0, 0) == 0)
        #expect(FxScanner.hasQuarantine(url))
    }

    // MARK: - Settings

    @Test func channelComesFromSettingsAndFallsBackToStableAsFxDoes() {
        func channel(_ json: String) -> FxSettings.Channel { FxSettings.parse(Data(json.utf8)).channel }
        #expect(channel(#"{"update_channel":"dev"}"#) == .dev)
        #expect(channel(#"{"update_channel":"DEV"}"#) == .dev)
        #expect(channel(#"{"update_channel":"stable"}"#) == .stable)
        #expect(channel(#"{}"#) == .stable)
        // fx drops a file it cannot parse, and so runs on stable.
        #expect(channel(#"{"update_channel":"nightly"}"#) == .stable)
        #expect(channel(#"{"update_channel":5}"#) == .stable)
        #expect(channel(#"["update_channel","dev"]"#) == .stable)
        #expect(channel("not json") == .stable)
    }

    /// fx's `auto_upgrade`: a JSON bool, absent means on, any other type makes fx
    /// drop the whole file — channel included. Mutation: accepting any NSNumber
    /// (dropping the bool-type check) reads `0` as "off" and keeps the channel.
    @Test func autoUpgradeIsABoolThatDefaultsOnAsFxReadsIt() {
        func settings(_ json: String) -> FxSettings { FxSettings.parse(Data(json.utf8)) }
        #expect(settings(#"{}"#).autoUpgrade)
        #expect(settings(#"{"auto_upgrade":true}"#).autoUpgrade)
        #expect(!settings(#"{"auto_upgrade":false}"#).autoUpgrade)
        #expect(settings(#"{"auto_upgrade":false,"update_channel":"dev"}"#) == FxSettings(channel: .dev, autoUpgrade: false))
        // Not a bool: fx drops the file, so auto-upgrade is on and the channel stable.
        #expect(settings(#"{"auto_upgrade":0,"update_channel":"dev"}"#) == FxSettings())
        #expect(settings(#"{"auto_upgrade":"false","update_channel":"dev"}"#) == FxSettings())
    }

    @Test func missingSettingsFileIsStable() throws {
        let box = try Sandbox()
        #expect(FxSettings.read(from: box.home.appendingPathComponent(".fx/settings.json")).channel == .stable)
        try box.write("home/.fx/settings.json", #"{"update_channel":"dev","model":"x"}"#)
        #expect(FxSettings.read(from: box.home.appendingPathComponent(".fx/settings.json")).channel == .dev)
    }

    // MARK: - Channel files

    @Test func channelFilesParseTheWayFxParsesThem() {
        #expect(FxRelease.parseStable("v0.0.12\n") == "0.0.12")
        #expect(FxRelease.parseStable("0.0.12") == "0.0.12")
        #expect(FxRelease.parseStable("<html>404</html>") == nil)
        #expect(FxRelease.parseStable("v0.0") == nil)

        let dev = #"{"version":"0.0.12","commit":"d44cd84ae19c8b642797f431a04df6e53c66a13e"}"#
        #expect(FxRelease.parseDev(Data(dev.utf8))
            == .dev(version: "0.0.12", revision: "d44cd84ae19c8b642797f431a04df6e53c66a13e"))
        #expect(FxRelease.parseDev(Data(#"{"version":"0.0.12","commit":"../escape"}"#.utf8)) == nil)
        #expect(FxRelease.parseDev(Data(#"{"version":"0.0.12","commit":"abc12"}"#.utf8)) == nil)
        #expect(FxRelease.parseDev(Data(#"{"version":"0.3","commit":"0123456"}"#.utf8)) == nil)
        #expect(FxRelease.parseDev(Data("[]".utf8)) == nil)
    }

    @Test func versionsCompareAsNumbers() {
        #expect(FxRelease.compare("0.0.9", "0.0.12") == .orderedAscending)
        #expect(FxRelease.compare("0.0.12", "v0.0.12") == .orderedSame)
        #expect(FxRelease.compare("0.1.0", "0.0.99") == .orderedDescending)
    }

    // MARK: - Verdict

    /// Records which channels the check asked.
    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [FxSettings.Channel] = []
        func add(_ item: FxSettings.Channel) { lock.withLock { items.append(item) } }
        var all: [FxSettings.Channel] { lock.withLock { items } }
    }

    func check(_ latest: FxRelease.Latest, asked: Asked = Asked()) -> FxCheck {
        FxCheck(latest: { asked.add($0); return latest })
    }

    func install(version: String? = "0.0.11", signature: FxInstall.Signature? = .vercel) -> FxInstall {
        FxInstall(
            path: "/Users/u/.local/bin/fx", executable: "/Users/u/.local/bin/fx", version: version,
            signature: signature)
    }

    @Test func olderStableOffersFxUpgradeWithNoChannel() async {
        let asked = Asked()
        let status = await check(.stable(version: "0.0.12"), asked: asked)
            .status(of: install(), settings: FxSettings(), busy: nil)
        #expect(status.kind == .fx)
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "0.0.11")
        #expect(status.latestVersion == "0.0.12")
        #expect(status.channel == "stable")
        #expect(status.withheld == nil)
        #expect(status.oneClick == CLIToolCommand(executable: "/Users/u/.local/bin/fx", arguments: ["upgrade"], pathPrefix: nil))
        #expect(asked.all == [.stable])
    }

    @Test func sameIsUpToDateAndNewerIsAhead() async {
        let same = await check(.stable(version: "0.0.11")).status(of: install(), settings: FxSettings(), busy: nil)
        #expect(same.state == .upToDate)
        #expect(same.oneClick == nil)
        let ahead = await check(.stable(version: "0.0.10")).status(of: install(), settings: FxSettings(), busy: nil)
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    @Test func busyWithholdsTheOneClick() async {
        let status = await check(.stable(version: "0.0.12"))
            .status(of: install(), settings: FxSettings(), busy: .upgradeCommand(42))
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .busy)
        #expect(status.oneClick == nil)
        #expect(status.note == "fx upgrade is running (pid 42)")
    }

    /// Auto-upgrade off: reported with the command a one-click would run, never
    /// offered — Claude Code's rule. Mutation: dropping the `autoUpgrade` gate
    /// offers the click.
    @Test func autoUpgradeOffReportsTheCommandInsteadOfOfferingIt() async {
        let status = await check(.stable(version: "0.0.12"))
            .status(of: install(), settings: FxSettings(channel: .stable, autoUpgrade: false), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .autoUpdateOff)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand
            == CLIToolCommand(executable: "/Users/u/.local/bin/fx", arguments: ["upgrade"], pathPrefix: nil))
        let current = await check(.stable(version: "0.0.11"))
            .status(of: install(), settings: FxSettings(channel: .stable, autoUpgrade: false), busy: nil)
        #expect(current.state == .upToDate)
        #expect(current.manualCommand == nil)
    }

    /// On `dev` fx replaces any stable build — and what it installs is an ad hoc
    /// signed binary DuoUpdater would refuse to run. Reported, never offered.
    @Test func devChannelIsAnUpdateButNotOffered() async {
        let asked = Asked()
        let status = await check(.dev(version: "0.0.12", revision: "d44cd84ae19c8b642797f431a04df6e53c66a13e"), asked: asked)
            .status(of: install(version: "0.0.12"), settings: FxSettings(channel: .dev), busy: nil)
        #expect(asked.all == [.dev])
        #expect(status.channel == "dev")
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "0.0.12-d44cd84")
        #expect(status.withheld == .channelUnsigned)
        #expect(status.oneClick == nil)
    }

    @Test func notVercelsIsWithheldBeforeTheChannelIsAsked() async {
        let asked = Asked()
        let status = await check(.stable(version: "0.0.12"), asked: asked)
            .status(of: install(version: nil, signature: .otherSigner), settings: FxSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .wrongSigner)
        #expect(asked.all.isEmpty)
    }

    /// On `dev`, a copy that is not Vercel's is fx's own ad hoc dev build: said
    /// so, not "not signed by Vercel". Still not run, still no channel asked.
    /// Mutation: dropping the `.dev` branch reads it `.wrongSigner`.
    @Test func anUnsignedCopyOnDevIsTheChannelsBuild() async {
        let asked = Asked()
        let status = await check(.stable(version: "0.0.12"), asked: asked)
            .status(of: install(version: nil, signature: .otherSigner), settings: FxSettings(channel: .dev), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .channelUnsigned)
        #expect(asked.all.isEmpty)
        // A copy whose seal is broken is not a dev build, whatever the channel.
        let invalid = await check(.stable(version: "0.0.12"))
            .status(of: install(version: nil, signature: .invalid), settings: FxSettings(channel: .dev), busy: nil)
        #expect(invalid.withheld == .wrongSigner)
    }

    @Test func unreadableVersionQuarantineAndBrokenAreWithheld() async {
        let noVersion = await check(.stable(version: "0.0.12")).status(of: install(version: nil), settings: FxSettings(), busy: nil)
        #expect(noVersion.withheld == .versionUnreadable)

        // Even with a version in hand, a quarantined file is never offered to run.
        let quarantined = FxInstall(path: "/p/fx", executable: "/p/fx", version: "0.0.11", signature: .vercel, quarantined: true)
        let q = await check(.stable(version: "0.0.12")).status(of: quarantined, settings: FxSettings(), busy: nil)
        #expect(q.withheld == .versionUnreadable)
        #expect(q.state == .unknown)
        #expect(q.oneClick == nil)

        let broken = FxInstall(path: "/p/fx", version: nil, problem: .executableMissing)
        let b = await check(.stable(version: "0.0.12")).status(of: broken, settings: FxSettings(), busy: nil)
        #expect(b.withheld == .broken)
    }

    @Test func unreachableChannelIsUnknown() async {
        let failing = FxCheck(latest: { _ in throw FxRelease.Failure.http(503) })
        let status = await failing.status(of: install(), settings: FxSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .channelUnreadable)
        #expect(status.oneClick == nil)
    }

    @Test func reportCarriesTheSettingsAndEachInstallsBusyState() async {
        let a = install()
        let b = FxInstall(path: "/opt/fx", executable: "/opt/fx", version: "0.0.11", signature: .vercel)
        let report = await FxProvider.report(
            installs: [a, b], settings: FxSettings(channel: .stable),
            processes: [ClaudeCodeActivity.Process(pid: 7, arguments: ["fx", "upgrade"])],
            check: check(.stable(version: "0.0.12")))
        #expect(report.kind == .fx)
        #expect(report.context == .fx(FxSettings(channel: .stable)))
        #expect(report.statuses.map(\.path) == ["/Users/u/.local/bin/fx", "/opt/fx"])
        #expect(report.statuses.map(\.withheld) == [.busy, .busy])
    }

    // MARK: - Activity

    @Test func onlyAnFxUpgradeIsBusy() {
        let fx = FxInstall(path: "/Users/u/bin/vfx", executable: "/Users/u/bin/vfx", version: "0.0.11", signature: .vercel)
        #expect(FxActivity.isUpgradeCommand(["fx", "upgrade"], install: fx))
        #expect(FxActivity.isUpgradeCommand(["/Users/u/.local/bin/fx", "upgrade", "--channel", "dev"], install: fx))
        #expect(FxActivity.isUpgradeCommand(["/Users/u/bin/vfx", "upgrade"], install: fx))
        #expect(!FxActivity.isUpgradeCommand(["fx"], install: fx))
        #expect(!FxActivity.isUpgradeCommand(["fx", "--version"], install: fx))
        #expect(!FxActivity.isUpgradeCommand(["fx", "ask", "upgrade"], install: fx))
        #expect(!FxActivity.isUpgradeCommand(["brew", "upgrade"], install: fx))
        #expect(FxActivity.busy(fx, processes: [
            .init(pid: 1, arguments: ["fx"]), .init(pid: 9, arguments: ["fx", "upgrade"]),
        ]) == .upgradeCommand(9))
        #expect(FxActivity.busy(fx, processes: [.init(pid: 1, arguments: ["fx", "sessions"])]) == nil)
    }
}
