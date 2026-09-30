import Testing
import Foundation
@testable import DuoUpdaterCore

/// Claude Code as a tracked command-line tool: where installs are found, which
/// settings are obeyed, what counts as an update already running, and when a
/// one-click update is offered.
///
/// Every test builds its own fake home in a temporary directory and injects the
/// signature check and the release lookups — nothing here reads the host's
/// `~/.local`, `~/.claude`, process table or network.
@Suite struct ClaudeCodeTests {

    // MARK: - Fixtures

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("claude-code-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// A file that starts with a 64-bit Mach-O magic, `size` bytes long.
        @discardableResult
        func machO(_ path: String, size: Int = 64) throws -> URL {
            var bytes = [UInt8](repeating: 0, count: size)
            bytes[0] = 0xCF; bytes[1] = 0xFA; bytes[2] = 0xED; bytes[3] = 0xFE
            return try write(path, Data(bytes))
        }

        @discardableResult
        func write(_ path: String, _ data: Data) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        }

        func write(_ path: String, _ text: String) throws { try write(path, Data(text.utf8)) }

        func symlink(_ path: String, to destination: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
        }

        /// An npm-style package directory at `package` (relative to root).
        func package(_ package: String, version: String, linked: Bool) throws {
            try write(package + "/package.json", #"{"name":"@anthropic-ai/claude-code","version":"\#(version)"}"#)
            if linked {
                try machO(package + "/bin/claude.exe")
            } else {
                try write(package + "/bin/claude.exe", "#!/bin/sh\necho 'Error: claude native binary not installed.' >&2\nexit 1\n")
            }
        }

        func scanner(prefixes: [String] = [], signature: ClaudeCodeInstall.Signature = .anthropic) -> ClaudeCodeScanner {
            ClaudeCodeScanner(
                home: home,
                systemPrefixes: prefixes.map { root.appendingPathComponent($0) },
                checkSignature: { _ in signature })
        }
    }

    // MARK: - Scanner: native

    @Test func nativeLauncherIsTheInstallAndItsTargetNamesTheVersion() throws {
        let box = try Sandbox()
        try box.machO("home/.local/share/claude/versions/2.1.266")
        try box.machO("home/.local/share/claude/versions/2.1.274")
        try box.symlink("home/.local/bin/claude", to: box.home.path + "/.local/share/claude/versions/2.1.274")

        let found = box.scanner().scan()
        #expect(found.count == 1)  // the older versions/ entry is a rollback copy, not an install
        let install = try #require(found.first)
        #expect(install.method == .native)
        #expect(install.version == "2.1.274")
        #expect(install.path == box.home.path + "/.local/bin/claude")
        #expect(install.signature == .anthropic)
        #expect(install.problem == nil)
    }

    /// What a failed native install leaves behind: `versions/<v>` as a zero-byte file.
    @Test func nativeLauncherToAnEmptyFileIsReportedAsMissing() throws {
        let box = try Sandbox()
        try box.write("home/.local/share/claude/versions/2.1.280", Data())
        try box.symlink("home/.local/bin/claude", to: box.home.path + "/.local/share/claude/versions/2.1.280")

        let install = try #require(box.scanner().scan().first)
        #expect(install.problem == .executableMissing)
        #expect(install.signature == nil)
    }

    /// A custom launcher (a regular file) decides its own version; without running
    /// it we cannot say which, so it is not claimed as a native install.
    @Test func customLauncherIsNotClaimed() throws {
        let box = try Sandbox()
        try box.machO("home/.local/share/claude/versions/2.1.274")
        try box.write("home/.local/bin/claude", "#!/bin/sh\nexec ~/.local/share/claude/versions/2.1.274 \"$@\"\n")
        #expect(box.scanner().scan().isEmpty)
    }

    // MARK: - Scanner: npm family

    @Test func npmPackageUnderANodePrefixCarriesThatPrefix() throws {
        let box = try Sandbox()
        try box.package("brew/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)

        let install = try #require(box.scanner(prefixes: ["brew"]).scan().first)
        #expect(install.method == .npm)
        #expect(install.version == "2.1.280")
        #expect(install.nodePrefix == box.root.appendingPathComponent("brew").path)
        #expect(install.problem == nil)
    }

    @Test func everyNvmNodeVersionIsItsOwnInstall() throws {
        let box = try Sandbox()
        try box.package("home/.nvm/versions/node/v22.1.0/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.259", linked: true)
        try box.package("home/.nvm/versions/node/v24.13.0/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)

        let found = box.scanner().scan()
        #expect(found.map(\.version) == ["2.1.259", "2.1.280"])
        #expect(Set(found.compactMap(\.nodePrefix)).count == 2)
    }

    /// pnpm 10 skips postinstall by default: the package is there, the binary is not.
    @Test func placeholderScriptIsNotLinked() throws {
        let box = try Sandbox()
        try box.package("home/Library/pnpm/global/5/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: false)

        let install = try #require(box.scanner().scan().first)
        #expect(install.method == .pnpm)
        #expect(install.problem == .nativeBinaryNotLinked)
        #expect(install.signature == nil)
    }

    @Test func aDifferentPackageInTheSamePlaceIsIgnored() throws {
        let box = try Sandbox()
        try box.write("brew/lib/node_modules/@anthropic-ai/claude-code/package.json", #"{"name":"not-claude","version":"1.0.0"}"#)
        #expect(box.scanner(prefixes: ["brew"]).scan().isEmpty)
    }

    // MARK: - Scanner: user-added paths

    @Test func userAddedPackageUnderAPrefixWithItsOwnNpmIsNpm() throws {
        let box = try Sandbox()
        try box.package("custom/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)
        try box.write("custom/bin/npm", "#!/usr/bin/env node\n")

        let install = try #require(box.scanner().scan(userPaths: [box.root.path + "/custom/lib/node_modules/@anthropic-ai/claude-code"]).first)
        #expect(install.origin == .userAdded)
        #expect(install.method == .npm)
        #expect(install.nodePrefix == box.root.appendingPathComponent("custom").standardizedFileURL.path)
    }

    @Test func userAddedPackageWithoutAnNpmIsUnknown() throws {
        let box = try Sandbox()
        try box.package("loose/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)

        let install = try #require(box.scanner().scan(userPaths: [box.root.path + "/loose/lib/node_modules/@anthropic-ai/claude-code"]).first)
        #expect(install.method == .unknown)
        #expect(install.nodePrefix == nil)
    }

    /// A bare file is only believed to be Claude Code on the strength of its signature.
    @Test func userAddedBinaryNeedsAnthropicsSignature() throws {
        let box = try Sandbox()
        let binary = try box.machO("elsewhere/claude")
        #expect(box.scanner(signature: .otherSigner).scan(userPaths: [binary.path]).isEmpty)
        #expect(box.scanner(signature: .anthropic).scan(userPaths: [binary.path]).count == 1)
    }

    /// Claude.app ships its own copy at `…/claude-code/<v>/claude.app/Contents/MacOS/claude`:
    /// signed by Anthropic, and still the app's to update, never ours.
    @Test func aBinaryInsideAnAppIsNeverAnInstall() throws {
        let box = try Sandbox()
        let bundled = try box.machO("support/claude-code/2.1.284/claude.app/Contents/MacOS/claude")
        #expect(box.scanner().scan(userPaths: [bundled.path]).isEmpty)
    }

    /// The `cua-driver` shape: a symlink outside, pointing into a bundle.
    @Test func aSymlinkIntoAnAppIsNeverAnInstall() throws {
        let box = try Sandbox()
        let bundled = try box.machO("Apps/Tool.app/Contents/MacOS/claude")
        try box.symlink("home/bin/claude", to: bundled.path)
        #expect(box.scanner().scan(userPaths: [box.home.path + "/bin/claude"]).isEmpty)
        #expect(ClaudeCodeScanner.owningApp(of: box.home.path + "/bin/claude")?.lastPathComponent == "Tool.app")
    }

    /// An app that embeds a whole node prefix, found through the conventional roots.
    @Test func anNpmPackageInsideAnAppIsNeverAnInstall() throws {
        let box = try Sandbox()
        try box.package("Host.app/Contents/Resources/node/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)
        #expect(box.scanner(prefixes: ["Host.app/Contents/Resources/node"]).scan().isEmpty)
    }

    @Test func pathsOutsideAnyAppHaveNoOwner() {
        #expect(ClaudeCodeScanner.owningApp(of: "/Users/x/.local/share/claude/versions/2.1.274") == nil)
        #expect(ClaudeCodeScanner.owningApp(of: "/Users/x/.nvm/versions/node/v24/lib/node_modules/@anthropic-ai/claude-code") == nil)
        #expect(ClaudeCodeScanner.owningApp(of: nil) == nil)
    }

    @Test func userAddedDuplicateOfAConventionalInstallIsListedOnce() throws {
        let box = try Sandbox()
        try box.machO("home/.local/share/claude/versions/2.1.274")
        try box.symlink("home/.local/bin/claude", to: box.home.path + "/.local/share/claude/versions/2.1.274")
        #expect(box.scanner().scan(userPaths: [box.home.path + "/.local/bin/claude"]).count == 1)
    }

    // MARK: - Settings

    func locations(_ box: Sandbox) -> ClaudeCodeSettings.Locations {
        ClaudeCodeSettings.Locations(
            userSettings: box.root.appendingPathComponent("home/.claude/settings.json"),
            managedDirectory: box.root.appendingPathComponent("managed"),
            managedPreferences: [box.root.appendingPathComponent("prefs/com.anthropic.claudecode.plist")])
    }

    @Test func defaultsAreLatestWithAutoUpdateOn() throws {
        let box = try Sandbox()
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .latest)
        #expect(settings.autoUpdatesEnabled)
        #expect(settings.sources.isEmpty)
    }

    @Test func userSettingsAreRead() throws {
        let box = try Sandbox()
        try box.write("home/.claude/settings.json", #"{"autoUpdatesChannel":"stable","minimumVersion":"2.1.100","env":{"DISABLE_AUTOUPDATER":"1"}}"#)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)
        #expect(settings.minimumVersion == "2.1.100")
        #expect(settings.autoUpdatesDisabled)
        #expect(!settings.updatesDisabled)
        #expect(!settings.autoUpdatesEnabled)
    }

    @Test func managedSettingsBeatUserSettingsKeyByKey() throws {
        let box = try Sandbox()
        try box.write("home/.claude/settings.json", #"{"autoUpdatesChannel":"latest","minimumVersion":"2.1.1"}"#)
        try box.write("managed/managed-settings.json", #"{"autoUpdatesChannel":"stable","env":{"DISABLE_UPDATES":"1"}}"#)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)            // managed wins
        #expect(settings.minimumVersion == "2.1.1")    // unset in managed: user's stands
        #expect(settings.updatesDisabled)
    }

    /// `managed-settings.json` first, then `managed-settings.d/*.json` alphabetically;
    /// later files win, hidden files are skipped.
    @Test func managedDropInsMergeInOrder() throws {
        let box = try Sandbox()
        try box.write("managed/managed-settings.json", #"{"autoUpdatesChannel":"latest"}"#)
        try box.write("managed/managed-settings.d/10-a.json", #"{"autoUpdatesChannel":"stable","env":{"A":"1"}}"#)
        try box.write("managed/managed-settings.d/20-b.json", #"{"env":{"DISABLE_AUTOUPDATER":"1"}}"#)
        try box.write("managed/managed-settings.d/.30-hidden.json", #"{"autoUpdatesChannel":"latest"}"#)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)
        #expect(settings.autoUpdatesDisabled)
    }

    /// First-wins across managed sources: an MDM profile hides the managed files.
    @Test func mdmProfileWinsTheManagedTier() throws {
        let box = try Sandbox()
        try box.write("managed/managed-settings.json", #"{"env":{"DISABLE_UPDATES":"1"}}"#)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["autoUpdatesChannel": "stable"], format: .xml, options: 0)
        try box.write("prefs/com.anthropic.claudecode.plist", plist)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)
        #expect(!settings.updatesDisabled)
    }

    @Test func unknownChannelFallsBackToLatest() {
        let settings = ClaudeCodeSettings.resolve([("x", ["autoUpdatesChannel": "beta"])])
        #expect(settings.channel == .latest)
    }

    @Test(arguments: [
        ("1", true), ("true", true), ("yes", true),
        ("0", false), ("false", false), ("", false), (" ", false),
    ])
    func switchValues(value: String, expected: Bool) {
        #expect(ClaudeCodeSettings.isSet(value) == expected)
    }

    // MARK: - Activity

    let native = ClaudeCodeInstall(
        path: "/h/.local/bin/claude", method: .native, origin: .conventional,
        executable: "/h/.local/share/claude/versions/2.1.274", version: "2.1.274",
        signature: .anthropic, problem: nil)

    let npm = ClaudeCodeInstall(
        path: "/p/lib/node_modules/@anthropic-ai/claude-code", method: .npm, origin: .conventional,
        executable: "/p/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe", version: "2.1.280",
        signature: .anthropic, problem: nil, nodePrefix: "/p")

    func emptyStaging() throws -> (Sandbox, URL) {
        let box = try Sandbox()
        let staging = box.root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return (box, staging)
    }

    @Test func runningClaudeUpdateMakesTheNativeInstallBusy() throws {
        let (box, staging) = try emptyStaging()
        _ = box
        let processes = [
            ClaudeCodeActivity.Process(pid: 10, arguments: ["claude"]),  // an ordinary session
            ClaudeCodeActivity.Process(pid: 11, arguments: ["/h/.local/share/claude/versions/2.1.274", "update"]),
        ]
        #expect(ClaudeCodeActivity.busy(native, processes: processes, stagingDirectory: staging) == .updateCommand(11))
        #expect(ClaudeCodeActivity.busy(native, processes: [processes[0]], stagingDirectory: staging) == nil)
    }

    /// `staging/<version>.<pid>.<ms>` — busy only while that pid is alive; a failed
    /// install leaves the directory behind with a dead pid.
    @Test func stagingDirectoryCountsOnlyWhileItsProcessLives() throws {
        let (box, staging) = try emptyStaging()
        _ = box
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("2.1.280.1352.1790771006787"), withIntermediateDirectories: true)
        #expect(ClaudeCodeActivity.busy(native, processes: [], stagingDirectory: staging, isAlive: { $0 == 1352 })
            == .staging(version: "2.1.280", pid: 1352))
        #expect(ClaudeCodeActivity.busy(native, processes: [], stagingDirectory: staging, isAlive: { _ in false }) == nil)
    }

    @Test func npmInstallingThePackageMakesTheNpmInstallBusy() throws {
        let (box, staging) = try emptyStaging()
        _ = box
        let installing = ClaudeCodeActivity.Process(
            pid: 20, arguments: ["node", "/p/lib/node_modules/npm/bin/npm-cli.js", "install", "-g", "@anthropic-ai/claude-code@latest"])
        let unrelated = ClaudeCodeActivity.Process(pid: 21, arguments: ["node", "server.js"])
        #expect(ClaudeCodeActivity.busy(npm, processes: [unrelated, installing], stagingDirectory: staging) == .packageManager(20))
        #expect(ClaudeCodeActivity.busy(npm, processes: [unrelated], stagingDirectory: staging) == nil)
        // A running `claude` session whose argv mentions the package is not a package manager.
        let session = ClaudeCodeActivity.Process(pid: 22, arguments: ["/p/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"])
        #expect(ClaudeCodeActivity.busy(npm, processes: [session], stagingDirectory: staging) == nil)
    }

    @Test func processArgumentsOfThisProcessAreReadable() throws {
        let arguments = try #require(ClaudeCodeActivity.arguments(of: getpid()))
        #expect(arguments.first == CommandLine.arguments.first)
    }

    // MARK: - Check

    func check(latest: String, manifestSize: Int? = nil) -> ClaudeCodeCheck {
        ClaudeCodeCheck(
            latest: { _, _ in latest },
            manifest: { _ in
                guard let manifestSize else { throw ClaudeCodeRelease.Failure.unreadable }
                return .init(size: manifestSize, sha256: "")
            })
    }

    @Test func nativeUpdateIsOfferedAsClaudeUpdate() async {
        let status = await check(latest: "2.1.285").status(of: native, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == .init(executable: "/h/.local/bin/claude", arguments: ["update"], pathPrefix: nil))
        #expect(status.note == nil)
    }

    @Test func autoUpdateOffMeansReportedButNotOffered() async {
        var settings = ClaudeCodeSettings()
        settings.autoUpdatesDisabled = true
        let status = await check(latest: "2.1.285").status(of: native, settings: settings, busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.note?.contains("DISABLE_AUTOUPDATER") == true)
    }

    @Test func updatesDisabledMeansReportedButNotOffered() async {
        var settings = ClaudeCodeSettings()
        settings.updatesDisabled = true
        let status = await check(latest: "2.1.285").status(of: native, settings: settings, busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
    }

    @Test func anUpdateAlreadyRunningWithholdsOneClick() async {
        let status = await check(latest: "2.1.285").status(of: native, settings: ClaudeCodeSettings(), busy: .updateCommand(7))
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.note == ClaudeCodeActivity.Busy.updateCommand(7).description)
    }

    @Test func aChannelBelowTheFloorIsNotAnUpdate() async {
        var settings = ClaudeCodeSettings()
        settings.minimumVersion = "2.1.300"
        let status = await check(latest: "2.1.285").status(of: native, settings: settings, busy: nil)
        #expect(status.state == .upToDate)
        #expect(status.oneClick == nil)
    }

    @Test func aheadOfTheChannelIsNotAnUpdate() async {
        let status = await check(latest: "2.1.270").status(of: native, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .ahead)
        #expect(status.oneClick == nil)
    }

    /// The npm command names this prefix's own node and npm, pins `--prefix`, and
    /// asks for the dist-tag of the user's channel.
    @Test func npmUpdateUsesThePrefixesOwnNpmAndChannel() async throws {
        let box = try Sandbox()
        try box.write("p/bin/npm", "#!/usr/bin/env node\n")
        let node = try box.write("p/bin/node", Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let prefix = box.root.appendingPathComponent("p").path
        let install = ClaudeCodeInstall(
            path: prefix + "/lib/node_modules/@anthropic-ai/claude-code", method: .npm, origin: .conventional,
            executable: nil, version: "2.1.280", signature: .anthropic, problem: nil, nodePrefix: prefix)
        var settings = ClaudeCodeSettings()
        settings.channel = .stable

        let status = await check(latest: "2.1.285").status(of: install, settings: settings, busy: nil)
        let command = try #require(status.oneClick)
        #expect(command.executable == prefix + "/bin/node")
        #expect(command.arguments == [prefix + "/bin/npm", "install", "-g", "--prefix", prefix, "@anthropic-ai/claude-code@stable"])
        #expect(command.pathPrefix == prefix + "/bin")
    }

    @Test func npmPrefixWithoutItsOwnNodeIsNotOffered() async {
        let status = await check(latest: "2.1.285").status(of: npm, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
    }

    @Test func pnpmAndUnknownInstallsAreDetectionOnly() async {
        for method in [ClaudeCodeInstall.Method.pnpm, .bun, .unknown] {
            let install = ClaudeCodeInstall(
                path: "/x", method: method, origin: .conventional, executable: nil, version: "2.1.280",
                signature: .anthropic, problem: nil)
            let status = await check(latest: "2.1.285").status(of: install, settings: ClaudeCodeSettings(), busy: nil)
            #expect(status.state == .updateAvailable)
            #expect(status.oneClick == nil, "\(method)")
        }
    }

    @Test func aFileThatIsNotTheReleaseItsLayoutNamesIsNotOffered() async throws {
        let box = try Sandbox()
        let binary = try box.machO("home/.local/share/claude/versions/2.1.274", size: 100)
        let install = ClaudeCodeInstall(
            path: "/h/.local/bin/claude", method: .native, origin: .conventional,
            executable: binary.path, version: "2.1.274", signature: .anthropic, problem: nil)

        let mismatch = await check(latest: "2.1.285", manifestSize: 99).status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(mismatch.versionConfirmed == false)
        #expect(mismatch.oneClick == nil)

        let match = await check(latest: "2.1.285", manifestSize: 100).status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(match.versionConfirmed == true)
        #expect(match.oneClick != nil)
    }

    @Test func notAnthropicsIsNeverCompared() async {
        let install = ClaudeCodeInstall(
            path: "/x", method: .native, origin: .conventional, executable: "/x", version: "2.1.1",
            signature: .otherSigner, problem: nil)
        let status = await check(latest: "2.1.285").status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.oneClick == nil)
    }
}
